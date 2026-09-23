#!/usr/bin/env Rscript
#'
#' Fetch WHO's own accounts of this outbreak: Disease Outbreak News and the
#' AFRO weekly external situation reports.
#'
#' INSP's daily reports are the record of what the response said. WHO writes
#' about the same epidemic from outside it, in English, on a different
#' schedule, and the two disagree in useful ways. Anything reading this corpus
#' gets a second account for the cost of a second directory.
#'
#' The two arrive differently. A Disease Outbreak News is prose in a JSON API,
#' so there is nothing to transcribe. A weekly situation report is a PDF in
#' IRIS with a text layer, so it is read with pdftools: a text layer that
#' exists beats one a model invents, and it costs nothing. Neither needs the
#' Gemini transcription that INSP's scanned PDFs do.
#'
#' Every document is written as front matter plus body, the same shape as
#' `data/corpus/fr/`, and rendering is checked to be reproducible before
#' anything is written: a corpus whose text changes between builds cannot
#' carry a quote check, and bvd-capacity's extraction depends on one.
#'
#' Both publications are © World Health Organization, CC BY-NC-SA 3.0 IGO.
#' `data/corpus/LICENSE-who.md` records that. The repository's own licence
#' covers the code, never the sources.
#'
#' Usage:
#'     Rscript R/06-fetch-who.R [--dons] [--afro] [--refresh]
#'
#' With neither flag, both are fetched.

suppressMessages({
    library(data.table)
})
source(here::here("R", "lib", "paths.R"))
source(here::here("R", "lib", "who.R"))

args <- commandArgs(trailingOnly = TRUE)
REFRESH <- "--refresh" %in% args
DO_DONS <- "--dons" %in% args || !any(c("--dons", "--afro") %in% args)
DO_AFRO <- "--afro" %in% args || !any(c("--dons", "--afro") %in% args)

ensure_dirs()

rows <- list()

# ------------------------------------------------------ Disease Outbreak News

if (DO_DONS) {
    index <- don_index()
    message(nrow(index), " Disease Outbreak News match, ",
        min(index$published), " to ", max(index$published), ".")

    for (i in seq_len(nrow(index))) {
        id <- index$id[i]
        raw_path <- who_raw_dir(paste0(id, ".json"))
        if (!file.exists(raw_path) || REFRESH) {
            rec <- don_record(id)
            jsonlite::write_json(rec, raw_path, auto_unbox = TRUE, pretty = TRUE)
        }
        rec <- jsonlite::fromJSON(raw_path, simplifyVector = FALSE)

        body <- vapply(DON_SECTIONS, function(s) html_to_text(rec[[s]]),
            character(1))
        keep <- nzchar(body)
        text <- render_document(list(
            id = id, source = "who_don",
            publisher = "World Health Organization",
            title = rec$Title,
            report_date = substr(rec$PublicationDateAndTime, 1, 10),
            url = paste0("https://www.who.int/emergencies/",
                "disease-outbreak-news/item/", id),
            licence = "CC BY-NC-SA 3.0 IGO", lang = "en"),
            paste(paste0("## ", DON_SECTIONS[keep], "\n\n", body[keep]),
                collapse = "\n\n"))

        path <- who_don_dir(paste0(id, ".md"))
        writeLines(text, path)
        back <- paste(readLines(path, warn = FALSE), collapse = "\n")
        if (!identical(text, back)) {
            stop("render is not reproducible for ", id)
        }

        rows[[length(rows) + 1L]] <- data.table(
            id = id, source = "who_don", title = rec$Title,
            report_date = as.Date(substr(rec$PublicationDateAndTime, 1, 10)),
            chars = nchar(text), path = file.path("data", "corpus", "who-dons",
                paste0(id, ".md")),
            url = paste0("https://www.who.int/emergencies/",
                "disease-outbreak-news/item/", id),
            licence = "CC BY-NC-SA 3.0 IGO")
        message(sprintf("[%2d/%2d] %s  %s  %6d chars", i, nrow(index), id,
            index$published[i], nchar(text)))
    }
}

