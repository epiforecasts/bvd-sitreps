# Cleans up quarto-formatted sitreps
if (!requireNamespace("groundhog", quietly = TRUE)) install.packages("groundhog")

runner_path <- "/home/runner/R_groundhog"
if (dir.exists(dirname(runner_path))) {
  groundhog::set.groundhog.folder(runner_path)
}

groundhog_date <- "2026-05-20"
r_version <- getRversion()

groundhog::groundhog.library(
  c("here", "base64enc", "httr2", "purrr"),
  date = groundhog_date, tolerate.R.version = r_version
)

repo_url <- "https://github.com/kathsherratt/bvd-sitreps/blob/main"
sentinel <- "## Source data"

add_source_links <- function(qmd_path) {
  lines <- readLines(qmd_path, warn = FALSE)
  if (any(grepl(sentinel, lines, fixed = TRUE))) {
    return(invisible(NULL))
  }

  stem <- tools::file_path_sans_ext(basename(qmd_path))

  csv_files <- basename(list.files(here("data/csv"), pattern = paste0("^", stem, "_"), full.names = FALSE))
  csv_links <- purrr::map_chr(csv_files, \(f) {
    label <- sub(paste0("^", stem, "_"), "", tools::file_path_sans_ext(f))
    label <- gsub("_", " ", label)
    sprintf("- [%s](%s/data/csv/%s)", label, repo_url, f)
  })

  block <- c(
    "",
    sentinel,
    "",
    sprintf("- [Original PDF (French)](%s/data/pdf/%s.pdf)", repo_url, stem),
    csv_links
  )

  writeLines(c(lines, block), qmd_path)
  message("Added source links: ", basename(qmd_path))
}

qmd_files <- list.files(here("docs"), pattern = "\\.qmd$", full.names = TRUE)
qmd_files <- qmd_files[basename(qmd_files) != "index.qmd"]
purrr::walk(qmd_files, add_source_links)
