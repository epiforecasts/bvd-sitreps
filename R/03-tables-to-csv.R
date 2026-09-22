#!/usr/bin/env Rscript
#'
#' Flatten the validated table JSON to one CSV per table.
#'
#' This is deliberately dull. All the judgement happened in
#' 02-build-corpus.R, where a table that did not fit its own header stopped
#' the report. By the time a table reaches here it is rectangular, so this
#' script is a shape change and a filename convention, nothing more.
#'
#' The previous version of this step parsed markdown pipe tables with regular
#' expressions, which is where `Indicators` columns turned into `NA` and rows
#' lost their leading label. Reading JSON removes the parsing problem rather
#' than fixing it.
#'
#' Usage:
#'     Rscript R/03-tables-to-csv.R [--only=007,040]

suppressMessages({
    library(data.table)
})
source(here::here("R", "lib", "paths.R"))

args <- commandArgs(trailingOnly = TRUE)
only <- grep("^--only=", args, value = TRUE)
ONLY <- if (length(only)) trimws(strsplit(sub("^--only=", "", only[1]), ",")[[1]]) else NULL

ensure_dirs()

#' Make a column name usable as a CSV header without losing what it said.
#'
#' Duplicates are suffixed rather than dropped: two columns genuinely called
#' `Total` in the document are two columns, and silently merging them would
#' lose a value.
clean_names <- function(x) {
    x <- trimws(x)
    x[!nzchar(x)] <- "col"
    make.unique(x, sep = "_")
}

#' A caption shortened into something that can live in a filename.
slug <- function(x, n = 40) {
    # macOS transliterates `é` to `'e` rather than `e`, which would otherwise
    # leave `r_ecapitulatif` in a filename. Drop the accent marks it inserts.
    x <- iconv(x, to = "ASCII//TRANSLIT")
    x <- gsub("['`^~\"]", "", x)
    x <- tolower(gsub("[^A-Za-z0-9]+", "_", x))
    x <- gsub("^_+|_+$", "", x)
    if (!nzchar(x)) return("")
    substr(x, 1, n)
}

write_tables <- function(path) {
    doc <- jsonlite::fromJSON(path, simplifyVector = FALSE)
    id <- doc$id
    if (!length(doc$tables)) {
        message(id, ": no tables")
        return(0L)
    }
    for (tb in doc$tables) {
        cols <- clean_names(unlist(tb$columns))
        rows <- lapply(tb$rows, function(r) unlist(r$cells))
        m <- as.data.table(do.call(rbind, rows))
        setnames(m, cols)

        label <- slug(tb$caption)
        stem <- if (nzchar(label)) {
            sprintf("%s_table_%02d_%s", id, tb$n, label)
        } else {
            sprintf("%s_table_%02d", id, tb$n)
        }
        fwrite(m, csv_dir(paste0(stem, ".csv")))
    }
    message(id, ": ", length(doc$tables), " tables")
    length(doc$tables)
}

files <- list.files(corpus_tables_dir(), pattern = "\\.json$", full.names = TRUE)
if (!is.null(ONLY)) {
    files <- files[tools::file_path_sans_ext(basename(files)) %in% ONLY]
}
if (!length(files)) {
    stop("No table JSON found. Run Rscript R/02-build-corpus.R first.", call. = FALSE)
}

n <- vapply(files, write_tables, integer(1))
message("\n", sum(n), " tables from ", length(files), " reports written to ", csv_dir())
