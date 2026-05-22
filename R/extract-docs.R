if (!requireNamespace("groundhog", quietly = TRUE)) {
  install.packages("groundhog")
}
groundhog::groundhog.library(
  c("here", "base64enc", "httr2", "purrr"),
  date = "2026-05-22"
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
    "  Do not use markdown headers except for section titles marked",
    "  with roman numerals.",
    "4. Convert any data table (including image-based tables) to",
    "   markdown table format. Ensure that the header row is first.",
    "5. Replace photographs with '[PHOTO]'.",
    "6. Begin the document with the following:",
    "   ```yaml",
    "   title: <sitrep number from report>",
    "   date: <publication date from report as YYYY-MM-DD>",
    "   ```",
    "'*CAUTION: converted with Google Gemini*'.",
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


pdf_files <- list.files("data/pdf", pattern = "\\.pdf$", full.names = TRUE)

purrr::walk(pdf_files, \(pdf_path) {
  out_path <- file.path(
    "docs",
    sub("\\.pdf$", ".md", basename(pdf_path))
  )
  if (file.exists(out_path)) {
    message("Skipping (already extracted): ", out_path)
    return(invisible(NULL))
  }
  extract_via_vision(pdf_path = pdf_path, path_out = out_path)
})
