# Scrapes the INSP website and downloads any new sitrep PDFs to data/pdf/.
# Skips files already present. Run from repo root.
groundhog::groundhog.library(c("rvest", "httr2"), date = groundhog_date)

url <- "https://insp.cd/ebola-17eme-epidemie/"
out_dir <- "data/pdf"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

page <- request(url) |>
    req_user_agent("Mozilla/5.0") |>
    req_perform() |>
    resp_body_html()

pdf_urls <- page |>
    html_elements("figure.wp-caption a[href$='.pdf']") |>
    html_attr("href")

for (pdf_url in pdf_urls) {
    dest <- file.path(out_dir, basename(pdf_url))
    if (!file.exists(dest)) {
        message("Downloading: ", basename(pdf_url))
        request(pdf_url) |>
            req_user_agent("Mozilla/5.0") |>
            req_perform() |>
            resp_body_raw() |>
            writeBin(dest)
    } else {
        message("Exists, skipping: ", basename(pdf_url))
    }
}
