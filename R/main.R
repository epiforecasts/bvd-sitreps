#!/usr/bin/env Rscript
#'
#' Run the whole pipeline in order, stopping at the first step that fails.
#'
#' Each step is its own Rscript process rather than being `source()`d into one
#' session. A step that leaves state behind cannot then change how a later one
#' behaves, and each step's exit status means what it says: the QA gate in
#' 05-check-corpus.R exits non-zero when the corpus does not hold up, and that
#' has to stop the run rather than scroll past.
#'
#' Order follows dependency, not the order a reader might expect: tables are
#' written to CSV before translation, because each English page links its
#' report's CSVs.
#'
#' The WHO steps run last and are independent of INSP's: they need the network
#' but no API key, and nothing upstream reads what they write. They sit after
#' the gate deliberately. A corpus that has failed its own checks is not a
#' corpus to add sources to, and a run that stops there should stop entirely
#' rather than half-refresh.
#'
#' Usage:
#'     Rscript R/main.R

steps <- c(
    "01-fetch-pdfs.R",
    "02-build-corpus.R",
    "03-tables-to-csv.R",
    "04-translate.R",
    "05-check-corpus.R",
    "06-fetch-who.R",
    "07-who-pages.R"
)

for (step in steps) {
    message("\n==> ", step)
    status <- system2("Rscript", here::here("R", step))
    if (status == 3L) {
        message("\n", step, " stopped at the API quota. Rerun after it resets ",
            "(midnight Pacific); finished reports are cached.")
        quit(status = 3L)
    }
    if (status != 0L) {
        stop(step, " exited with status ", status, "; stopping.", call. = FALSE)
    }
}

message("\nPipeline complete.")
