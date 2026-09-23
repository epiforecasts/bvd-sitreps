# Contributing

Issues and pull requests are very welcome at
[epiforecasts/bvd-sitreps](https://github.com/epiforecasts/bvd-sitreps).

Feedback, questions, corrections, bug reports, new pipeline steps, better
prompts: all of it is welcome, and none of it needs to be polished.

Corrections are especially easy to make. Every page is machine transcribed and
translated with no human review, so if a figure looks wrong, please
[open an issue](https://github.com/epiforecasts/bvd-sitreps/issues) with the
report number and what the source PDF says. There is no need to work out the
cause.

## What this repository is for

Turning the INSP situation report PDFs into text a machine can read, without
changing what they say. The French transcription is the record, and the CSVs
and English pages are derived from it.

Analysis of what the reports say belongs downstream, in a repository that
reads this corpus.

## Layout

| path | what it is |
|---|---|
| `R/main.R` | runs the five steps in order, stopping at the first failure |
| `R/01-fetch-pdfs.R` | indexes reports through the INSP WordPress posts API and downloads each PDF |
| `R/02-build-corpus.R` | transcribes each PDF to `data/corpus/fr/<id>.md` |
| `R/03-tables-to-csv.R` | extracts each report's tables to `data/csv/` |
| `R/04-translate.R` | translates to English and writes the Quarto pages in `docs/` |
| `R/05-check-corpus.R` | the QA gate: checks the corpus against the PDFs and exits non-zero if it does not hold up |
| `R/06-fetch-who.R` | fetches WHO's Disease Outbreak News and the AFRO weekly situation reports, and renders both to the corpus |
| `R/lib/who.R` | the WHO clients: the Disease Outbreak News API, IRIS (DSpace), and PDF text extraction |
| `R/lib/gemini.R` | the model client, with the API and Antigravity CLI backends |
| `assets/prompt-*.md` | the transcription and translation prompts |
| `data/manifest.csv` | every PDF: source URL, md5, pages, text-layer size |
| `data/corpus/fr/` | the record |
| `data/LICENSE.md` | terms for everything under `data/`, which MIT does not cover |

PDFs are not committed. `data/manifest.csv` records each one's URL and md5, so
a clone refetches them and the md5 proves they are the same files the corpus
was built from.

## Running it

```bash
Rscript R/main.R
```

Transcription takes a few minutes per report, so a first build runs for hours.
Run it detached and poll the log:

```bash
mkdir -p outputs/logs
nohup caffeinate -is Rscript R/main.R \
  > outputs/logs/build_$(date +%F-%H%M).log 2>&1 &
```

Every step caches, keyed per report. A report is rebuilt only when its PDF,
the prompt, the schema or the model changes, so a new report costs one
transcription and leaves the rest alone. `--only=007,040` limits a step to
some reports and `--force` rebuilds regardless.

Exit 3 from any step means the model quota stopped it. Rerun after it resets;
finished reports are cached.

## Conventions

The corpus is verbatim. If a report contains an obvious typo, it stays: a
transcription that tidies its source cannot be checked against it.

Model output is checked, never trusted. `02-build-corpus.R` checks recall
against the PDF text layer, `04-translate.R` checks that every number survives
translation, and `05-check-corpus.R` checks the corpus against the PDFs. When
a check fails, rerun that report with a better prompt or leave it out, rather
than weakening the check.

Models are pinned in `R/lib/gemini.R`. Changing a pin rebuilds everything, so
please say why in the commit.

R code uses data.table and `here::here()` for paths, and each script runs on
its own with `Rscript`. British English, sentence case headings.

## Pull requests

`main` requires one approving review.

Please say what you ran. A change to a prompt or a model pin invalidates the
cache, so it helps to note how many reports it rebuilds and what changed.

## Use of AI

The pipeline code was drafted by a language model under human direction, and
commits carry a `Commit-Via` trailer recording that. The transcription and
translation are model output by design, which is why every step carries a
check. The named author is responsible for the oversight.
