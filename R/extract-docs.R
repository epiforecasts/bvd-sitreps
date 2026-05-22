# Converts PDFs in data/pdf/ to translated markdown in docs/.
# Calls Gemini Vision API. Requires GOOGLE_AI_KEY env var.
# Skips PDFs that already have a matching .md file.
groundhog::groundhog.library(
  c("here", "base64enc", "httr2", "purrr"),
  date = groundhog_date, tolerate.R.version = r_version
)

extract_via_vision <- function(
    pdf_path,
    path_out,
    api_key = Sys.getenv("GOOGLE_AI_KEY")) {
  pdf_b64 <- base64encode(pdf_path)

  prompt <- paste(
    "French Ebola situation report from DRC. Do the following:",
    "1. Translate all text to English.",
    "   Keep proper nouns (place names, names) unchanged.",
    "2. Output as markdown. One sentence per line. Remove page numbers.",
    "3. Minimal formatting. ",
    "  Use blank lines between paragraphs and after headers.",
    "  Do not use markdown headers except for section titles.",
    "4. Convert any data table (including image-based tables) to markdown pipe table format.",
    "   Rules:",
    "   - Output a line containing only TABLE_N (e.g. TABLE_1) immediately before each table.",
    "     No markdown formatting around TABLE_N. No trailing whitespace.",
    "   - The header row must be the first row.",
    "   - Use | as the column separator. Every row must start and end with |.",
    "   - All rows must have the same number of columns.",
    "   - Do not merge or span cells. Split merged cells into separate columns.",
    "   - Cell content must not contain newlines. Summarise multi-line content on one line.",
    "   - Use empty string (nothing between ||) for empty cells.",
    "   - Number tables sequentially starting at TABLE_1 across the whole document.",
    "   - Include all tables, even those without a caption.",
    "5. Replace photographs with '[PHOTO]'.",
    "6. Begin the document with YAML front matter using --- delimiters:",
    "   ---",
    "   title: <sitrep number from report>",
    "   sitrep: <3 digit numeric sitrep number typically following 'Sitrep MVE N° ': e.g. 001>",
    "   date: <publication date from report as YYYY-MM-DD>",
    "   ---
        ",
    "'**CAUTION: converted with Google Gemini**'.",
    "Output only the converted document. No preamble."
  )

  url <- paste0(
    "https://generativelanguage.googleapis.com/v1beta/models/",
    "gemini-2.5-flash-lite:generateContent?key=", api_key
  )

  resp <- tryCatch(
    request(url) |>
      req_body_json(list(
        contents = list(list(
          parts = list(
            list(inline_data = list(
              mime_type = "application/pdf",
              data      = pdf_b64
            )),
            list(text = prompt)
          )
        ))
      )) |>
      req_perform(),
    error = function(e) {
      message(
        "ERROR extracting ", basename(pdf_path), ": ",
        conditionMessage(e)
      )
      NULL
    }
  )

  if (is.null(resp)) return(invisible(NULL))

  result <- resp |> resp_body_json()
  writeLines(result$candidates[[1]]$content$parts[[1]]$text, con = path_out)
  message("Extracted and saved to: ", path_out)
}


parse_sitrep_from_md <- function(text) {
  pattern <- "(?<=sitrep: )\\d{3}"
  m <- regmatches(text, regexpr(pattern, text, perl = TRUE))
  if (length(m) == 0) {
    return(NULL)
  }
  m[[1]]
}

pdf_files <- list.files("data/pdf", pattern = "\\.pdf$", full.names = TRUE)

purrr::walk(pdf_files, \(pdf_path) {
  stem <- sub("\\.pdf$", ".processed", basename(pdf_path))
  marker <- file.path("data/pdf", stem)
  if (file.exists(marker)) {
    message("Skipping (already extracted): ", basename(pdf_path))
    return(invisible(NULL))
  }
tmp_path <- tempfile(fileext = ".md")
extract_via_vision(pdf_path = pdf_path, path_out = tmp_path)
if (!file.exists(tmp_path)) {
  return(invisible(NULL))
}

text <- readLines(tmp_path, warn = FALSE)
sitrep_str <- parse_sitrep_from_md(paste(text, collapse = "\n"))

if (is.null(sitrep_str)) {
  warning(
    "Could not parse sitrep numeric from: ", basename(pdf_path),
    " — saving as PDF-stem name"
  )
  final_path <- file.path("docs", sub("\\.pdf$", ".md", basename(pdf_path)))
} else {
  final_path <- file.path("docs", paste0(sitrep_str, ".md"))
  v <- 2L
  while (file.exists(final_path)) {
    final_path <- file.path("docs", paste0(sitrep_str, "v", v, ".md"))
    v <- v + 1L
  }
}

file.rename(tmp_path, final_path)
writeLines("", marker)
message("Saved: ", final_path)
})
