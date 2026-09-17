#!/usr/bin/env Rscript
#'
#' Download every INSP situation report PDF from insp.cd.
#'
#' The index is the WordPress posts API, not the media library and not the
#' INRB-UMIE GitHub mirror. Each is worse for a different reason.
#'
#' The mirror is incomplete and lossy: it holds 96 of the 122 reports, and its
#' copy of SitRep 007 has no text layer at all where the INSP original has
#' 39,372 characters. Reading the mirror is what forced OCR into every earlier
#' attempt at this.
#'
#' The media library is complete but unindexed. Filenames there are whatever
#' the author saved that day: `Draft-1-SitRep_MVE_RDC_N°040_23_06_2026.pdf`,
#' `Daft-SitRep_MVE_RDC_N18_01_06_2026_JO_PA-Final-1.pdf`,
#' `SitRep_MVE_RDC_20260701_OK.pdf` with no number at all, and 32 files from
#' the 2025 epidemic under the same prefix. Parsing report numbers out of them
#' recovers 102 of 122 and guesses at several.
#'
#' The posts API carries one post per published report, titled
#' `SitRep N°122/MVEBDB/13/09/2026`, with the PDF's URL base64-encoded in the
#' embedded viewer's `pdfemb-data` parameter. That gives the report number
#' from the publisher rather than from a filename, and reaches 115 of 122.
#' The seven it misses (003, 029, 043, 045, 063, 075, 076) are absent from the
#' mirror too, so they were never published.
#'
#' The number in the title is trusted only as a filing label. What a report
#' says it is, and what date it covers, are read from the document itself in
#' 02-build-corpus.R, and that is what the corpus is keyed on.
#'
#' Usage:
#'     Rscript R/01-fetch-pdfs.R [--refresh]
#'
#' `--refresh` re-downloads PDFs already on disk, to pick up a silently
#' replaced upstream file. Without it, existing PDFs are left alone and only
#' the manifest is rebuilt.

suppressMessages({
    library(data.table)
})
source(here::here("R", "lib", "paths.R"))
source(here::here("R", "lib", "http.R"))

POSTS_API <- "https://insp.cd/wp-json/wp/v2/posts"
PER_PAGE <- 100L
MAX_PAGES <- 20L

REFRESH <- "--refresh" %in% commandArgs(trailingOnly = TRUE)

# ---------------------------------------------------------------- index ----

#' Walk the posts API until it runs out.
#'
#' WordPress reports the page count in a header, but a cache that keeps
#' answering page 1 would leave that promise unkept, so the walk is also
#' capped. A nightly hang is worse than an error.
fetch_posts <- function() {
    out <- list()
    for (page in seq_len(MAX_PAGES)) {
        message("posts page ", page)
        body <- insp_get_json(POSTS_API, list(
            search = "SitRep", per_page = PER_PAGE, page = page
        ))
        if (!length(body)) break
        out <- c(out, body)
        if (length(body) < PER_PAGE) break
    }
    out
}

strip_html <- function(x) {
    x <- gsub("<[^>]+>", "", x)
    x <- gsub("&#8217;|&#039;|&rsquo;", "'", x)
    x <- gsub("&amp;", "&", x)
    trimws(x)
}

#' Pull the PDF URL out of the embedded viewer.
#'
#' The viewer is given its configuration as base64url in a query parameter,
#' and the URL inside it is JSON-escaped (`\/` for every slash). Nothing else
#' in the post body links the PDF, so this is the only route from a post to
#' its file.
post_pdf_url <- function(content) {
    m <- regmatches(content, gregexpr("pdfemb-data=[A-Za-z0-9_-]+", content))[[1]]
    if (!length(m)) return(NA_character_)
    for (token in m) {
        payload <- sub("^pdfemb-data=", "", token)
        payload <- chartr("-_", "+/", payload)
        payload <- paste0(payload, strrep("=", (4L - nchar(payload) %% 4L) %% 4L))
        decoded <- tryCatch(
            rawToChar(jsonlite::base64_dec(payload)),
            error = function(e) NA_character_
        )
        if (is.na(decoded)) next
        parsed <- tryCatch(jsonlite::fromJSON(decoded), error = function(e) NULL)
        url <- if (is.null(parsed)) NA_character_ else parsed$url
        if (!is.null(url) && grepl("\\.pdf$", url, ignore.case = TRUE)) {
            return(gsub("\\\\/", "/", url))
        }
    }
    NA_character_
}

#' The report number as the publisher filed it.
title_sitrep <- function(title) {
    m <- regmatches(title, regexpr("N\\s*[°o]?\\s*0*[0-9]{1,3}", title,
        ignore.case = TRUE))
    if (!length(m)) return(NA_integer_)
    as.integer(sub("^N\\s*[°o]?\\s*0*", "", m, ignore.case = TRUE))
}

