# bvd-sitreps

Extracts Ebola (BVD) outbreak sitreps from INRC into machine-readable format. PDFs → markdown (via Google Gemini Vision) → CSV tables.

## Setup

Set `GOOGLE_AI_KEY` environment variable with Google Cloud API key.

Packages managed with `groundhog`. Date pinned in `R/main.R` via `groundhog_date`. No renv, no manual installs needed.

## Workflow

Run `Rscript R/main.R` from repo root. Runs in order:

1. `R/scrape-pdf.R` — scrapes INSP website, downloads new PDFs to `data/pdf/`
2. `R/extract-docs.R` — converts PDFs in `data/pdf/` to translated markdown in `docs/`
3. `R/extract-tables.R` — extracts markdown tables to CSVs in `data/csv/`

Each sitrep PDF produces one markdown file and N CSVs. Existing files skipped.

## Structure

- `data/pdf/` — source sitrep PDFs (French)
- `docs/` — extracted markdown (English), also served as Jekyll site
- `data/csv/` — structured table extracts
- `R/` — extraction scripts

## Notes

- Gemini prompt translates French → English, preserves proper nouns, converts tables to pipe format
- Jekyll site auto-lists reports from `docs/` via `docs/index.md`
