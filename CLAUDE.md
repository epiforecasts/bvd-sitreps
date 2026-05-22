# bvd-sitreps

Extracts French Ebola (EVD) outbreak sitreps from DRC into machine-readable format. PDFs → markdown (via Google Gemini Vision) → CSV tables.

## Setup

Set `GOOGLE_AI_KEY` environment variable with Google Cloud API key.

No renv — install packages manually if missing: `rvest`, `here`, `base64enc`, `httr2`, `purrr`, `readr`, `stringr`, `tools`.

## Workflow

1. `R/scrape-pdf.R` — scrapes INSP website, downloads new PDFs to `data/pdf/`
2. `R/extract-docs.R` — converts PDFs in `data/pdf/` to translated markdown in `docs/`
3. `R/extract-tables.R` — extracts markdown tables to CSVs in `data/csv/`

Run scripts in order. Each sitrep PDF produces one markdown file and N CSVs.

## Structure

- `data/pdf/` — source sitrep PDFs (French)
- `docs/` — extracted markdown (English), also served as Jekyll site
- `data/csv/` — structured table extracts
- `R/` — extraction scripts

## Notes

- PDFs are numbered 01–05 (more added as outbreak progresses)
- Gemini prompt translates French → English, preserves proper nouns, converts tables to pipe format
- Jekyll site auto-lists reports from `docs/` via `docs/index.md`
