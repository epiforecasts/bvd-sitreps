# Terms for the contents of data/

The code in this repository is under the MIT licence in [../LICENSE](../LICENSE).
That licence does not cover the material in this directory, and neither does
the MIT badge GitHub shows for the repository as a whole.

## The situation reports are not ours

`data/corpus/fr/`, `data/csv/` and the English pages under `docs/` are derived
from situation reports published by the Institut National de Santé Publique
(INSP) and the Centre d'opérations d'urgence de santé publique (COUSP) of the
Democratic Republic of the Congo. INSP holds whatever rights attach to them.
This repository is not affiliated with INSP and claims no ownership of the
reports or of anything they say.

Every file records where it came from. `data/corpus/fr/<id>.md` carries the
source URL and the md5 of the PDF it was transcribed from, and
`data/manifest.csv` lists all of them. The PDF at that URL is the authority:
where it and this repository disagree, the PDF is right.

They are reproduced here because they are published openly, and because a PDF
on a website cannot be used as data. If INSP asks for any of it to be taken
down, it will be taken down.

## What is ours

The transcription, the translation, the table extraction and the structure of
these files are this repository's work, offered under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) with attribution to
INSP as above. All of it is machine generated and none of it has been read by
a person.

## Personal data

The reports are aggregate. Across all 116 there are no personal names, no
contact details and no line list. The one telephone number is the public
`numéro vert` hotline being advertised.

Two sentences place a confirmed case's household on a named street or in a
named neighbourhood, as INSP published them. Nothing here has been redacted,
because a transcription that does not match its source cannot be checked
against it, and being checkable against the source is the only reason to
trust this corpus at all. If you need a redacted derivative, build it
downstream where the difference stays visible.
