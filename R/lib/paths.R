#' Where everything lives.
#'
#' One function per artefact root, so a layout change is one edit here rather
#' than a grep across five scripts. Paths are relative to the repository, not
#' to a working directory, because the Actions runner and a local session do
#' not share one.

pdf_dir <- function(...) here::here("data", "pdf", ...)

#' The corpus of record: faithful French markdown, one file per report.
corpus_fr_dir <- function(...) here::here("data", "corpus", "fr", ...)

#' Tables lifted out of the body, as validated JSON.
corpus_tables_dir <- function(...) here::here("data", "corpus", "tables", ...)

#' Tables again, flattened to CSV for people who want a spreadsheet.
csv_dir <- function(...) here::here("data", "csv", ...)

#' English translations, one Quarto page per report.
docs_dir <- function(...) here::here("docs", ...)

manifest_path <- function() here::here("data", "manifest.csv")

qa_path <- function() here::here("data", "corpus-qa.csv")

log_dir <- function(...) here::here("outputs", "logs", ...)

#' Create every output directory. Cheap, idempotent, and saves each script
#' from carrying its own dir.create calls.
ensure_dirs <- function() {
    for (d in c(pdf_dir(), corpus_fr_dir(), corpus_tables_dir(),
                csv_dir(), docs_dir(), log_dir())) {
        dir.create(d, recursive = TRUE, showWarnings = FALSE)
    }
    invisible(NULL)
}

#' The canonical id for a report: three digits, plus a version suffix when
#' INSP has published more than one PDF for the same number.
#'
#' Zero-padding is what makes `sort()` on the id agree with report order, and
#' every file in the pipeline is named by this id, so a report's PDF, French
#' markdown, translation and tables all share a stem.
report_id <- function(sitrep, version = 1L) {
    stopifnot(is.numeric(sitrep), !is.na(sitrep))
    ifelse(version > 1L,
        sprintf("%03d_v%d", as.integer(sitrep), as.integer(version)),
        sprintf("%03d", as.integer(sitrep)))
}
