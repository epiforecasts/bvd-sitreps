#!/usr/bin/env Rscript
#'
#' Translate the French corpus into English pages for the public site.
#'
#' Text in, text out. No PDF is opened here: the input is the French
#' markdown and table JSON that 02-build-corpus.R wrote, so a translation
#' error can never reach the corpus of record, and the English is always a
#' view of something checkable.
#'
#' Tables are translated too - captions, headers and label cells - because a
#' reader who needs the English page cannot read `Patients au lit (J-1)`.
#' Translating a table is where a model is most tempted to tidy a number, so
#' each translated table is held to two checks before it is written: the same
#' shape as the French, and the same numbers in every row.
#'
#' Usage:
#'     Rscript R/04-translate.R [--only=007,040] [--force]

suppressMessages({
    library(data.table)
})
source(here::here("R", "lib", "paths.R"))
source(here::here("R", "lib", "gemini.R"))

args <- commandArgs(trailingOnly = TRUE)
only <- grep("^--only=", args, value = TRUE)
ONLY <- if (length(only)) trimws(strsplit(sub("^--only=", "", only[1]), ",")[[1]]) else NULL
FORCE <- "--force" %in% args

REPO_URL <- "https://github.com/epiforecasts/bvd-sitreps/blob/main"

PROMPT <- paste(readLines(here::here("assets", "prompt-translate.md"),
    warn = FALSE), collapse = "\n")

ROW <- list(type = "OBJECT",
    properties = list(cells = list(type = "ARRAY", items = list(type = "STRING"))),
    required = list("cells"))

SCHEMA <- list(
    type = "OBJECT",
    properties = list(
        body_markdown = list(type = "STRING"),
        tables = list(type = "ARRAY", items = list(
            type = "OBJECT",
            properties = list(
                n = list(type = "INTEGER"),
                caption = list(type = "STRING"),
                columns = list(type = "ARRAY", items = list(type = "STRING")),
                rows = list(type = "ARRAY", items = ROW)
            ),
            required = list("n", "caption", "columns", "rows"),
            propertyOrdering = list("n", "caption", "columns", "rows")
        ))
    ),
    required = list("body_markdown", "tables"),
    propertyOrdering = list("body_markdown", "tables")
)

TABLE_INSTRUCTION <- paste(
    "The JSON after the markdown holds this report's tables.",
    "Translate each table's caption, column headers and any text cells into English,",
    "following the same rules. Return every table with the same n, the same number",
    "of columns, the same number of rows in the same order, and every number, date,",
    "code, place name and `ND` unchanged in its cell."
)

`%||%` <- function(a, b) if (is.null(a)) b else a

digits_of <- function(x) {
    out <- regmatches(x, gregexpr("[0-9]+(?:[.,][0-9]+)?", x))[[1]]
    sort(out)
}

#' Hold a translated table to the French one it came from.
#'
#' Shape first, then the numbers row by row. A translated table that has
#' gained or lost a row, or changed a figure, is an error: the English page
#' is public and a reader has no way to notice.
check_translation <- function(fr, en, id) {
    if (length(fr) != length(en)) {
        stop(id, ": French has ", length(fr), " tables, English has ",
            length(en), ".", call. = FALSE)
    }
    for (i in seq_along(fr)) {
        a <- fr[[i]]; b <- en[[i]]
        if (length(a$columns) != length(b$columns) ||
            length(a$rows) != length(b$rows)) {
            stop(id, " table ", a$n, ": translation changed the table's shape.",
                call. = FALSE)
        }
        for (j in seq_along(a$rows)) {
            fa <- digits_of(paste(unlist(a$rows[[j]]$cells), collapse = " "))
            fb <- digits_of(paste(unlist(b$rows[[j]]$cells), collapse = " "))
            if (!identical(fa, fb)) {
                stop(id, " table ", a$n, " row ", j,
                    ": numbers differ after translation (",
                    paste(fa, collapse = " "), " vs ", paste(fb, collapse = " "),
                    ").", call. = FALSE)
            }
        }
    }
    invisible(TRUE)
}

md_escape <- function(x) gsub("\\|", "\\\\|", x)

render_table <- function(tb) {
    cols <- md_escape(unlist(tb$columns))
    head <- paste0("| ", paste(cols, collapse = " | "), " |")
    rule <- paste0("|", paste(rep("---", length(cols)), collapse = "|"), "|")
    body <- vapply(tb$rows, function(r) {
        paste0("| ", paste(md_escape(unlist(r$cells)), collapse = " | "), " |")
    }, character(1))
    cap <- if (nzchar(tb$caption %||% "")) paste0("\n: ", tb$caption) else ""
    paste(c(head, rule, body), collapse = "\n") |> paste0(cap)
}

