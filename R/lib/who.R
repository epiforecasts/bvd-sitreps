#' Talking to WHO.
#'
#' Two publications about this outbreak come from WHO rather than INSP, and
#' they arrive by different routes.
#'
#' Disease Outbreak News is a JSON API behind who.int, one record a
#' publication with the prose already in fields. It needs no user agent games
#' and no scraping: the same OData endpoint the website's own front page
#' calls.
#'
#' The weekly external situation reports are PDFs deposited in IRIS, WHO's
#' institutional repository, which runs DSpace 7. Finding one means a search
#' call, then a bundles call, then a bitstream call. They are digital PDFs
#' with a text layer, so they are read with pdftools rather than transcribed
#' by a model: a text layer that exists is always better than one a model
#' invents, and it costs nothing.
#'
#' Both are © World Health Organization, CC BY-NC-SA 3.0 IGO.

WHO_UA <- "bvd-sitreps/0.1 (research; github.com/epiforecasts/bvd-sitreps)"
WHO_TIMEOUT <- 180
WHO_ATTEMPTS <- 4

who_get <- function(url, query = NULL) {
    req <- httr2::request(url) |>
        httr2::req_user_agent(WHO_UA) |>
        httr2::req_timeout(WHO_TIMEOUT) |>
        httr2::req_retry(max_tries = WHO_ATTEMPTS,
            backoff = function(i) 10 * i)
    if (!is.null(query)) req <- httr2::req_url_query(req, !!!query)
    httr2::req_perform(req)
}

who_json <- function(url, query = NULL) {
    httr2::resp_body_json(who_get(url, query))
}

# ------------------------------------------------------ Disease Outbreak News

DON_API <- "https://www.who.int/api/news/diseaseoutbreaknews"

#' WHO prints a DON in these sections, in this order. Fixed here so a render
#' does not depend on the order a JSON parser hands back fields.
DON_SECTIONS <- c("Summary", "Overview", "Epidemiology", "Assessment",
    "Response", "Advice", "FurtherInformation")

#' Every Disease Outbreak News whose title matches, oldest first.
don_index <- function(pattern = "Bundibugyo", top = 80L) {
    res <- who_json(DON_API, list(
        sf_provider = "dynamicProvider372",
        sf_culture = "en",
        `$orderby` = "PublicationDateAndTime desc",
        `$top` = top,
        `$select` = "Title,PublicationDateAndTime,UrlName"))$value
    dt <- data.table::rbindlist(lapply(res, function(x) data.table::data.table(
        id = x$UrlName, title = x$Title,
        published = as.Date(substr(x$PublicationDateAndTime, 1, 10)))))
    dt[grepl(pattern, title, ignore.case = TRUE)][order(published)]
}

don_record <- function(id) {
    res <- who_json(DON_API, list(
        sf_provider = "dynamicProvider372", sf_culture = "en",
        `$filter` = sprintf("UrlName eq '%s'", id)))$value
    if (!length(res)) stop("no Disease Outbreak News returned for ", id)
    res[[1]]
}

# -------------------------------------------------------------- IRIS (DSpace)

IRIS_API <- "https://iris.who.int/server/api"

#' Search IRIS and keep the items whose title matches. DSpace scores loosely,
#' so the filter is applied here rather than trusted to the query.
iris_search <- function(query, title_pattern, size = 60L) {
    res <- who_json(paste0(IRIS_API, "/discover/search/objects"),
        list(query = query, size = size, sort = "dc.date.issued,DESC"))
    objs <- res$`_embedded`$searchResult$`_embedded`$objects
    if (!length(objs)) return(data.table::data.table())
    dt <- data.table::rbindlist(lapply(objs, function(o) {
        io <- o$`_embedded`$indexableObject
        meta <- io$metadata
        first <- function(field) {
            v <- meta[[field]]
            if (length(v)) v[[1]]$value else NA_character_
        }
        data.table::data.table(
            uuid = io$uuid %||% NA_character_,
            handle = io$handle %||% NA_character_,
            title = first("dc.title"),
            issued = first("dc.date.issued"))
    }), fill = TRUE)
    dt <- dt[!is.na(title) & grepl(title_pattern, title, perl = TRUE)]
    dt[, published := as.Date(substr(issued, 1, 10))]
    dt[order(published)]
}

