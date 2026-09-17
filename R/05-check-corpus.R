#!/usr/bin/env Rscript
#'
#' Check the corpus against the PDFs it came from, and fail if it does not
#' hold up.
#'
#' A language model transcribing a document does not fail loudly. It fails by
#' producing something that reads correctly and has a row missing, or a figure
#' altered, and nothing downstream can tell. So the corpus is not trusted
#' because a good model made it; it is trusted because the numbers in it are
#' checked against the numbers in the PDF.
#'
#' The check that does the work is numeric recall: every number printed in the
#' report, as `pdftools::pdf_text()` reads it, should appear somewhere in the
#' corpus. That is a weak check in one direction, since it says nothing about
#' a number landing in the wrong cell, and a strong one in the other, since a
#' dropped row or a rewritten figure shows up immediately. Every INSP original
#' has a text layer, so this covers the whole corpus. Reading the INRB-UMIE
#' mirror instead would have left seven reports with no ground truth at all.
#'
#' Usage:
#'     Rscript R/05-check-corpus.R [--recall=0.95]

suppressMessages({
    library(data.table)
})
source(here::here("R", "lib", "paths.R"))

args <- commandArgs(trailingOnly = TRUE)
rec <- grep("^--recall=", args, value = TRUE)
MIN_RECALL <- if (length(rec)) as.numeric(sub("^--recall=", "", rec[1])) else 0.95

`%||%` <- function(a, b) if (is.null(a)) b else a

#' Every number in a string.
#'
#' Decimal commas are normalised so that `91,3` and `91.3` compare equal.
#' Thousands separators are deliberately not joined: `72 530` is read as `72`
#' and `530` on both sides. Joining them looks more correct and is not, because
#' there is no way to tell a thousands space from the space between two
#' adjacent table cells, and joining merged `18` and `215` into `18215` and
#' reported both as missing from a table that held them. Splitting the same
#' way on both sides keeps the comparison symmetric.
numbers <- function(x) {
    x <- paste(x, collapse = "\n")
    out <- regmatches(x, gregexpr("[0-9]+(?:[.,][0-9]+)?", x))[[1]]
    unique(gsub(",", ".", out))
}

#' The PDF's text, less what the transcription is told to leave out.
#'
#' The prompt removes page numbers and headers and footers that repeat on
#' every page, so their numbers are not expected in the corpus. Counting them
#' flagged SitRep 001 for `Page 9` and a footer reading `No 1/ 202-`. A line
#' is dropped if it is a bare page number, or if it recurs, with its digits
#' masked, on three or more pages.
pdf_numbers <- function(path) {
    pages <- lapply(pdftools::pdf_text(path), function(p) strsplit(p, "\n")[[1]])
    squash <- function(x) trimws(gsub("\\s+", " ", x))
    masked <- lapply(pages, function(l) unique(gsub("[0-9]+", "#", squash(l))))
    recurring <- names(which(table(unlist(masked)) >= 3))
    recurring <- recurring[nzchar(recurring)]
    keep <- unlist(lapply(pages, function(l) {
        sq <- squash(l)
        l[!grepl("^(page|p\\.)?\\s*[0-9]+(\\s*/\\s*[0-9]+)?$", sq, ignore.case = TRUE) &
          !gsub("[0-9]+", "#", sq) %in% recurring]
    }))
    numbers(keep)
}

#' Numbers a person has checked and confirmed need not be in the corpus.
#'
#' Chart axis ticks are the main case: the text layer carries them, and the
#' prompt rightly tells the model not to read values off a chart. Each row in
#' `data/corpus-qa-exemptions.csv` names one number in one report and says
#' why. An exemption is a reviewed decision, not a way to pass the gate: add
#' one only after finding the number in the PDF and confirming it is not
#' content.
read_exemptions <- function() {
    path <- here::here("data", "corpus-qa-exemptions.csv")
    if (!file.exists(path)) {
        return(data.table(id = character(), number = character(), reason = character()))
    }
    fread(path, colClasses = "character")
}

#' Read the front matter written by 02-build-corpus.R.
front_matter <- function(path) {
    lines <- readLines(path, warn = FALSE)
    end <- which(lines == "---")
    if (length(end) < 2) return(list())
    kv <- lines[(end[1] + 1):(end[2] - 1)]
    keys <- sub(":.*$", "", kv)
    vals <- trimws(sub("^[^:]*:", "", kv))
    setNames(as.list(vals), keys)
}

#' Everything the corpus holds for one report, as one string.
corpus_text <- function(id) {
    md <- readLines(corpus_fr_dir(paste0(id, ".md")), warn = FALSE)
    tbl <- corpus_tables_dir(paste0(id, ".json"))
    cells <- character()
    if (file.exists(tbl)) {
        doc <- jsonlite::fromJSON(tbl, simplifyVector = FALSE)
        cells <- unlist(lapply(doc$tables, function(tb) {
            c(unlist(tb$columns), tb$caption,
              unlist(lapply(tb$rows, function(r) unlist(r$cells))))
        }))
    }
    paste(c(md, cells), collapse = " ")
}