#' The date in the title, where there is one.
#'
#' 19 of the 116 titles carry no parseable date. That is not worth chasing:
#' `Date de rapportage` is printed on the report itself and is read in
#' 02-build-corpus.R, which is the value the corpus uses. This one is a
#' cross-check and a sort key for reports not yet built.
title_date <- function(title) {
    m <- regmatches(title, regexpr("[0-9]{1,2}[/_-][0-9]{1,2}[/_-]20[0-9]{2}", title))
    if (!length(m)) return(as.Date(NA))
    as.Date(m, tryFormats = c("%d/%m/%Y", "%d-%m-%Y", "%d_%m_%Y"))
}

build_index <- function(posts) {
    rows <- lapply(posts, function(p) {
        title <- strip_html(p$title$rendered)
        if (!grepl("sitrep", title, ignore.case = TRUE)) return(NULL)
        data.table(
            sitrep = title_sitrep(title),
            title = title,
            title_date = title_date(title),
            posted = as.Date(substr(p$date, 1, 10)),
            pdf_url = post_pdf_url(p$content$rendered)
        )
    })
    idx <- rbindlist(Filter(Negate(is.null), rows))

    bad <- idx[is.na(sitrep) | is.na(pdf_url)]
    if (nrow(bad)) {
        stop("Posts with no report number or no PDF link:\n",
            paste0("  ", bad$title, collapse = "\n"),
            "\nThese need a rule before the fetch can be trusted to be complete.",
            call. = FALSE)
    }

    # A number with more than one post is a reissue. Order by publication so
    # the first one published is v1, and never renumber a version that has
    # already been fetched: the id is what every later artefact is named by.
    setorder(idx, sitrep, posted)
    idx[, version := seq_len(.N), by = sitrep]
    idx[, id := report_id(sitrep, version)]
    idx[]
}

# ------------------------------------------------------------- download ----

#' Percent-encode the non-ASCII characters in a URL.
#'
#' Several filenames contain a degree sign (`N°60`). curl will not send it
#' raw, and encoding the whole URL would also encode the scheme separators.
encode_url <- function(url) {
    utils::URLencode(url, reserved = FALSE)
}

fetch_one <- function(row) {
    dest <- pdf_dir(paste0(row$id, ".pdf"))
    if (file.exists(dest) && !REFRESH) {
        return("skipped")
    }
    insp_download(encode_url(row$pdf_url), dest)
    "fetched"
}

#' Describe a PDF on disk.
#'
#' `text_layer_chars` is the single most useful number here. It separates a
#' born-digital report from a scan, and it is the baseline the corpus is
#' checked against in 05-check-corpus.R. Reading it now means the check costs
#' nothing later.
describe_pdf <- function(path) {
    if (!file.exists(path)) {
        return(list(md5 = NA_character_, bytes = NA_integer_,
            n_pages = NA_integer_, text_layer_chars = NA_integer_))
    }
    txt <- tryCatch(pdftools::pdf_text(path), error = function(e) character())
    list(
        md5 = unname(tools::md5sum(path)),
        bytes = as.integer(file.size(path)),
        n_pages = length(txt),
        text_layer_chars = as.integer(sum(nchar(txt)))
    )
}

# ------------------------------------------------------------------ run ----

ensure_dirs()

index <- build_index(fetch_posts())
message("indexed ", nrow(index), " posts covering ",
    uniqueN(index$sitrep), " report numbers")

index[, status := vapply(seq_len(.N), function(i) {
    row <- index[i]
    tryCatch(fetch_one(row), error = function(e) {
        message("FAILED ", row$id, ": ", conditionMessage(e))
        "failed"
    })
}, character(1))]

meta <- rbindlist(lapply(index$id, function(id) {
    as.data.table(describe_pdf(pdf_dir(paste0(id, ".pdf"))))
}))
manifest <- cbind(index, meta)
manifest[, fetched_at := as.character(Sys.time())]
setcolorder(manifest, c("id", "sitrep", "version", "title", "title_date",
    "posted", "pdf_url", "status", "md5", "bytes", "n_pages",
    "text_layer_chars", "fetched_at"))
fwrite(manifest, manifest_path())

# --------------------------------------------------------------- report ----

present <- sort(unique(manifest[!is.na(md5)]$sitrep))
gaps <- setdiff(seq_len(max(present)), present)
scans <- manifest[!is.na(md5) & text_layer_chars < 200L]

message("\n", nrow(manifest[status == "fetched"]), " fetched, ",
    nrow(manifest[status == "skipped"]), " already present, ",
    nrow(manifest[status == "failed"]), " failed")
message(length(present), " of ", max(present), " report numbers held")
message("never published by INSP: ",
    if (length(gaps)) paste(sprintf("%03d", gaps), collapse = ", ") else "none")
message("no text layer (would need OCR): ",
    if (nrow(scans)) paste(scans$id, collapse = ", ") else "none")
message("manifest written to ", manifest_path())

if (nrow(manifest[status == "failed"])) {
    quit(status = 1L)
}
