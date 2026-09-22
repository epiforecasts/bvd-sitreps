#!/usr/bin/env Rscript
#'
#' Turn each situation report PDF into the corpus of record: faithful French
#' markdown, plus its tables as validated JSON.
#'
#' This is the only script in the repository that opens a PDF. Everything
#' downstream - the English site, the CSVs, and any topic extraction in
#' another repository - reads what this produces. That boundary is the point:
#' three earlier attempts at these reports each rebuilt their own PDF layer,
#' and each inherited its own OCR problems.
#'
#' French, not English. The earlier version of this pipeline translated while
#' transcribing, which cost two things. A claim extracted downstream could no
#' longer be checked against the source document, because the words no longer
#' matched. And the translation made mistakes in exactly the terms that
#' matter: `CTE`, Centre de Traitement Ebola, came out as "Treatment Centers
#' for Epidemics". The French is the record; English is produced from it in
#' 04-translate.R and is clearly a derived view.
#'
#' Output is cached on the PDF's md5, so a rerun costs nothing for reports
#' that have not changed, and a reissued PDF rebuilds because its hash is
#' different.
#'
#' Usage:
#'     Rscript R/02-build-corpus.R [--only=007,040] [--force] [--model=ID]
#'         [--thinking=low]
#'
#' `--model` and `--thinking=low` are for experimenting with `--only` on a
#' report the default model fails. Once a setting works, record it in
#' `assets/model-overrides.csv` so every later run uses it.
#'
#' Long enough to want detaching:
#'     nohup caffeinate -is Rscript R/02-build-corpus.R \
#'         > outputs/logs/corpus_$(date +%F-%H%M).log 2>&1 &

suppressMessages({
    library(data.table)
})
source(here::here("R", "lib", "paths.R"))
source(here::here("R", "lib", "gemini.R"))

args <- commandArgs(trailingOnly = TRUE)
flag <- function(name, default = NULL) {
    hit <- grep(paste0("^--", name, "="), args, value = TRUE)
    if (!length(hit)) return(default)
    sub(paste0("^--", name, "="), "", hit[1])
}
FORCE <- "--force" %in% args
ONLY <- flag("only")
MODEL_FLAG <- flag("model")
THINKING_FLAG <- flag("thinking")

#' Per-report model settings, where the default model fails a report.
#'
#' `assets/model-overrides.csv` holds one row per exception: `id`, `model`,
#' `thinking` (blank for the model's default) and `reason`. A command-line
#' `--model` or `--thinking` beats the file, for experiments; the file beats
#' the default, so every later run, including CI, rebuilds that report the
#' way that worked rather than retrying the way that failed.
OVERRIDES <- local({
    path <- here::here("assets", "model-overrides.csv")
    if (file.exists(path)) fread(path, colClasses = "character") else
        data.table(id = character(), model = character(), thinking = character())
})

settings_for <- function(report) {
    # `report`, not `id`: inside OVERRIDES[...] a variable named `id` is the
    # column, which matched every report to the first override.
    ov <- OVERRIDES[which(OVERRIDES$id == report)]
    model <- MODEL_FLAG %||% (if (nrow(ov) && nzchar(ov$model)) ov$model) %||%
        GEMINI_MODEL_TRANSCRIBE
    thinking <- THINKING_FLAG %||% (if (nrow(ov) && nzchar(ov$thinking)) ov$thinking)
    list(model = model, thinking = thinking)
}

# ----------------------------------------------------------- the schema ----

#' Rows are objects carrying a `cells` array rather than bare nested arrays.
#'
#' An array of arrays is legal in the schema language but is the construction
#' most likely to come back ragged. Wrapping each row makes the shape explicit
#' to the model and gives R one obvious thing to count.
TABLE_SCHEMA <- list(
    type = "OBJECT",
    properties = list(
        n = list(type = "INTEGER"),
        caption = list(type = "STRING"),
        columns = list(type = "ARRAY", items = list(type = "STRING")),
        rows = list(
            type = "ARRAY",
            items = list(
                type = "OBJECT",
                properties = list(
                    cells = list(type = "ARRAY", items = list(type = "STRING"))
                ),
                required = list("cells")
            )
        )
    ),
    required = list("n", "caption", "columns", "rows"),
    propertyOrdering = list("n", "caption", "columns", "rows")
)