ensure_dirs()

if (!file.exists(manifest_path())) {
    stop("No manifest. Run Rscript R/01-fetch-pdfs.R first.", call. = FALSE)
}
manifest <- fread(manifest_path())[!is.na(md5)]

built <- tools::file_path_sans_ext(basename(
    list.files(corpus_fr_dir(), pattern = "\\.md$")))
message(length(built), " reports in the corpus, ", nrow(manifest), " PDFs held")

exemptions <- read_exemptions()

missing <- setdiff(manifest$id, built)
extra <- setdiff(built, manifest$id)

rows <- rbindlist(lapply(built, function(this_id) {
    fm <- front_matter(corpus_fr_dir(paste0(this_id, ".md")))
    man <- manifest[match(this_id, manifest$id)]
    pdf <- pdf_dir(paste0(this_id, ".pdf"))

    truth <- pdf_numbers(pdf)
    exempt <- intersect(truth, exemptions[id == this_id]$number)
    truth <- setdiff(truth, exempt)
    got <- numbers(corpus_text(this_id))
    tbl <- corpus_tables_dir(paste0(this_id, ".json"))
    n_tables <- if (file.exists(tbl)) {
        length(jsonlite::fromJSON(tbl, simplifyVector = FALSE)$tables)
    } else NA_integer_

    data.table(
        id = this_id,
        sitrep_doc = fm$sitrep %||% NA_character_,
        sitrep_indexed = sprintf("%03d", man$sitrep),
        report_date = fm$report_date %||% NA_character_,
        pdf_md5_now = man$md5,
        pdf_md5_built = fm$pdf_md5 %||% NA_character_,
        n_tables = n_tables,
        n_numbers_pdf = length(truth),
        n_exempt = length(exempt),
        model = fm$model %||% NA_character_,
        recall = if (length(truth)) mean(truth %in% got) else NA_real_,
        missing_numbers = paste(utils::head(setdiff(truth, got), 12), collapse = " ")
    )
}))

# The document is the authority on what report it is. Where it disagrees with
# the number the posts index filed it under, that is worth knowing: it means
# either the index or the report is mislabelled, and downstream work keyed on
# the wrong one would be silently wrong.
rows[, sitrep_mismatch := !is.na(sitrep_doc) &
    gsub("^0+", "", sitrep_doc) != gsub("^0+", "", sitrep_indexed)]
rows[, stale := !is.na(pdf_md5_built) & pdf_md5_built != pdf_md5_now]
rows[, low_recall := !is.na(recall) & recall < MIN_RECALL]

setorder(rows, id)
fwrite(rows, qa_path())

# ---------------------------------------------------------------- report ----

say <- function(label, value) message(sprintf("  %-34s %s", label, value))

message("\nCoverage")
say("PDFs held", nrow(manifest))
say("reports built", length(built))
say("built but no PDF", if (length(extra)) paste(extra, collapse = ", ") else "none")
say("PDF but not built", if (length(missing)) paste(missing, collapse = ", ") else "none")

present <- sort(unique(manifest$sitrep))
say("report numbers never published", paste(sprintf("%03d",
    setdiff(seq_len(max(present)), present)), collapse = ", "))

message("\nFidelity")
say("median numeric recall", sprintf("%.4f", median(rows$recall, na.rm = TRUE)))
say("min numeric recall", sprintf("%.4f", min(rows$recall, na.rm = TRUE)))
say(sprintf("below %.2f", MIN_RECALL), nrow(rows[low_recall == TRUE]))
say("tables extracted", sum(rows$n_tables, na.rm = TRUE))
say("numbers exempted after review", sum(rows$n_exempt))
say("reports by model", paste(names(table(rows$model)), table(rows$model), sep = " ", collapse = ", "))

message("\nConsistency")
say("sitrep number disagrees with index", nrow(rows[sitrep_mismatch == TRUE]))
say("built from a superseded PDF", nrow(rows[stale == TRUE]))

if (nrow(rows[low_recall == TRUE])) {
    message("\nReports below the recall threshold:")
    print(rows[low_recall == TRUE, .(id, recall, n_numbers_pdf, missing_numbers)])
}
if (nrow(rows[sitrep_mismatch == TRUE])) {
    message("\nNumber disagreements (document vs index):")
    print(rows[sitrep_mismatch == TRUE, .(id, sitrep_doc, sitrep_indexed)])
}

message("\nwritten to ", qa_path())

failed <- length(missing) > 0 || nrow(rows[low_recall == TRUE]) > 0 ||
    nrow(rows[stale == TRUE]) > 0
if (failed) {
    message("\nFAIL: the corpus does not yet stand up. See above.")
    quit(status = 1L)
}
message("\nPASS")
