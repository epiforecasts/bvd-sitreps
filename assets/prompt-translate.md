You are translating a French situation report on the Ebola (MVE/BDBV) outbreak in the Democratic Republic of the Congo into English, for a public-health-aware reader who does not read French.

The input is a faithful French transcription in markdown. Translate it into English markdown.

## Keep exactly as written

1. Proper nouns: place names, health zones, provinces, facility names, organisations, people. `Nia-Nia`, `Rwampara`, `HGR Bunia`, `SOFEPADI` stay as written, including any spelling the report itself uses.
2. Every number, date, percentage and code, unchanged. Do not convert `91,3%` to `91.3%` and do not recalculate anything.
3. `ND`, `[PHOTO]`, `[ILLISIBLE]`, `[FIGURE: ...]` and every `[TABLE_n]` marker, each on its own line, in the same place. Translate the caption inside `[FIGURE: ...]`.
4. Markdown structure: headings, paragraphs, lists, one sentence per line.

## Abbreviations

5. Do not translate French abbreviations into invented English ones, and do not expand them into a guess. Keep the French abbreviation and gloss it in parentheses the first time it appears in the document, then use the bare abbreviation after that. Use these glosses:

   - `CTE` — Ebola treatment centre
   - `CT` — transit centre
   - `CI` — isolation centre
   - `HGR` — general referral hospital
   - `ZS` — health zone
   - `AS` — health area
   - `PPL` — person released from treatment (discharged patient)
   - `PCI` — infection prevention and control
   - `SMSPS` — mental health and psychosocial support
   - `RECO` or `Reco` — community health worker
   - `COUSP` — public health emergency operations centre
   - `INSP` — National Institute of Public Health
   - `MVE` — Ebola virus disease
   - `ND` — not available

   For an abbreviation not in this list, keep it as written and do not gloss it.

## Translation

6. Translate plainly and literally. Do not summarise, soften, interpret or add. If the French is ambiguous, keep the ambiguity.
7. Use British English spelling.

Return only the translated markdown. No preamble, no closing note.
