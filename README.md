# Daily INSP BVD situation reports

This codebase translates Ebola-BVD outbreak situation reports provided by the Centre d’opérations d’urgence de santé publique (COUSP) / L'Institut National de Santé Publique (INSP).

The intention is to provide an English translated, machine-readable, time-stamped archive of sitrep information and data.

- Sitrep PDFs are downloaded from the publicly available [INSP website](https://insp.cd/ebola-17eme-epidemie/)
- PDFs are converted, translated to English **via Google Gemini Vision**, and archived
- Data tables are parsed into structured CSV files

Please note:

- I am not affiliated with INSP in any way 
- All translation and conversion from PDF including English translation is via Google Gemini AI 
  - This is likely to contain errors, mistranslations and could lead to misinterpretations. Each English version is linked to a source PDF report. I recommend using this to check the original source before relying on the automated translation.
  - Please flag if you spot errors or mistranslations
- I welcome feedback and collaboration - please contribute directly or get in touch

Many thanks to the authors and those involved in providing public access to the INSP sitreps.

## Guide to contents

### Overview

#### Inputs

```
INSP website → data/pdf/   (scrape-pdf.R)
data/pdf/    → docs/       (extract-docs.R)
docs/        → data/csv/   (extract-tables.R)
```

Extracted reports are published as a Jekyll site from `docs/`.

#### Outputs

Each sitrep PDF produces one `.md` file and one `.csv` per data table found in the report.

```
data/
  pdf/    — source sitrep PDFs, named by original filename from INSP
  csv/    — structured table extracts, named {sitrep}_{table-name}.csv
docs/
  *.md    — translated markdown, one file per sitrep (English)
  index.md — Jekyll index page
```

### Setup

**Requirements:** R, a [Google AI API key](https://aistudio.google.com/app/apikey)

Set an API key as an environment variable:

```bash
export GOOGLE_AI_KEY=your_key_here
```

Packages are managed with [`groundhog`](https://groundhogr.com/) (date-pinned, no lockfile). 
Each script installs `groundhog` automatically on first run, then loads pinned versions of its dependencies.

### Usage

Run the full pipeline from the repo root:

```r
Rscript R/main.R
```

This runs all three steps in order: scrape PDFs, extract markdown, parse tables. 

### Automation

A GitHub Actions workflow ([`.github/workflows/update-sitreps.yml`](.github/workflows/update-sitreps.yml)) runs daily at 01:00 UTC. It:

1. Scrapes INSP for new PDFs
2. Extracts and translates any new PDFs via Gemini
3. Parses tables to CSV
4. Commits and pushes any new files

The `GOOGLE_AI_KEY` secret must be set in the repository's Actions secrets. Trigger a manual run from the Actions tab using **workflow_dispatch**.

### Jekyll site

The `docs/` directory is configured as a Jekyll site. 
Each markdown file in `docs/` is a report page; `docs/index.md` lists them by date. 
GitHub Pages can serve this directly from the `docs/` folder on `main`.

### Notes

- **Translation:** Gemini translates French → English, preserving proper nouns (place names, people). All outputs carry a `*CAUTION: converted with Google Gemini*` header.
- **Model:** `gemini-2.5-flash-lite` — cost-efficient for document OCR and translation.
- **No renv:** Dependencies are pinned via `groundhog` (date set in `R/main.R`). To update, change `groundhog_date` there.
- **Data files:** `data/pdf/` and `data/csv/` are committed to the repo by the Actions workflow. 
