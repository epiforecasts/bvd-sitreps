# INSP situation reports: Ebola (BDBV) DRC 2026

This repository holds a machine-readable corpus of the situation reports published by the Institut National de Santé Publique (INSP) / Centre d'opérations d'urgence de santé publique (COUSP) for the 2026 Bundibugyo virus disease outbreak in the Democratic Republic of the Congo, with English translations.

- Access the site: https://epiforecasts.io/bvd-sitreps/

Very many thanks to INSP and all those providing public access to these reports.

- Authors are in no way affiliated with INSP, and INSP hold complete rights over the source material; see [citation](#citation) and [license](#licence) details.
- All transcription and translation is done by Google Gemini, and you should assume this has **not been reviewed by a human**. Please check the source PDF before relying on any figure.
- If you spot any errors, give feedback, or wish to contribute, you are very welcome and encouraged to open an [Issue](https://github.com/epiforecasts/bvd-sitreps/issues).

## What is here

This repository holds extraction and translation only, aiming to support analysis elsewhere.

| | |
|---|---|
| `data/corpus/fr/` | French transcription of each report, one markdown file. The corpus of record |
| `data/corpus/tables/` | Each report's tables as JSON |
| `data/csv/` | The same tables, one CSV each |
| `data/manifest.csv` | Every PDF: source URL, md5, pages, text-layer size |
| `data/corpus-qa.csv` | Per-report checks of the transcription against the PDF |
| `docs/` | English translation of each report, rendered as the site |

Files are named by a three-digit report number (`040`), with `_v2` for a reissue.

## Method

```
insp.cd posts API  ──01──▶  data/pdf/              (not committed; refetchable)
data/pdf/          ──02──▶  data/corpus/fr/, data/corpus/tables/
tables JSON        ──03──▶  data/csv/
French corpus      ──04──▶  docs/
                   ──05──▶  data/corpus-qa.csv
```

1. `R/01-fetch-pdfs.R` indexes the reports through the INSP WordPress posts API, whose titles carry the report number, and downloads each PDF.
2. `R/02-build-corpus.R` sends each PDF to Gemini with `assets/prompt-transcribe.md` and a response schema. The output is French, not translated. Tables are returned as structured rows, and a table whose rows do not match its header stops the report.
3. `R/03-tables-to-csv.R` writes each table to CSV.
4. `R/04-translate.R` translates the French into English with `assets/prompt-translate.md`. It never opens a PDF. Each translated table must keep the same shape and the same numbers in every row as the French one.
5. `R/05-check-corpus.R` checks, for every report, that the numbers `pdftools` reads from the PDF are present in the transcription, and fails below 95%.

We use insp.cd rather than the INRB-UMIE mirror as the mirror is missing reports and some of its copies are degraded (SitRep 007 has no text layer).

## Coverage

As at 14 September 2026, INSP has published 115 report numbers between 001 and 122. Numbers 003, 029, 043, 045, 063, 075 and 076 do not appear on the INSP site or in the mirror. Report 006 was published twice.

## Running

Requirements: R with `data.table`, `httr2`, `jsonlite`, `pdftools`, `here`, `base64enc`, `digest`; a [Google AI Studio API key](https://aistudio.google.com/app/apikey) as `GOOGLE_AI_KEY` in `~/.Renviron`.

```bash
Rscript R/main.R
```

Transcription takes a few minutes per report, so a first build runs for hours. Run it detached:

```bash
mkdir -p outputs/logs
nohup caffeinate -is Rscript R/02-build-corpus.R \
  > outputs/logs/corpus_$(date +%F-%H%M).log 2>&1 &
```

Every step caches. A report is rebuilt only when its PDF, the prompt, the schema or the model changes. `--only=007,040` limits a step to some reports and `--force` rebuilds regardless.

Models are pinned in `R/lib/gemini.R`, with the comparison that chose them. Token use is logged to `outputs/gemini-usage.csv`.

The `Update Sitreps` Actions workflow runs the same pipeline on demand and commits the results. It needs `GOOGLE_AI_KEY` as a repository secret.

## Citation

Please cite the INSP situation reports.

- Institut National de Santé Publique, Democratic Republic of the Congo
  (2026). *Situation reports on the 17th Ebola virus disease epidemic.*
  <https://insp.cd/ebola-17eme-epidemie/>. Individual report URLs and dates
  are in [data/manifest.csv](data/manifest.csv).

If you used the machine-readable text or the English translation rather than the PDFs for further work, you may wish to also cite this corpus:

- Sherratt, K. (2026). *bvd-sitreps: a machine-readable corpus of the INSP
  situation reports for the 2026 DRC Bundibugyo virus outbreak.*
  <https://github.com/epiforecasts/bvd-sitreps>.

Machine-readable citation: [CITATION.cff](CITATION.cff).

For any individual statement or number, please cite the specific report it
appears in.

## Contributing

All feedback, discussion, or contributions of any kind are very welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

The code in `R/` is MIT, in [LICENSE](LICENSE).

`data/` and the English pages under `docs/` are derived from situation reports published by INSP, who hold all rights
attached to them. The transcription and translation are published here under CC BY 4.0. See [data/LICENSE.md](data/LICENSE.md).