#' The PDF behind an IRIS item: its ORIGINAL bundle's first bitstream.
iris_pdf_url <- function(uuid) {
    bundles <- who_json(sprintf("%s/core/items/%s/bundles",
        IRIS_API, uuid))$`_embedded`$bundles
    original <- Filter(function(b) identical(b$name, "ORIGINAL"), bundles)
    if (!length(original)) return(NA_character_)
    bits <- who_json(original[[1]]$`_links`$bitstreams$href)$`_embedded`$bitstreams
    pdfs <- Filter(function(b) grepl("\\.pdf$", b$name, ignore.case = TRUE), bits)
    if (!length(pdfs)) return(NA_character_)
    pdfs[[1]]$`_links`$content$href
}

iris_download <- function(url, path) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    httr2::request(url) |>
        httr2::req_user_agent(WHO_UA) |>
        httr2::req_timeout(WHO_TIMEOUT) |>
        httr2::req_retry(max_tries = WHO_ATTEMPTS, backoff = function(i) 10 * i) |>
        httr2::req_perform(path = path)
    invisible(path)
}

# -------------------------------------------------------------- rendering

#' WHO writes DON sections as HTML. The corpus's rule is that a rendered text
#' is the same string every time it is built, because everything downstream
#' checks quotes against it. A carriage return breaks that rule quietly:
#' writeLines keeps it and readLines eats it, so the text read back is one
#' character shorter than the text written.
html_to_text <- function(x) {
    if (is.null(x) || !length(x) || !nzchar(x)) return("")
    x <- gsub("\r|​|﻿", "", x, perl = TRUE)
    x <- gsub("<(br|/p|/h[1-6]|/li|/tr)[^>]*>", "\n", x, perl = TRUE)
    x <- gsub("<[^>]*>", "", x, perl = TRUE)
    x <- gsub("&nbsp;| | ", " ", x)
    x <- gsub("&amp;", "&", x, fixed = TRUE)
    x <- gsub("&lt;", "<", x, fixed = TRUE)
    x <- gsub("&gt;", ">", x, fixed = TRUE)
    x <- gsub("&quot;", "\"", x, fixed = TRUE)
    x <- gsub("&#39;|&rsquo;", "'", x)
    x <- gsub("[ \t]+", " ", x)
    x <- gsub(" *\n *", "\n", x)
    x <- gsub("\n{3,}", "\n\n", x)
    trimws(x)
}

#' A PDF with a text layer, page by page, with the page breaks kept as
#' markers. The markers matter downstream: a figure caption and the sentence
#' under it are not neighbours if a page ends between them.
pdf_to_text <- function(path) {
    pages <- pdftools::pdf_text(path)
    pages <- vapply(pages, function(p) {
        p <- gsub("\r", "", p, fixed = TRUE)
        p <- gsub("[ \t]+", " ", p)
        p <- gsub(" *\n *", "\n", p)
        trimws(gsub("\n{3,}", "\n\n", p))
    }, character(1))
    paste(sprintf("[PAGE %d]\n\n%s", seq_along(pages), pages), collapse = "\n\n")
}

#' Front matter, then the body. Same shape as the French corpus, so anything
#' that reads one can read the other.
render_document <- function(meta, body) {
    keys <- c("id", "source", "publisher", "title", "report_date",
        "publication_date", "url", "licence", "lang", "pdf_md5", "handle")
    lines <- vapply(keys, function(k) {
        v <- meta[[k]]
        if (is.null(v) || !length(v) || is.na(v) || !nzchar(as.character(v))) {
            NA_character_
        } else {
            paste0(k, ": ", as.character(v))
        }
    }, character(1))
    paste0("---\n", paste(lines[!is.na(lines)], collapse = "\n"),
        "\n---\n\n", body)
}

`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
