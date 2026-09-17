# bvd-sitreps

Corpus of INSP Ebola (BDBV) DRC 2026 situation reports: PDF → faithful French markdown + table JSON → CSV and English site. Extraction and translation only. Topic analysis (treatment centres, capacity) lives in other repos and reads `data/corpus/` by path.

## Rules

- `R/02-build-corpus.R` is the only script that opens a PDF. Nothing downstream reads PDFs.
- The French corpus is the record. Never translate, correct or normalise in the transcription step.
- Do not relax a check to make a report pass. A ragged table, low numeric recall or a translated table whose numbers changed is a transcription failure to fix in the prompt or model.
- Cache keys include PDF md5, prompt hash, schema hash and model. Do not key on the PDF alone.
- PDFs are not committed. `data/manifest.csv` makes them refetchable and verifiable by md5.
- Call `gemini_models()` before changing a model pin; retired ids fail as 404.

## Pipeline

`Rscript R/main.R` runs 01-05 in dependency order, each as its own process, stopping at the first failure. Tables go to CSV (03) before translation (04) because English pages link the CSVs.

Transcription is slow; run `02` detached with `nohup caffeinate -is ... > outputs/logs/... 2>&1 &` and poll the log.

## Layout

- `R/lib/` — `paths.R` (all paths, `report_id()`), `http.R` (insp.cd client), `gemini.R` (the one Gemini client)
- `assets/` — transcription and translation prompts
- `data/` — manifest, corpus, CSVs, QA
- `docs/` — English pages, rendered by Quarto