#' Put each rendered table back where the transcription marked it.
insert_tables <- function(body, tables) {
    for (tb in tables) {
        marker <- paste0("[TABLE_", tb$n, "]")
        if (grepl(marker, body, fixed = TRUE)) {
            body <- sub(marker, paste0("\n", render_table(tb), "\n"), body, fixed = TRUE)
        } else {
            body <- paste0(body, "\n\n", render_table(tb), "\n")
        }
    }
    body
}

read_front <- function(lines) {
    end <- which(lines == "---")
    kv <- lines[(end[1] + 1):(end[2] - 1)]
    list(
        meta = setNames(as.list(trimws(sub("^[^:]*:", "", kv))), sub(":.*$", "", kv)),
        body = paste(lines[-(1:end[2])], collapse = "\n")
    )
}

translate_one <- function(id) {
    fr_path <- corpus_fr_dir(paste0(id, ".md"))
    tb_path <- corpus_tables_dir(paste0(id, ".json"))
    out <- docs_dir(paste0(id, ".qmd"))

    fr <- read_front(readLines(fr_path, warn = FALSE))
    fr_tables <- jsonlite::fromJSON(tb_path, simplifyVector = FALSE)$tables

    # Keyed on the French file's own build key as well as this step's prompt
    # and model, so a rebuilt transcription or a changed translation prompt
    # both flow through to the English page.
    key <- paste(fr$meta$build_key,
        digest::digest(PROMPT, algo = "md5", serialize = FALSE),
        GEMINI_MODEL_TRANSLATE, sep = ":")
    if (!FORCE && file.exists(out)) {
        if (paste0("translate_key: \"", key, "\"") %in%
            readLines(out, n = 15, warn = FALSE)) {
            return("cached")
        }
    }

    res <- gemini(
        parts = list(gemini_text_part(paste(
            PROMPT, "\n\n---\n\n", fr$body, "\n\n---\n\n", TABLE_INSTRUCTION,
            "\n\n", jsonlite::toJSON(fr_tables, auto_unbox = TRUE)))),
        schema = SCHEMA,
        model = GEMINI_MODEL_TRANSLATE,
        label = paste0(id, "/translate")
    )
    check_translation(fr_tables, res$tables, id)

    sitrep <- fr$meta$sitrep
    front <- c(
        "---",
        sprintf('title: "SitRep %s"', sitrep),
        sprintf('subtitle: "Report date %s"', fr$meta$report_date),
        paste0("date: ", fr$meta$report_date),
        paste0("sitrep: \"", sitrep, "\""),
        paste0("pdf_md5: ", fr$meta$pdf_md5),
        paste0("model: ", GEMINI_MODEL_TRANSLATE),
        paste0("translate_key: \"", key, "\""),
        "lang: en",
        "---",
        "",
        "::: {.callout-caution}",
        paste("Machine translation from the French original with Google Gemini,",
            "with no human review. Check the original before relying on any figure."),
        ":::",
        ""
    )

    csvs <- list.files(csv_dir(), pattern = paste0("^", id, "_table_"))
    sources <- c(
        "", "## Source", "",
        paste0("- [Original PDF (French), INSP](", fr$meta$pdf_url, ")"),
        paste0("- [French transcription](", REPO_URL, "/data/corpus/fr/", id, ".md)"),
        if (length(csvs)) paste0("- [", sub("\\.csv$", "", csvs), "](",
            REPO_URL, "/data/csv/", csvs, ")")
    )

    writeLines(c(front, insert_tables(res$body_markdown, res$tables), sources), out)
    "translated"
}

ensure_dirs()

ids <- tools::file_path_sans_ext(list.files(corpus_fr_dir(), pattern = "\\.md$"))
if (!is.null(ONLY)) ids <- intersect(ids, ONLY)
if (!length(ids)) {
    stop("Nothing in the corpus. Run Rscript R/02-build-corpus.R first.", call. = FALSE)
}

status <- character(length(ids))
quota <- NULL
for (i in seq_along(ids)) {
    status[i] <- tryCatch({
        s <- translate_one(ids[i])
        message(sprintf("[%3d/%3d] %s %s", i, length(ids), ids[i], s))
        s
    }, gemini_quota_stop = function(e) {
        quota <<- e
        "stopped"
    }, error = function(e) {
        message(sprintf("[%3d/%3d] %s FAILED: %s", i, length(ids), ids[i],
            conditionMessage(e)))
        "failed"
    })
    if (!is.null(quota)) break
}

message("\ntranslated ", sum(status == "translated"), ", cached ",
    sum(status == "cached"), ", failed ", sum(status == "failed"),
    ", not yet attempted ", sum(status %in% c("", "stopped")))

# Exit 3: stopped for quota, as in 02-build-corpus.R. Rerun to resume.
if (!is.null(quota)) {
    message("\nSTOPPED: ", conditionMessage(quota))
    quit(status = 3L)
}
if (any(status == "failed")) quit(status = 1L)
