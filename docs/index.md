---
title: Situation Reports
layout: home
---

Ebola-BVD situation reports extracted from INSP 

See: https://insp.cd/ebola-17eme-epidemie/

{% assign reports = site.pages | where_exp: "p", "p.path contains 'docs/' and p.name != 'index.md'" | sort: "date" | reverse %}
{% for report in reports %}
- [{{ report.title }}]({{ report.url | relative_url }}) — {{ report.date }}
{% endfor %}
