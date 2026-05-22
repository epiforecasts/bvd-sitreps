# Runs the full sitrep pipeline: scrape PDFs, convert to markdown, parse tables.
# Set GOOGLE_AI_KEY before running extract-docs.R (via env var or .Renviron).
# Run from repo root.
if (!requireNamespace("groundhog", quietly = TRUE)) install.packages("groundhog")

runner_path <- "/home/runner/R_groundhog"
if (dir.exists(dirname(runner_path))) {
  groundhog::set.groundhog.folder(runner_path)
}

groundhog_date <- "2026-05-20"
r_version <- getRversion()

source("R/01-scrape-pdf.R")
source("R/02-extract-docs.R")
source("R/03-extract-tables.R")
source("R/04-format-quarto.R")
