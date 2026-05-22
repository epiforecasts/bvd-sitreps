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
  prompt  <- paste(
    readLines("assets/gemini-prompt.txt", warn = FALSE), collapse = "\n"
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
  stem <- tools::file_path_sans_ext(basename(pdf_path))
  final_path <- file.path("docs", paste0(stem, ".qmd"))
  if (file.exists(final_path)) {
    message("Skipping (already extracted): ", basename(pdf_path))
    return(invisible(NULL))
  }
  extract_via_vision(pdf_path = pdf_path, path_out = final_path)
  message("Saved: ", final_path)
})
