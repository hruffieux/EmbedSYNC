# Analysis

Scripts are numbered in the order they are meant to run. Each one sources
`R/00_setup.R` for paths, seeds and provenance, saves its expensive outputs
under `objects/`, and writes small result tables to `results/` and diagnostic
figures to `figures/progress/`. `PROGRESS.Rmd` at the repository root reads
those cached outputs rather than refitting anything.

The tables under `results/` and the figures under `figures/progress/` are
version-controlled, because the report reads them: ignoring them would leave
`PROGRESS.Rmd` unbuildable from a fresh clone without rerunning every fit.
What is not tracked is the bulk — downloaded data, foundation-model
embeddings and fitted model objects — all of which the scripts regenerate.

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
| `R/00_setup.R` | paths, seeds, time scale, provenance, shared helpers |
| `R/00_check_package_rename.R` | Stage 0: `bayesSYNCfm` reproduces `bayesSYNC` |
| `R/01_prepare_data.R` | Stage 1: retrieve GSE194378, reconstruct the design, check the expression scale |
| `R/01b_pilot_vanilla_fit.R` | Stage 1 gate: vanilla bayesSYNC on a 300-gene pilot panel |
| `R/02_define_gene_panel.R` | Stage 2: freeze the common 1,000-gene panel |
| `python/01_extract_scgpt_gene_embeddings.py` | Stage 3: extract and cache scGPT gene embeddings |
| `R/03_build_fm_groups.R` | Stage 3: foundation-model gene groups from those embeddings |

## Python

One step is not R: the scGPT checkpoint is a PyTorch `state_dict`, so reading it
needs torch. It runs once and caches a CSV, after which everything is R again.

```sh
python3 -m venv .venv
.venv/bin/pip install torch numpy
.venv/bin/python analysis/python/01_extract_scgpt_gene_embeddings.py
```

`.venv/` and the 196 MB checkpoint under `data/external/` are not tracked.

## Time scale

bayesSYNC works on normalised time in `[0, 1]`. `00_setup.R` fixes the mapping
from GSE194378 visit days with `day_to_time()` and `time_to_day()`, over the
observed range `[-7, 30]`. Every stage uses this one mapping, so that a
candidate held-out day falls on the same point of the dense grid `time_g` in
every model.
