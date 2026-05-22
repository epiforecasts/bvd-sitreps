---
layout: home
---
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

---

{% assign reports = site.pages | where_exp: "p", "p.path contains 'docs/' and p.name != 'index.md'" | sort: "date" | reverse %}
{% for report in reports %}
- [{{ report.title }}]({{ report.url | relative_url }}) 
- {{ report.sitrep }}
- {{ report.date }}
{% endfor %}
