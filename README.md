# Syllabi

Syllabi is a Julia package for creating Syllabi. The main feature is that it automatically keeps track of class dates. To use it, in your syllabus markdown file, include a section that contains the word "schedule". All subsections below that will be assigned a date. If you follow a subsection with e.g. `{days=2}`, that subsection will be assigned two days. You specify what days your class meets in the YAML front matter, for example:

```yaml
---
start_date: 2023-08-21
end_date: 2023-12-06
days_of_week: MW
excluded_dates:
    - [2023-09-04, "Labor Day"]
    - [2023-09-25, "Well-being day"]
    - [2023-11-22, "Thanksgiving"]
---
```

Running `Syllabi.render("input.symd", "output.md")` will create a Markdown file with the dates assigned.