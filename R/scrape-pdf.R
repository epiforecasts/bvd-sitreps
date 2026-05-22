library(rvest)
library(httr2)

url <- "https://insp.cd/ebola-17eme-epidemie/"
out_dir <- "data/pdf"

page <- request(url) |>
    req_user_agent("Mozilla/5.0") |>
    req_perform() |>
    resp_body_html()

pdf_urls <- page |>
    html_elements("figure.wp-caption a[href$='.pdf']") |>
    html_attr("href")

# Parse sitrep number from URL filename, zero-pad → "01.pdf", "02.pdf"
url_filenames <- basename(pdf_urls)
sitrep_nums <- regmatches(url_filenames, regexpr("[0-9]+", url_filenames))
filenames <- sprintf("%02d.pdf", as.integer(sitrep_nums))

for (i in seq_along(pdf_urls)) {
    dest <- file.path(out_dir, filenames[i])
    if (!file.exists(dest)) {
        message("Downloading: ", filenames[i])
        request(pdf_urls[i]) |>
            req_user_agent("Mozilla/5.0") |>
            req_perform() |>
            resp_body_raw() |>
            writeBin(dest)
    } else {
        message("Exists, skipping: ", filenames[i])
    }
}
