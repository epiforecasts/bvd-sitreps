`#ai-input`

# Contributing

Issues and pull requests are welcome at
[epiforecasts/bvd-sitreps](https://github.com/epiforecasts/bvd-sitreps).

Contributions of every kind are welcome: a correction, a bug report, a new
pipeline step, a better prompt, or a question about how something works.

Corrections are especially easy to make and especially valuable, because every
page is machine transcribed and translated with no human review. If you read a
report here and a figure looks wrong, please
[open an issue](https://github.com/epiforecasts/bvd-sitreps/issues) with the
report number and what the source PDF says. No need to work out the cause; the
report number is enough to go on.

## What this repository is for

One job: turn the INSP situation report PDFs into text that can be read by a
machine, without changing what they say. The French transcription is the
record. Everything else, the CSVs and the English pages, is derived from it.

It is not an analysis repository. Anything that interprets the reports rather
than transcribing them belongs downstream, in a repository that reads this
corpus by path.

## Layout

| path | what it is |
|---|---|
| `R/main.R` | runs the five steps in order, stopping at the first failure |
| `R/01-fetch-pdfs.R` | indexes reports through the INSP WordPress posts API and downloads each PDF |
| `R/02-build-corpus.R` | transcribes each PDF to `data/corpus/fr/<id>.md` |
| `R/03-tables-to-csv.R` | extracts each report's tables to `data/csv/` |
| `R/04-translate.R` | translates to English and writes the Quarto pages in `docs/` |
| `R/05-check-corpus.R` | the QA gate: checks the corpus against the PDFs and exits non-zero if it does not hold up |
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

The corpus is verbatim. A transcription that tidies the source cannot be
checked against it, and being checkable is the only reason to trust it. If a
report contains an obvious typo, it stays.

Model output is never trusted on its own. `02-build-corpus.R` checks recall
against the PDF text layer, `04-translate.R` checks that every number survives
translation, and `05-check-corpus.R` checks the corpus against the PDFs.
Weakening a check to make a failure disappear is the wrong fix; the right one
is to rerun that report with a better prompt, or to leave it out.

Models are pinned in `R/lib/gemini.R` with the comparison that chose them.
Changing a pin changes every key and rebuilds everything, so say why in the
commit.

R code uses data.table and `here::here()` for paths. Each script is runnable
on its own with `Rscript`.

British English in prose, sentence case headings, and no bold or italics in
documentation.

## Pull requests

`main` requires one approving review.

Say in the description what you ran. A change to a prompt or a model pin
invalidates the cache, so note how many reports it rebuilds and what changed
in the output.

## Use of AI

The pipeline code was drafted by a language model under human direction, and
commits carry a `Commit-Via` trailer recording that. The transcription and
translation are model output by design. The named author is responsible for
the oversight.
