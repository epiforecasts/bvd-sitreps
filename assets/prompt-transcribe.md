You are transcribing a French situation report on the Ebola (MVE/BDBV) outbreak in the Democratic Republic of the Congo, published by the Institut National de Santé Publique.

Transcribe it. Do not translate it. The output must be in French, exactly as the document is written.

## Fidelity

1. Copy the wording of the document. Do not correct spelling, do not expand abbreviations, do not normalise place names, do not tidy grammar, do not convert number formats. `CTE`, `CT`, `CI`, `PPL`, `ND`, `SMSPS`, `91,3%` and `Nia-Nia` all stay exactly as written.
2. Never supply a value the document does not show. If a cell is blank, it is blank. If a figure is illegible, write `[ILLISIBLE]`.
3. Do not summarise, reorder or omit content.

## Body

4. Put the running text in `body_markdown`, in French.
5. One sentence per line. A blank line between paragraphs.
6. Use markdown headings only for section titles that the document itself presents as section titles.
7. Remove page numbers, and remove headers and footers that repeat on every page. Keep the front-matter block of the first page (provinces touchées, zones de santé touchées, date de rapportage, date de publication) as text.
8. Replace each photograph or decorative image with `[PHOTO]` on its own line. One `[PHOTO]` per page, however many images that page holds.
9. Charts, maps and epidemic curves are images, not tables. Write `[FIGURE: <the caption as printed>]` on its own line. Do not attempt to read values off a chart.

## Tables

10. Every data table goes in `tables`, not in `body_markdown`. At the position where the table appeared, leave a line in `body_markdown` containing only `[TABLE_n]`, matching that table's `n`.
11. Number tables `1, 2, 3...` in the order they appear in the document, whatever the document's own numbering says. Record the document's own caption, verbatim and in French, in `caption`. If a table has no caption, use an empty string.
12. `columns` is the header row. Every entry in `rows` must have exactly as many cells as there are entries in `columns`.
13. Where one cell spans several rows, repeat its value on every one of those rows. Do not leave the repeats empty. A province or category written once against a block of rows belongs in each of those rows.

    If the document shows

    |          | Bunia    | 0 |
    | Ituri    | Rwampara | 4 |
    |          | Sous total | 16 |

    then all three rows begin `Ituri`: `Ituri | Bunia | 0`, `Ituri | Rwampara | 4`, `Ituri | Sous total | 16`. A total or subtotal row inside the block takes the block's value too.

14. Where a row is a group heading with no data of its own, do not emit it as a row. Fold its label into the rows beneath it, joined with a space. If the document shows a heading `Sorties (24h)` above rows `Décédés`, `Non-cas` and `Guéris`, emit `Sorties (24h) Décédés`, `Sorties (24h) Non-cas`, `Sorties (24h) Guéris`. Never emit a row whose cells are all empty.
15. Where a header spans several columns, give each column its own name, qualified by the spanning header. Never drop a row's leading label to make the row fit.
16. A cell that is empty in the document, and is not a repeat covered by rule 13, is an empty string. A cell the document marks `ND` is `ND`.
17. Keep cell content on one line. Where a cell wraps in the document, join it with a single space.

## Identification

18. `sitrep` is the report number as printed, three digits, zero-padded. It is normally in a line like `SitRep N°040/MVB_23/06/2026` or `SitRep MVE N° 007/MVB_17/2026`.
19. `report_date` is `Date de rapportage`, as `YYYY-MM-DD`.
20. `publication_date` is `Date de publication`, as `YYYY-MM-DD`. Use an empty string if the document does not give one.

Return only the JSON object the schema describes.
