# Analysis

Scripts are numbered in the order they are meant to run. Each one sources
`R/00_setup.R` for paths, seeds and provenance, saves its expensive outputs
under `objects/`, and writes small result tables to `results/` and diagnostic
figures to `figures/progress/`. `PROGRESS.Rmd` at the repository root reads
those cached outputs rather than refitting anything.

## Layout

```text
analysis/
├── R/            analysis scripts
├── python/       scGPT gene-embedding extraction, run once
├── data/         raw/, processed/ and external/ inputs (not tracked)
├── metadata/     small tracked metadata tables
├── objects/      embeddings/ and fits/ (not tracked), groups/ (tracked)
├── results/      metrics/ and tables/
├── figures/      progress/ holds the figures used by PROGRESS.Rmd
└── lib/          locally installed package builds (not tracked)
```

## Packages

Two packages are used side by side:

- `bayesSYNC`, unmodified, the reference for the Test A regression check;
- `bayesSYNCfm`, in `../bayesSYNCfm/`, which adds the group-informed prior.

They export the same function names, so always call them with an explicit
namespace and never attach either with `library()`:

```r
bayesSYNC::bayesSYNC(...)      # reference
bayesSYNCfm::bayesSYNC(...)    # group-informed
```

Reinstall `bayesSYNCfm` after editing the package source:

```r
R CMD INSTALL --no-multiarch --with-keep.source bayesSYNCfm
```

## Scripts

| Script | Purpose |
|---|---|
| `R/00_setup.R` | paths, seeds, provenance, shared helpers |
| `R/00_check_package_rename.R` | Stage 0: `bayesSYNCfm` reproduces `bayesSYNC` |