REPORT_SCHEMA <- list(
    type = "OBJECT",
    properties = list(
        sitrep = list(type = "STRING"),
        report_date = list(type = "STRING"),
        publication_date = list(type = "STRING"),
        body_markdown = list(type = "STRING"),
        tables = list(type = "ARRAY", items = TABLE_SCHEMA)
    ),
    required = list("sitrep", "report_date", "body_markdown", "tables"),
    propertyOrdering = list("sitrep", "report_date", "publication_date",
        "body_markdown", "tables")
)

PROMPT <- paste(readLines(here::here("assets", "prompt-transcribe.md"),
    warn = FALSE), collapse = "\n")

#' What a corpus file was built from, as one string.
#'
#' The PDF hash alone is not enough. A report built before a prompt fix would
#' match on its PDF, be reported as cached, and never receive the fix, with
#' nothing to show the corpus is now a mix of two prompts. So the key also
#' carries the prompt's hash, the schema's hash and the model: changing any of
#' them rebuilds, and leaving all of them alone costs nothing.
build_key <- function(pdf_md5, model, thinking = NULL) {
    # Built with c() and collapse, not paste(..., sep = ":"): paste turns a
    # NULL argument into "" and appends a trailing ":", which changed every
    # report's key the first time the thinking option was added and rebuilt
    # two reports before it was stopped.
    paste(c(pdf_md5,
        digest::digest(PROMPT, algo = "md5", serialize = FALSE),
        digest::digest(REPORT_SCHEMA, algo = "md5"),
        model,
        # Only when set, so that the option does not change the key of any
        # report built without it.
        if (!is.null(thinking)) paste0("thinking=", thinking)),
        collapse = ":")
}

# ------------------------------------------------------------ validation ----

#' Refuse a table whose rows do not match its header.
#'
#' This is the check the previous pipeline did not have. Its output shifted
#' every value in a row one column left whenever a province cell spanned
#' several rows, and wrote the result to CSV without complaint. A ragged table
#' is a transcription failure, so it stops the report rather than being
#' repaired by guesswork.
validate_tables <- function(tables, id) {
    if (!length(tables)) return(invisible(TRUE))
    for (tb in tables) {
        ncol <- length(tb$columns)
        if (ncol == 0L) {
            stop(id, " table ", tb$n, " has no header row.", call. = FALSE)
        }
        if (!length(tb$rows)) {
            stop(id, " table ", tb$n, " has a header but no rows.", call. = FALSE)
        }
        widths <- vapply(tb$rows, function(r) length(r$cells), integer(1))
        if (any(widths != ncol)) {
            bad <- which(widths != ncol)
            stop(id, " table ", tb$n, ": header has ", ncol, " columns but ",
                length(bad), " row(s) have ",
                paste(unique(widths[bad]), collapse = "/"),
                " (rows ", paste(utils::head(bad, 5), collapse = ", "), ").",
                call. = FALSE)
        }
    }
    invisible(TRUE)
}

#' Check the markdown leaves a marker for each table it lifted out.
#'
#' Without the markers a downstream reader loses the reading order, and a
#' table that was silently dropped from the body looks the same as one that
#' was never there.
check_markers <- function(body, tables, id) {
    if (!length(tables)) return(invisible(TRUE))
    missing <- Filter(function(n) !grepl(paste0("\\[TABLE_", n, "\\]"), body),
        vapply(tables, function(tb) tb$n, integer(1)))
    if (length(missing)) {
        warning(id, ": no [TABLE_n] marker in the body for table(s) ",
            paste(missing, collapse = ", "), call. = FALSE)
    }
    invisible(TRUE)
}

# ------------------------------------------------------------------ run ----

ensure_dirs()

