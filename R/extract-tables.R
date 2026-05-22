# Parses markdown tables from docs/ into CSVs in data/csv/.
# One CSV per table per report, named {sitrep}_{table-name}.csv.
# Skips reports that already have CSVs.
groundhog::groundhog.library(
  c("here", "readr", "stringr", "purrr"),
  date = groundhog_date, tolerate.R.version = r_version
)

extract_tables <- function(md_path, dir_out = here("data/csv")) {
  lines <- readLines(md_path, warn = FALSE)
  stem  <- tools::file_path_sans_ext(basename(md_path))

  table_starts <- which(str_detect(lines, "^TABLE_\\d+$"))

  walk(seq_along(table_starts), \(i) {
    header_line <- lines[[table_starts[i]]]
    table_name  <- str_to_lower(header_line)

    start <- table_starts[i] + 1
    end   <- if (i < length(table_starts)) {
      table_starts[i + 1] - 1
    } else {
      length(lines)
    }

    table_lines <- lines[start:end]
    table_lines <- table_lines[str_starts(table_lines, "\\|")]
    table_lines <- table_lines[
      !str_detect(table_lines, "^\\|[-: |]+\\|$")
    ]

    if (length(table_lines) < 2) return(invisible(NULL))

    table_lines <- str_remove(table_lines, "^\\|") |> str_remove("\\|$")

    df <- read_delim(
      I(paste(table_lines, collapse = "\n")),
      delim = "|",
      trim_ws = TRUE,
      show_col_types = FALSE
    )

    out_path <- file.path(dir_out, paste0(stem, "_", table_name, ".csv"))
    write_csv(df, out_path)
    message("Wrote: ", out_path)
  })
}

md_files <- list.files(here("docs"), pattern = "\\.md$", full.names = TRUE)
md_files <- md_files[basename(md_files) != "index.md"]

md_files <- Filter(\(md_path) {
  stem <- tools::file_path_sans_ext(basename(md_path))
  existing <- list.files(here("data/csv"), pattern = paste0("^", stem, "_"))
  if (length(existing) > 0) {
    message("Skipping (CSVs exist): ", basename(md_path))
    return(FALSE)
  }
  TRUE
}, md_files)

walk(md_files, extract_tables)