# ------------------------------------------ AFRO weekly situation reports

if (DO_AFRO) {
    items <- iris_search(
        query = '"Bundibugyo" AND "External Situation Report"',
        title_pattern = "Weekly External Situation Report")
    message("\n", nrow(items), " AFRO weekly situation reports on IRIS, ",
        min(items$published), " to ", max(items$published), ".")

    #' The report number is in the title (`Weekly External Situation Report
    #' 19, Data as of ...`) and is the publisher's own filing label, so the
    #' corpus is keyed on it rather than on a UUID nobody can read.
    items[, number := sub("^.*Report (\\d+).*$", "\\1", title)]
    items[, id := sprintf("afro-%02d", as.integer(number))]

    for (i in seq_len(nrow(items))) {
        it <- items[i]
        pdf_path <- who_pdf_dir(paste0(it$id, ".pdf"))
        if (!file.exists(pdf_path) || REFRESH) {
            url <- iris_pdf_url(it$uuid)
            if (is.na(url)) {
                message("  ", it$id, ": no PDF bitstream, skipped")
                next
            }
            iris_download(url, pdf_path)
        }

        body <- pdf_to_text(pdf_path)
        text <- render_document(list(
            id = it$id, source = "who_afro",
            publisher = "World Health Organization Regional Office for Africa",
            title = it$title, report_date = as.character(it$published),
            url = paste0("https://iris.who.int/handle/", it$handle),
            licence = "CC BY-NC-SA 3.0 IGO", lang = "en",
            pdf_md5 = unname(tools::md5sum(pdf_path)),
            handle = it$handle), body)

        path <- who_afro_dir(paste0(it$id, ".md"))
        writeLines(text, path)
        back <- paste(readLines(path, warn = FALSE), collapse = "\n")
        if (!identical(text, back)) stop("render is not reproducible for ", it$id)

        rows[[length(rows) + 1L]] <- data.table(
            id = it$id, source = "who_afro", title = it$title,
            report_date = it$published, chars = nchar(text),
            path = file.path("data", "corpus", "who-afro", paste0(it$id, ".md")),
            url = paste0("https://iris.who.int/handle/", it$handle),
            licence = "CC BY-NC-SA 3.0 IGO")
        message(sprintf("[%2d/%2d] %s  %s  %6d chars  %s", i, nrow(items),
            it$id, it$published, nchar(text), basename(pdf_path)))
    }
}

# ----------------------------------------------------------------- manifest

if (length(rows)) {
    fresh <- rbindlist(rows, fill = TRUE)
    held <- if (file.exists(who_manifest_path())) {
        fread(who_manifest_path(), colClasses = list(character = "id"))
    } else NULL
    manifest <- if (is.null(held)) fresh else {
        rbind(held[!id %in% fresh$id], fresh, fill = TRUE)
    }
    setorder(manifest, source, report_date)
    fwrite(manifest, who_manifest_path())
    message("\n", nrow(manifest), " WHO documents in ", who_manifest_path())
    print(manifest[, .(documents = .N, chars = sum(chars)), keyby = source])
}

licence <- here::here("data", "corpus", "LICENSE-who.md")
if (!file.exists(licence)) {
    writeLines(c(
        "# WHO material in this corpus",
        "",
        "`data/corpus/who-dons/` and `data/corpus/who-afro/` hold documents",
        "published by the World Health Organization, not by INSP and not by",
        "this repository's authors.",
        "",
        "© World Health Organization. Licensed CC BY-NC-SA 3.0 IGO:",
        "<https://creativecommons.org/licenses/by-nc-sa/3.0/igo/>",
        "",
        "Disease Outbreak News is reproduced from WHO's public API; the AFRO",
        "weekly external situation reports are reproduced from the PDFs",
        "deposited in IRIS, WHO's institutional repository, with their text",
        "layer extracted and nothing else changed. Each file names its source",
        "URL in its front matter.",
        "",
        "Use is non-commercial, attribution to WHO is required, and anything",
        "built on this text carries the same terms. WHO does not endorse this",
        "repository, its authors, or any use made of its material here."),
        licence)
}
