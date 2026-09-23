#!/usr/bin/env Rscript
#'
#' Publish the WHO AFRO weekly situation reports as pages.
#'
#' These exist publicly only as PDFs in IRIS. A PDF is not a usable source:
#' it cannot be searched from a browser, linked to by section, quoted without
#' retyping, or read on a phone. The text layer is already extracted for the
#' corpus, so a page per report costs nothing and fills the one gap that
#' matters about this source.
#'
#' The Disease Outbreak News get no page. WHO already publishes them as
#' clean HTML at who.int, and mirroring them would add a second copy of
#' something already readable while doubling what has to be kept in step.
#' They are listed with links instead.
#'
#' The text is published as extracted, in a pre-wrapped block rather than as
#' reflowed markdown. A weekly report's key figures are a column block:
#'
#'     7 Provinces      6 Provinces           1 902     59.1%
#'     63 Health Zones  49 Health Zones       Cases     Bed
#'     Affected         Active Transmission   Recovered Occupancy
#'
#' Reflowed into a paragraph that becomes an unreadable run of numbers, and
#' guessing which blocks are prose and which are tables would put a heuristic
#' between the reader and the source. Keeping the layout is both easier and
#' more honest: what the page shows is what the PDF's text layer holds.
#'
#' WHO's material is CC BY-NC-SA 3.0 IGO. Every page carries the attribution,
#' the link to the IRIS record, and a note that the rendering is ours and the
#' endorsement is not WHO's.
#'
#' Usage:
#'     Rscript R/07-who-pages.R

suppressMessages({
    library(data.table)
})
source(here::here("R", "lib", "paths.R"))

who_docs_dir <- function(...) here::here("docs-who", ...)

dir.create(who_docs_dir(), recursive = TRUE, showWarnings = FALSE)

manifest <- fread(who_manifest_path())
afro <- manifest[source == "who_afro"][order(report_date)]
dons <- manifest[source == "who_don"][order(report_date)]

if (!nrow(afro)) stop("No AFRO reports in ", who_manifest_path())

read_doc <- function(path) {
    lines <- readLines(here::here(path), warn = FALSE)
    ends <- which(lines == "---")
    meta_lines <- lines[(ends[1] + 1L):(ends[2] - 1L)]
    meta <- lapply(meta_lines, function(l) sub("^[^:]+: ?", "", l))
    names(meta) <- sub(":.*$", "", meta_lines)
    list(meta = meta,
        body = paste(lines[(ends[2] + 1L):length(lines)], collapse = "\n"))
}

#' A report number from the id, for a title a reader can scan.
number_of <- function(id) sub("^afro-0?", "", id)

for (i in seq_len(nrow(afro))) {
    row <- afro[i]
    doc <- read_doc(row$path)

    #' Backticks would end the block early, and a report quoting code is not
    #' a thing that happens; the guard is here so that it cannot.
    body <- gsub("```", "'''", doc$body, fixed = TRUE)

    page <- c(
        "---",
        sprintf('title: "WHO AFRO weekly situation report %s"', number_of(row$id)),
        sprintf('subtitle: "Data as of %s"', row$report_date),
        sprintf("date: %s", row$report_date),
        sprintf('source_url: "%s"', row$url),
        'publisher: "World Health Organization Regional Office for Africa"',
        'licence: "CC BY-NC-SA 3.0 IGO"',
        "lang: en",
        "---",
        "",
        "::: {.callout-note}",
        "## Published by WHO, republished here as text",
        "",
        sprintf(paste("This is the text layer of a PDF published by the WHO",
            "Regional Office for Africa, extracted without change and laid out",
            "as the PDF lays it out. The record of authority is",
            "[the PDF in IRIS](%s)."), row$url),
        "",
        paste("© World Health Organization. Licensed",
            "[CC BY-NC-SA 3.0 IGO](https://creativecommons.org/licenses/by-nc-sa/3.0/igo/).",
            "WHO does not endorse this site, its authors, or any use made of",
            "this material here."),
        ":::",
        "",
        "```{.text}",
        body,
        "```")

    writeLines(page, who_docs_dir(paste0(row$id, ".qmd")))
}

# ------------------------------------------------------------- the listing

listing <- c(
    "---",
    'title: "WHO reports on this outbreak"',
    "listing:",
    "  id: afro",
    "  contents: docs-who",
    '  sort: "date desc"',
    "  type: table",
    "  fields: [date, title]",
    '  date-format: "YYYY-MM-DD"',
    "---",
    "",
    paste("WHO writes about this outbreak from outside the response, in",
        "English, on its own schedule. Two publications are held here."),
    "",
    "## Weekly external situation reports",
    "",
    paste("Published by the WHO Regional Office for Africa as PDFs in IRIS,",
        "and republished here as text so they can be searched, linked and",
        "quoted.", nrow(afro), "reports,", min(afro$report_date), "to",
        paste0(max(afro$report_date), ".")),
    "",
    "::: {#afro}",
    ":::",
    "",
    "## Disease Outbreak News",
    "",
    paste("WHO publishes these as web pages already, so they are linked",
        "rather than copied.", nrow(dons), "cover this outbreak."),
    "",
    "| date | title |",
    "|---|---|",
    sprintf("| %s | [%s](%s) |", dons$report_date, dons$title, dons$url),
    "",
    "## Terms",
    "",
    paste("Both publications are © World Health Organization, licensed",
        "[CC BY-NC-SA 3.0 IGO](https://creativecommons.org/licenses/by-nc-sa/3.0/igo/):",
        "non-commercial use, attribution to WHO, share alike. That is not the",
        "licence on this repository's own code and translations. WHO does not",
        "endorse this site or any use made of its material here."))

writeLines(listing, here::here("who.qmd"))

message(nrow(afro), " situation report pages in ", who_docs_dir())
message("Listing written to ", here::here("who.qmd"))
message("\nAdd to _quarto.yml render: who.qmd and docs-who/*.qmd")
