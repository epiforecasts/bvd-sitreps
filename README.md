# INSP situation reports: Ebola (BDBV) DRC 2026

A machine-readable corpus of the situation reports published by the Institut National de Santé Publique (INSP) / Centre d'opérations d'urgence de santé publique (COUSP) for the 2026 Bundibugyo virus disease outbreak in the Democratic Republic of the Congo, with English translations.

Site: https://epiforecasts.io/bvd-sitreps/

We are not affiliated with INSP. All transcription and translation is done by Google Gemini and has not been reviewed by a person. Check the source PDF before relying on any figure, and please flag errors.

## What is here

| | |
|---|---|
| `data/corpus/fr/` | French transcription of each report, one markdown file. The corpus of record |
| `data/corpus/tables/` | Each report's tables as JSON |
| `data/csv/` | The same tables, one CSV each |
| `data/manifest.csv` | Every PDF: source URL, md5, pages, text-layer size |
| `data/corpus-qa.csv` | Per-report checks of the transcription against the PDF |
| `docs/` | English translation of each report, rendered as the site |

Files are named by a three-digit report number (`040`), with `_v2` for a reissue.

This repository does extraction and translation only. Analysis of what the reports say, such as treatment centre openings or bed capacity, reads this corpus from elsewhere.

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

Why French first: translating while transcribing leaves nothing to check a downstream claim against, and mistranslates the terms that matter most. An earlier version of this pipeline rendered `CTE` (Centre de Traitement Ebola) as "Treatment Centers for Epidemics".

Why insp.cd rather than the INRB-UMIE mirror: the mirror is missing reports and some of its copies are degraded. Its SitRep 007 has no text layer; the INSP original has 39,372 characters.

## Coverage

INSP has published 115 report numbers between 001 and 122. Numbers 003, 029, 043, 045, 063, 075 and 076 do not appear on the INSP site or in the mirror. Report 006 was published twice.

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

Cite the situation reports. They are the work; this repository is a
transcription of them.

- Institut National de Santé Publique, Democratic Republic of the Congo
  (2026). *Situation reports on the 17th Ebola virus disease epidemic.*
  <https://insp.cd/ebola-17eme-epidemie/>. Individual report URLs and dates
  are in [data/manifest.csv](data/manifest.csv).

If it matters to your reader how you read them, for instance because you used
the machine-readable text or the English translation rather than the PDFs, add
this corpus as a secondary reference:

- Sherratt, K. (2026). *bvd-sitreps: a machine-readable corpus of the INSP
  situation reports for the 2026 DRC Bundibugyo virus outbreak.*
  <https://github.com/epiforecasts/bvd-sitreps>.

[CITATION.cff](CITATION.cff) carries that secondary reference in a form GitHub
and reference managers can read. For any individual figure, cite the report it
appears in: the source PDF is the authority, and each file here records which
one it came from.

## Contributing

Contributions of any kind are welcome, from a one-line correction to a new
pipeline step. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

The code in `R/` is MIT, in [LICENSE](LICENSE).

The reports are not ours. `data/` and the English pages under `docs/` are
derived from situation reports published by INSP, who hold whatever rights
attach to them; the transcription and translation are ours, under CC BY 4.0.
[data/LICENSE.md](data/LICENSE.md) sets out both, and what the reports do and
do not contain about individuals. The source PDF is the authority in every
case, and every file records which one it came from.

Many thanks to INSP and all those providing public access to these reports.