if (!file.exists(manifest_path())) {
    stop("No manifest. Run Rscript R/01-fetch-pdfs.R first.", call. = FALSE)
}
manifest <- fread(manifest_path())
manifest <- manifest[!is.na(md5)]
if (!is.null(ONLY)) {
    want <- trimws(strsplit(ONLY, ",")[[1]])
    manifest <- manifest[id %in% want]
}
setorder(manifest, sitrep, version)

message(nrow(manifest), " reports to consider, default model ",
    MODEL_FLAG %||% GEMINI_MODEL_TRANSCRIBE,
    if (nrow(OVERRIDES)) paste0(", ", nrow(OVERRIDES), " per-report override(s)") else "")

build_one <- function(row) {
    id <- row$id
    fr <- corpus_fr_dir(paste0(id, ".md"))
    tb <- corpus_tables_dir(paste0(id, ".json"))

    # The build key is carried in the markdown's front matter. A reissued PDF,
    # a changed prompt or a new model each change it and rebuild; otherwise
    # the report never costs a second call.
    set <- settings_for(id)
    key <- build_key(row$md5, set$model, set$thinking)
    if (!FORCE && file.exists(fr) && file.exists(tb)) {
        head <- readLines(fr, n = 15, warn = FALSE)
        if (paste0("build_key: ", key) %in% head) {
            return("cached")
        }
    }

    pdf <- pdf_dir(paste0(id, ".pdf"))
    res <- gemini(
        parts = list(gemini_pdf_part(pdf), gemini_text_part(PROMPT)),
        schema = REPORT_SCHEMA,
        model = set$model,
        label = id,
        thinking_level = set$thinking
    )

    validate_tables(res$tables, id)
    check_markers(res$body_markdown, res$tables, id)

    # The document's own number and date are recorded beside the ones the
    # posts index gave. Where they disagree, 05-check-corpus.R says so; the
    # document is the authority, the index was only a filing label.
    front <- c(
        "---",
        paste0("id: ", id),
        paste0("sitrep: ", res$sitrep),
        paste0("sitrep_indexed: ", sprintf("%03d", row$sitrep)),
        paste0("report_date: ", res$report_date),
        paste0("publication_date: ", res$publication_date %||% ""),
        paste0("pdf_md5: ", row$md5),
        paste0("pdf_url: ", row$pdf_url),
        paste0("model: ", set$model),
        if (!is.null(set$thinking)) paste0("thinking: ", set$thinking),
        paste0("build_key: ", key),
        paste0("built: ", as.character(Sys.time())),
        "lang: fr",
        "---",
        ""
    )
    writeLines(c(front, res$body_markdown), fr)
    jsonlite::write_json(list(id = id, sitrep = res$sitrep,
        report_date = res$report_date, pdf_md5 = row$md5,
        tables = res$tables), tb, auto_unbox = TRUE, pretty = TRUE)
    "built"
}

results <- character(nrow(manifest))
quota <- NULL
for (i in seq_len(nrow(manifest))) {
    row <- manifest[i]
    results[i] <- tryCatch({
        out <- build_one(row)
        message(sprintf("[%3d/%3d] %s %s", i, nrow(manifest), row$id, out))
        out
    }, gemini_quota_stop = function(e) {
        quota <<- e
        "stopped"
    }, error = function(e) {
        message(sprintf("[%3d/%3d] %s FAILED: %s", i, nrow(manifest), row$id,
            conditionMessage(e)))
        "failed"
    })
    if (!is.null(quota)) break
}

message("\nbuilt ", sum(results == "built"),
    ", cached ", sum(results == "cached"),
    ", failed ", sum(results == "failed"),
    ", not yet attempted ", sum(results %in% c("", "stopped")))

if (any(results == "failed")) {
    message("failed: ", paste(manifest$id[results == "failed"], collapse = ", "))
}

# Exit 3 means "stopped for quota, nothing wrong": the corpus is partial but
# every report in it is complete, and a rerun resumes where this one stopped.
if (!is.null(quota)) {
    message("\nSTOPPED: ", conditionMessage(quota))
    quit(status = 3L)
}
if (any(results == "failed")) quit(status = 1L)
