EmbedSYNC progress report
================
06 September 2026

- [Status](#status)
- [Reproducibility snapshot](#reproducibility-snapshot)
- [Stage 0 — scaffold](#stage-0--scaffold)
  - [Objective](#objective)
  - [Work completed](#work-completed)
  - [Checks and QC](#checks-and-qc)
  - [Results](#results)
  - [Figures and tables](#figures-and-tables)
  - [Decisions](#decisions)
  - [Open issues](#open-issues)
  - [Files created or changed](#files-created-or-changed)
  - [Next step](#next-step)
- [Stage 1 — data feasibility](#stage-1--data-feasibility)
  - [Objective](#objective-1)
  - [Work completed](#work-completed-1)
  - [Checks and QC](#checks-and-qc-1)
  - [Results](#results-1)
  - [Figures and tables](#figures-and-tables-1)
  - [Decisions](#decisions-1)
  - [Open issues](#open-issues-1)
  - [Files created or changed](#files-created-or-changed-1)
  - [Next step](#next-step-1)
- [Stage 2 — final gene panel](#stage-2--final-gene-panel)
  - [Objective](#objective-2)
  - [Work completed](#work-completed-2)
  - [Checks and QC](#checks-and-qc-2)
  - [Results](#results-2)
  - [Figures and tables](#figures-and-tables-2)
  - [Decisions](#decisions-2)
  - [Open issues](#open-issues-2)
  - [Files created or changed](#files-created-or-changed-2)
  - [Next step](#next-step-2)
- [Stage 3 — foundation-model groups](#stage-3--foundation-model-groups)
  - [Objective](#objective-3)
  - [Work completed](#work-completed-3)
  - [Checks and QC](#checks-and-qc-3)
  - [Results](#results-3)
  - [Figures and tables](#figures-and-tables-3)
  - [Decisions](#decisions-3)
  - [Open issues](#open-issues-3)
  - [Files created or changed](#files-created-or-changed-3)
  - [Next step](#next-step-3)
- [Stage template](#stage-template)
  - [Objective](#objective-4)
  - [Work completed](#work-completed-4)
  - [Checks and QC](#checks-and-qc-4)
  - [Results](#results-4)
  - [Figures and tables](#figures-and-tables-4)
  - [Decisions](#decisions-4)
  - [Open issues](#open-issues-4)
  - [Files created or changed](#files-created-or-changed-4)
  - [Next step](#next-step-4)

# Status

**Current stage:** Stage 4 — curated and random groups  
**Stage 0:** complete. `bayesSYNCfm` installs alongside the unmodified
`bayesSYNC` and reproduces it exactly.  
**Stage 1:** complete. GSE194378 supports the design and vanilla
bayesSYNC fits it cleanly.  
**Stage 2:** complete. A 1,000-gene panel is frozen, all genes covered
by both scGPT and Reactome.  
**Stage 3:** complete. Every panel gene has a foundation-model group; 20
groups of 16 to 91 genes.  
**Next gate:** all grouping vectors aligned to the same gene order.

This report is the running scientific record for EmbedSYNC. It should
contain enough narrative, checks, tables and figures to understand what
was done and what was learnt without rerunning expensive analyses.

Expensive model fits should be saved by the analysis scripts and read
from cached outputs here. Knitting this report should remain reasonably
quick.

# Reproducibility snapshot

The software columns are read from
`analysis/results/metrics/00_provenance.csv`, written by the analysis
scripts, so this table cannot drift away from what was actually run.

``` r
prov_file <- file.path(project_root, "analysis", "results", "metrics",
                       "00_provenance.csv")
prov <- if (file.exists(prov_file)) {
  utils::read.csv(prov_file, stringsAsFactors = FALSE)
} else {
  data.frame(item = character(), value = character())
}

lookup <- function(item, default = "not yet recorded") {
  hit <- prov$value[prov$item == item]
  if (length(hit) == 1L && !is.na(hit)) hit else default
}

emb_prov_file <- file.path(project_root, "analysis", "objects", "embeddings",
                           "03_scgpt_embedding_provenance.json")
emb_prov <- if (file.exists(emb_prov_file)) {
  jsonlite::fromJSON(emb_prov_file)
} else list()

snapshot <- data.frame(
  item = c(
    "EmbedSYNC commit",
    "Upstream bayesSYNC commit (origin of bayesSYNCfm)",
    "Reference bayesSYNC version (Test A)",
    "bayesSYNCfm version",
    "Primary dataset",
    "Dataset retrieval date",
    "Gene panel size",
    "scGPT checkpoint",
    "Reactome source/version",
    "R version",
    "Python version"
  ),
  value = c(
    lookup("EmbedSYNC commit"),
    lookup("bayesSYNC upstream commit"),
    lookup("bayesSYNC version (reference)"),
    lookup("bayesSYNCfm version"),
    "GSE194378",
    "2026-09-06",
    "1000 genes",
    if (length(emb_prov)) sprintf("%s, embsize %d", emb_prov$checkpoint,
                                  emb_prov$embedding_dim) else "not yet recorded",
    paste("reactome.db", as.character(packageVersion("reactome.db"))),
    R.version.string,
    if (length(emb_prov)) sprintf("%s (torch %s)", emb_prov$python_version,
                                  emb_prov$torch_version) else "not yet recorded"
  ),
  stringsAsFactors = FALSE
)

knitr::kable(snapshot, col.names = c("Item", "Value"))
```

| Item | Value |
|:---|:---|
| EmbedSYNC commit | b3d86dbe6763aaa35d526a2d524b79ec06d39556 |
| Upstream bayesSYNC commit (origin of bayesSYNCfm) | de326142f15c8a087f544c84f18d83511aae50f1 |
| Reference bayesSYNC version (Test A) | 0.1.0 |
| bayesSYNCfm version | 0.1.0 |
| Primary dataset | GSE194378 |
| Dataset retrieval date | 2026-09-06 |
| Gene panel size | 1000 genes |
| scGPT checkpoint | wanglab/scGPT-human (whole-human, CellxGene census May 2023), embsize 512 |
| Reactome source/version | reactome.db 1.95.0 |
| R version | R version 4.5.2 (2025-10-31) |
| Python version | 3.9.6 (torch 2.8.0) |

# Stage 0 — scaffold

## Objective

Establish the software baseline against which the grouped prior will be
developed and tested.

## Work completed

The group-informed prior is implemented in **bayesSYNCfm**, an R package
derived from bayesSYNC at commit `de32614`. It carries its own package
name, so it installs alongside the unmodified bayesSYNC rather than
replacing it, and both can be loaded in the same session. The exported
function names are shared, so the two are distinguished by namespace,
`bayesSYNC::bayesSYNC()` against `bayesSYNCfm::bayesSYNC()`, and neither
is attached with `library()`.

Keeping the original implementation installed matters for the validation
strategy. Every change to the prior can then be checked by regression
against a reference that is known to be unmodified, rather than by
reading the diff. This is what Test A in the analysis plan asks for, and
it only works if the reference cannot be overwritten by the development
version.

At this stage bayesSYNCfm differs from bayesSYNC in package identity
alone. The likelihood, temporal basis, FPCA representation, variational
updates and ELBO are untouched, so the two packages must give identical
results. Establishing that agreement now fixes the baseline, so that any
later difference can be attributed to the prior.

The analysis scaffold was also created. `analysis/R/00_setup.R` holds
the path helpers, the seeds used throughout, and a `provenance()`
function recording the R version, the package versions and the commits,
which every script saves alongside its results.

## Checks and QC

`analysis/R/00_check_package_rename.R` simulates a small dataset from
the model, fits it under both packages with the same seed and identical
arguments, and compares every output that later stages depend on. The
fits are capped at 30 iterations, since the check is exact agreement
between two runs rather than convergence.

``` r
check_file <- file.path(project_root, "analysis", "results", "metrics",
                        "00_package_rename_check.csv")
if (file.exists(check_file)) {
  check <- utils::read.csv(check_file, stringsAsFactors = FALSE)
  knitr::kable(check, col.names = c("Output", "Identical"))
} else {
  cat("Not yet run.")
}
```

| Output             | Identical |
|:-------------------|:----------|
| B_hat              | TRUE      |
| ppi                | TRUE      |
| omega_hat          | TRUE      |
| factor_ppi         | TRUE      |
| ELBO_iter          | TRUE      |
| i_iter             | TRUE      |
| list_Y_hat         | TRUE      |
| list_h_hat         | TRUE      |
| list_Zeta_hat      | TRUE      |
| list_mu_hat        | TRUE      |
| list_list_Phi_hat  | TRUE      |
| list_cumulated_pve | TRUE      |
| time_g             | TRUE      |

The script also compares the source of `bayesSYNC_core()`, which
contains the whole variational algorithm, between the two packages. At
this stage it is byte-identical. Once the grouped prior is added it will
no longer be, and the numerical outputs above become the operative
check.

## Results

Every compared output agrees exactly, including the ELBO, the loadings
`B_hat`, the posterior inclusion probabilities `ppi` and the
reconstructed trajectories.

This is the baseline for Test A. When `prior_groups` is added, calling
bayesSYNCfm with `prior_groups = NULL` must still reproduce these
values.

## Figures and tables

- `analysis/results/metrics/00_package_rename_check.csv`
- `analysis/results/metrics/00_provenance.csv`

No figures at this stage.

## Decisions

An unmodified bayesSYNC is kept installed as a reference implementation
for the duration of the project, so that the default path can be
validated by regression at every stage rather than only at the end.

Authorship and the GPL-3 licence of bayesSYNC are carried over
unchanged, bayesSYNCfm being a derivative work. Provenance is recorded
through the upstream commit it was derived from.

Analysis scripts depend on `here`, so that paths resolve identically
whether a script is run from the console, run with `Rscript`, or
evaluated while knitting this report.

## Open issues

None.

## Files created or changed

- `bayesSYNCfm/` — the group-informed package, derived from bayesSYNC
  `de32614`
- `analysis/README.md`
- `analysis/R/00_setup.R`
- `analysis/R/00_check_package_rename.R`

## Next step

Stage 1, data feasibility. Retrieve the GSE194378 processed matrix and
metadata, separate biological samples from technical controls and
resequenced samples, reconstruct the subject and time structure, and
inspect the expression scale.

# Stage 1 — data feasibility

## Objective

Establish whether GSE194378 supports the analysis, and whether vanilla
bayesSYNC behaves sensibly on it, before any methodological change.

## Work completed

`analysis/R/01_prepare_data.R` retrieves the processed data and
metadata, reconstructs the design and checks the expression scale.
`analysis/R/01b_pilot_vanilla_fit.R` fits vanilla bayesSYNC to a small
pilot panel.

Three features of the design had to be resolved before the data could be
used, none of which can be taken from the series description alone.

Each RNA isolation batch carried a technical control drawn from a single
healthy donor. These are 25 of the 412 libraries and are not biological
subjects, so they are excluded.

Some subject-visit pairs appear more than once, for two different
reasons: eleven libraries were re-sequenced on a second instrument to
replace initial ones, and some visits were sequenced twice on the
original instrument. Exactly one library is kept per subject-visit.
Where a re-sequenced copy exists it is kept, since the authors describe
those as replacements; otherwise the copy with the larger library size
is kept. Library size is a sequencing quality measure, so neither
criterion involves expression contrasts, subject group or the visits
that will later be held out. For the re-sequenced visits the two
criteria agree, which is a small check on the rule.

The sample metadata are stored as ragged key/value characteristics:
COVID-19 recovered subjects carry four fields that the healthy controls
do not, so the entries do not line up by position across samples. They
are parsed by key rather than by position, since parsing by position
silently misassigns visit day and subject group.

``` r
read_metric <- function(file) {
  path <- file.path(project_root, "analysis", "results", "metrics", file)
  if (file.exists(path)) utils::read.csv(path, stringsAsFactors = FALSE) else NULL
}

design <- read_metric("01_design_summary.csv")
if (!is.null(design)) {
  knitr::kable(design, col.names = c("Item", "Value"))
} else cat("Not yet run.")
```

| Item | Value |
|:---|:---|
| GEO accession | GSE194378 |
| Retrieval date | 2026-09-06 |
| Libraries in series matrices | 412 |
| Technical control libraries | 25 |
| Biological libraries | 387 |
| Re-sequenced libraries | 11 |
| Duplicated subject-visit pairs resolved | 24 |
| Biological libraries retained | 363 |
| Subjects | 73 |
| Distinct RNA-seq days | -7, -6, 0, 1, 7, 26, 27, 28, 29, 30 |
| Genes in normalised matrix | 17060 |
| Genes mapping to a current symbol | 16865 |
| Subjects with a day 1 visit | 72 |
| Subjects with a day 7 visit | 73 |
| Subjects eligible for held-out evaluation | 73 |

## Checks and QC

**Visit times.** The nominal visits are days -7, 0, 1, 7 and 28, but the
actual days recorded are -7, -6, 0, 1, 7, 26, 27, 28, 29 and 30. The
drift is confined to the day -7 and day 28 visits; days 0, 1 and 7 are
exact for every subject. The actual days are kept rather than rounded to
the nominal visit, since bayesSYNC models irregular observation times
and does not require a shared grid, and rounding would discard real
information about when blood was drawn. Days 1 and 7, the candidate
held-out visits, remain exact, so they can be placed exactly on the
dense grid `time_g` as the evaluation requires.

``` r
vd <- read_metric("01_visit_vs_actual_day.csv")
if (!is.null(vd)) {
  knitr::kable(vd, col.names = c("Nominal visit", "Actual day", "Samples"))
} else cat("Not yet run.")
```

| Nominal visit | Actual day | Samples |
|:--------------|-----------:|--------:|
| Day -7        |         -7 |      71 |
| Day -7        |         -6 |       2 |
| Day 0         |          0 |      73 |
| Day 1         |          1 |      72 |
| Day 7         |          7 |      73 |
| Day 28        |         26 |       2 |
| Day 28        |         27 |       2 |
| Day 28        |         28 |      63 |
| Day 28        |         29 |       3 |
| Day 28        |         30 |       2 |

**Availability.** 73 subjects, 363 libraries, 71 subjects with all five
visits and 2 with four.

``` r
knitr::include_graphics("analysis/figures/progress/01_subject_time_availability.png")
```

<img src="analysis/figures/progress/01_subject_time_availability.png" alt="" width="1200" style="display: block; margin: auto;" />

**Expression scale.** The authors’ normalised matrix is on a log2
counts-per-million scale: continuous, roughly symmetric about 5 for
expressed genes, with 18% of values negative. No further transformation
is needed for the Gaussian observation model. Variance is concentrated
in lowly expressed genes, the usual behaviour of log counts-per-million
at low counts, which is what the baseline expression filter in Stage 2
is for.

``` r
scale_tab <- read_metric("01_expression_scale.csv")
if (!is.null(scale_tab)) knitr::kable(scale_tab, col.names = c("Item", "Value"))
```

| Item                   |   Value |
|:-----------------------|--------:|
| Minimum                | -11.460 |
| 1st quartile           |   0.910 |
| Median                 |   3.660 |
| 3rd quartile           |   5.440 |
| Maximum                |  13.910 |
| Proportion negative    |   0.184 |
| Spearman cor(mean, sd) |  -0.797 |

``` r
knitr::include_graphics("analysis/figures/progress/01_expression_scale.png")
```

<img src="analysis/figures/progress/01_expression_scale.png" alt="" width="1200" style="display: block; margin: auto;" />

**Gene identifiers.** The matrix rows are NCBI Entrez gene identifiers
carrying a `gene` prefix. 16,865 of 17,060 map to a current symbol, so
identifier resolution is not an obstacle to the scGPT and Reactome
coverage checks in Stage 2.

## Results

The design is well suited to the project: near-complete five-visit
longitudinal sampling on 73 subjects, with days 1 and 7 available as
internal post-vaccination visits for every subject bar one.

The temporal structure is the demanding part. Four of the five visits
fall within the first week and the last is around day 28, leaving three
weeks with no observations at all. The interior knots of the O’Sullivan
basis are placed at quantiles of the pooled observation times, so none
fall in that gap and the spline spans it as a single long segment. No
smoother can recover behaviour where there are no measurements, so the
question is not whether the gap is uncertain but whether the basis
invents structure there.

The basis was therefore checked rather than assumed. Candidate values of
`K` were compared on how much each varies across the gap, measured for
every subject and selected gene as the reconstruction range over days 8
to 25 relative to its range over the observed part of the study. Both
the median and the 95th percentile are reported: a basis can interpolate
well for most curves while producing large excursions for a minority,
and it is the minority that would make a plotted trajectory misleading.
The comparison uses no external grouping and no held-out visit.

``` r
basis <- read_metric("01b_basis_comparison.csv")
if (!is.null(basis)) {
  knitr::kable(basis, col.names = c("K", "L", "Iterations", "ELBO",
                                    "Runtime (min)", "Active factors",
                                    "Genes selected", "Gap ratio (median)",
                                    "Gap ratio (95th pct)"))
} else cat("Not yet run.")
```

| K | L | Iterations | ELBO | Runtime (min) | Active factors | Genes selected | Gap ratio (median) | Gap ratio (95th pct) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 4 | 2 | 130 | -158363.6 | 5.1 | 3 | 256 | 0.99 | 1.20 |
| 5 | 2 | 126 | -158248.2 | 5.7 | 3 | 259 | 0.91 | 1.32 |
| 7 | 2 | 283 | -158317.1 | 12.2 | 3 | 254 | 1.09 | 1.63 |

All three configurations keep the 95th percentile below 1.7, so none is
dominated by unconstrained behaviour. `K = 5` is used: it has the best
ELBO, the lowest median gap ratio and the fastest convergence, and
`K = 7` shows visibly more spread across the gap for no gain in fit.

``` r
f <- file.path(project_root, "analysis", "figures", "progress",
               "01b_pilot_basis_comparison.png")
if (file.exists(f)) {
  knitr::include_graphics("analysis/figures/progress/01b_pilot_basis_comparison.png")
}
```

<img src="analysis/figures/progress/01b_pilot_basis_comparison.png" alt="" width="1500" style="display: block; margin: auto;" />

With `K = 5`, `L = 2` and `Q = 4` deliberately over-specified, the model
converged in 126 iterations over about six minutes and switched one
factor off entirely, leaving three active. That is the intended
behaviour of the sparsity prior under over-specification. Individual
trajectories are well constrained where data exist, fan out moderately
across the gap and reconverge at day 28, retaining between-subject
variation.

**The Stage 1 gate is passed.** Vanilla bayesSYNC fits this design
cleanly and the temporal representation behaves sensibly, so there is no
need to invoke the fallback dataset rule.

``` r
pilot <- read_metric("01b_pilot_summary.csv")
if (!is.null(pilot)) knitr::kable(pilot, col.names = c("Item", "Value"))
```

| Item                                  | Value     |
|:--------------------------------------|:----------|
| Subjects                              | 73        |
| Genes                                 | 300       |
| Observations                          | 363       |
| Q                                     | 4         |
| L                                     | 2         |
| K                                     | 5         |
| Iterations to convergence             | 126       |
| Final ELBO                            | -158248.2 |
| Runtime (minutes)                     | 5.7       |
| Active factors (factor PPI \> 0.5)    | 3         |
| Genes with PPI \> 0.5 on any factor   | 259       |
| Gap amplitude ratio (median)          | 0.91      |
| Gap amplitude ratio (95th percentile) | 1.32      |
| Temporal basis gate                   | passed    |

``` r
fac <- read_metric("01b_pilot_factors.csv")
if (!is.null(fac)) {
  knitr::kable(fac, col.names = c("Factor", "Factor PPI", "Genes with PPI > 0.5",
                                  "Max |loading|", "PVE component 1 (%)"))
}
```

| Factor | Factor PPI | Genes with PPI \> 0.5 | Max \|loading\| | PVE component 1 (%) |
|:---|---:|---:|---:|---:|
| Factor_1 | 1 | 206 | 2.702 | 98.7 |
| Factor_2 | 1 | 181 | 2.104 | 93.5 |
| Factor_3 | 0 | 0 | 0.000 | NA |
| Factor_4 | 1 | 95 | 3.182 | 86.8 |

``` r
f <- file.path(project_root, "analysis", "figures", "progress",
               "01b_pilot_trajectories.png")
if (file.exists(f)) {
  knitr::include_graphics("analysis/figures/progress/01b_pilot_trajectories.png")
}
```

<img src="analysis/figures/progress/01b_pilot_trajectories.png" alt="" width="1500" style="display: block; margin: auto;" />

## Figures and tables

- `analysis/figures/progress/01_subject_time_availability.png`
- `analysis/figures/progress/01_expression_scale.png`
- `analysis/figures/progress/01b_pilot_basis_comparison.png`
- `analysis/figures/progress/01b_pilot_trajectories.png`
- `analysis/results/metrics/01_*.csv`, `01b_*.csv`
- `analysis/metadata/01b_pilot_gene_panel.csv`

## Decisions

Actual visit days are used rather than nominal visit labels, because
bayesSYNC supports irregular observation times and the candidate
held-out days are exact.

One library is kept per subject-visit, by the re-sequencing and
library-size rule above, rather than by averaging duplicates, which
would mix sequencing batches.

The authors’ normalised matrix is used as supplied. It is already on a
log scale suitable for a Gaussian likelihood.

The pilot gene panel is selected from pre-vaccination visits only,
filtering on baseline expression and ranking on between-subject
variation at baseline. This is the same principle the final panel will
use, so the pilot does not depend on the measurements the evaluation
will hold out.

## Open issues

**The pilot selection rule biased the factors towards static
structure.** The pilot ranked genes by between-subject standard
deviation at baseline, which selects for genes with large stable
individual differences. Decomposing each active factor’s latent
trajectories over the observed window shows the consequence: for two of
the three active factors the within-subject temporal variation is far
smaller than the variation between subject means (ratios 0.23 and 0.15),
so those factors largely encode which subject a sample came from rather
than how that subject responded. Only one factor is genuinely dynamic
(ratio 1.11).

This matters for the main comparison rather than for the pilot. If the
panel is dominated by stable individual differences, every method
reconstructs a held-out visit mostly by predicting that subject’s own
level, and the external grouping has little room to distinguish itself.
The final panel is therefore ranked by within-subject change between day
-7 and day 0, both pre-vaccination and so leakage-free, which
concentrates the panel where the grouping can matter. The residual risk,
that only two pre-vaccination visits make this ranking partly sensitive
to technical noise, is carried forward to Stage 2.

The three-week gap between day 7 and day 28 carries no observations. The
basis check shows the fitted curves do not invent much structure there,
but they are interpolation rather than evidence. Trajectories should be
read as describing the first week after vaccination and the day 28
endpoint, not the interval between them. This is a caveat on
interpretation, not on the held-out evaluation, which acts inside the
observed window.

`L = 1` cannot be used. It fails in bayesSYNC, and in the unmodified
package on its own simulated data, so this is a package limitation
rather than anything to do with these data: in `bayesSYNC_core`,
`setdiff(1:L, l)` is empty when `L = 1`, so the enclosing
`rowSums(sapply(...))` receives an empty list and errors. `L = 2` is the
smallest usable number of FPCA components. This is recorded rather than
fixed: it lies in the inference code that this project deliberately
leaves untouched, and changing it would make bayesSYNCfm diverge from
the reference before the Test A baseline has been used.

Runtime is not a binding constraint at the intended panel size. Timed on
this design with `K = 5`, `L = 2`, `Q = 4` and all 73 subjects, a fit
takes 5.7 minutes at 300 genes, 7.0 at 600 and 12.2 at 1,000. The
per-iteration cost grows roughly in proportion to the number of genes,
but the iteration count falls a little, so the total grows more slowly
than the gene count. At 1,000 genes the full-data comparison across
vanilla, curated, foundation-model and ten matched-random partitions is
about 2.6 hours, and each held-out masking replicate costs the same
again.

## Files created or changed

- `analysis/R/01_prepare_data.R`
- `analysis/R/01b_pilot_vanilla_fit.R`
- `analysis/R/00_setup.R` — fixed day-to-time mapping shared by all
  stages

## Next step

Stage 2, the final gene panel. Check scGPT vocabulary and Reactome
coverage for the mapped genes, apply the prespecified baseline-only
feature rule, and freeze one ordered gene list for every model.

# Stage 2 — final gene panel

## Objective

Freeze one ordered gene list, covered by both external information
sources, for every model to use.

## Work completed

`analysis/R/02_define_gene_panel.R` builds the panel. Genes must be
reliably measured, present in the scGPT vocabulary and annotated in
Reactome. Requiring all three costs little, because the eligible pool is
far larger than the panel, and it removes the need for the `unassigned`
curated group that the analysis plan holds in reserve.

``` r
cov <- read_metric("02_coverage.csv")
if (!is.null(cov)) knitr::kable(cov, col.names = c("Step", "Genes"))
```

| Step                                            | Genes |
|:------------------------------------------------|------:|
| Genes in normalised matrix                      | 17060 |
| Mapping to a current symbol                     | 16865 |
| In scGPT vocabulary                             | 16387 |
| of which matched via an alias                   |   300 |
| Annotated in Reactome                           |  8618 |
| Reliably measured (baseline mean \> 2)          | 11323 |
| Globin transcripts excluded                     |     4 |
| Eligible: measured, scGPT, Reactome, non-globin |  6795 |
| Panel                                           |  1000 |

Two points about coverage are worth recording. The scGPT vocabulary is
keyed by gene symbol and was built from a 2023 CellxGene release,
whereas the symbols here come from a current annotation. Matching on the
current symbol alone discards genes purely because the symbol has since
changed, so unmatched genes are retried against their aliases; this
recovers 300 genes that would otherwise have been lost to nomenclature
drift. Reactome is the binding constraint at 50.5% of genes, not scGPT
at 96.1%.

## Checks and QC

**Globin transcripts are excluded.** Ranking on within-subject change
placed HBD, HBB, HBA2 and HBA1 at four of the top six positions. Globins
are expressed here at log2 counts-per-million of 8 to 9, and their
abundance varies between blood draws largely through handling and
globin-depletion efficiency, so they would carry large loadings and risk
anchoring a factor that represents how much globin was in the tube.
Excluding them is standard for whole-blood RNA-seq. The exclusion is
deliberately narrow: erythroid genes that are not globins, such as
ALAS2, SLC4A1 and CA1, are kept, because their variation reflects
genuine reticulocyte content.

**The ranking is corrected for the expression trend in variability.**
Ranking on the raw standard deviation of within-subject change selects
partly for noise, because variability falls steeply with expression on
this scale and lowly expressed genes therefore show large apparent
change simply from being measured less precisely. Without correction the
panel fills from the low end of the expression range. The panel instead
ranks on the residual from a fitted trend of log variability against
mean expression, which selects genes whose change is large *for their
expression level*. This is the same idea as variance-stabilised feature
selection in single-cell analysis, and it keeps the criterion
pre-vaccination and leakage-free.

``` r
knitr::include_graphics("analysis/figures/progress/02_panel_selection.png")
```

<img src="analysis/figures/progress/02_panel_selection.png" alt="" width="1200" style="display: block; margin: auto;" />

``` r
rc <- read_metric("02_rule_comparison.csv")
if (!is.null(rc)) knitr::kable(rc, col.names = c("Item", "Value"))
```

| Item                                                       |  Value |
|:-----------------------------------------------------------|-------:|
| Shared with the pilot rule (between-subject SD)            | 536.00 |
| Shared with raw within-subject change, no trend correction | 427.00 |
| Median baseline expression, this panel                     |   5.71 |
| Median baseline expression, raw-change panel               |   3.02 |
| Median baseline expression, all eligible genes             |   5.13 |
| Median pathways per panel gene                             |   8.00 |

The correction matters. It changes 57% of the panel relative to ranking
on raw change, and moves the median baseline expression from 3.02 to
5.71, slightly above the median of the eligible pool at 5.13, so the
panel is no longer drawn preferentially from the noisy low end.

## Results

The panel holds 1,000 genes from an eligible pool of 6,795, with a
median of 8 Reactome pathways each.

The genes at the top are interpretable as things that genuinely change
within a person over a week: glucocorticoid and circadian responders
(`FKBP5`, `DDIT4`, `PER1`), a plasma-cell marker (`JCHAIN`), eosinophil
and granulocyte genes (`ALOX15`, `SIGLEC8`), reticulocyte content
(`ALAS2`, `SLC4A1`) and metabolic switching (`CPT1A`).
Interferon-stimulated genes such as `RSAD2`, `IFI44L` and `IFIT1` also
enter the panel, which matters because those are the genes expected to
respond to vaccination.

## Figures and tables

- `analysis/metadata/02_gene_panel.csv` — the frozen ordered panel
- `analysis/figures/progress/02_panel_selection.png`
- `analysis/results/metrics/02_coverage.csv`, `02_rule_comparison.csv`

## Decisions

The panel requires membership of both external sources, so that vanilla,
curated, foundation-model and matched-random models all run on exactly
the same genes and no model is advantaged by coverage.

Globin transcripts are excluded; other erythroid genes are retained.

The ranking is the residual from the expression trend in within-subject
pre-vaccination variability, not the raw standard deviation.

The panel is stored in a fixed order and saved before any grouping is
constructed, so that every grouping vector and every fit refers to the
same genes in the same positions.

## Open issues

The ranking rests on a single pre-vaccination interval, from the day -7
visit to day 0, so it estimates within-subject variability from one
paired difference per subject. The trend correction removes the
systematic part of the noise but not its randomness, and some genes will
enter the panel through chance variation. This is the residual form of
the risk noted when the rule was chosen.

`KRT1` ranks eighth. Keratins in whole blood are commonly skin
contamination from the draw rather than blood biology. It is one gene in
a thousand and is left in rather than starting a list of ad hoc
exclusions, but it is worth remembering if it appears with a large
loading.

## Files created or changed

- `analysis/R/02_define_gene_panel.R`
- `analysis/data/external/scgpt_human_vocab.json`,
  `scgpt_human_args.json`

## Next step

Stage 3, foundation-model groups. Download the whole-human scGPT
checkpoint, extract the static gene-token embeddings for the panel once
and cache them, then build the nearest-neighbour graph and communities.

# Stage 3 — foundation-model groups

## Objective

Turn the scGPT gene representations into one group per panel gene,
without letting the grouping see the longitudinal data.

## Work completed

`analysis/python/01_extract_scgpt_gene_embeddings.py` extracts the
embeddings and `analysis/R/03_build_fm_groups.R` builds the groups. The
Python step is the only part of the project that is not R, and exists
solely because the checkpoint is a PyTorch `state_dict`. It runs once
and writes a cached CSV; everything after that is R.

The model is used as a lookup table. Nothing is fine-tuned, no
expression data pass through the network, and the bulk longitudinal
samples are never embedded as cells. The representations are those
learnt during pretraining on the CellxGene census, so they are
independent of GSE194378 by construction.

One implementation point matters for correctness. The scGPT
`GeneEncoder` is an embedding lookup followed by a LayerNorm, and the
published gene-embedding workflow obtains representations by calling
that encoder rather than by reading the embedding matrix directly. The
LayerNorm is therefore applied here as well. This is not cosmetic: its
learned elementwise scale and shift change the direction of each gene
vector, and the groups are built from cosine similarity, which depends
on direction.

The pipeline follows the published workflow: L2 normalisation, a cosine
nearest-neighbour graph with `k = 15`, then Leiden communities.

``` r
par3 <- read_metric("03_fm_group_parameters.csv")
if (!is.null(par3)) knitr::kable(par3, col.names = c("Item", "Value"))
```

| Item | Value |
|:---|:---|
| Checkpoint | wanglab/scGPT-human (whole-human, CellxGene census May 2023) |
| Embedding dimension | 512 |
| Neighbours per gene (k) | 15 |
| Resolution grid | 0.2 to 3.0 by 0.1 |
| Target group count | 20 |
| Chosen resolution | 2.7 |
| Groups | 20 |
| Smallest group | 16 |
| Largest group | 91 |
| Leiden seed | 10 |

The Leiden resolution is chosen by a prespecified rule. The analysis
plan asks for roughly 10 to 30 groups at this panel size, so the
resolution is taken from a fixed grid as the value whose community count
is closest to 20, with ties broken towards the coarser resolution. This
is a rule about how many groups come out, and involves no model fit, no
held-out visit and no comparison between grouping schemes.

## Checks and QC

**The embeddings carry real biology.** This is the check that the right
tensor was read, with the right normalisation and the right vocabulary
mapping. Cosine nearest neighbours are coherent: `ALAS2` sits with
`SLC4A1`, `FECH`, `BPGM` and `SPTA1`; `IFIT1` with `IFIT3`, `IFIT2`,
`MX1` and `OAS2`; `JCHAIN` with `DERL3`, `CD79A` and `CD27`; `FKBP5`
with `ZBTB16` and `PDK4`; `LYZ` with `S100A8`, `S100A9` and `FCN1`. A
misread tensor would not produce this.

**The graph is well connected**, so no gene is grouped by default for
want of edges.

``` r
gs <- read_metric("03_fm_graph_summary.csv")
if (!is.null(gs)) knitr::kable(gs, col.names = c("Item", "Value"))
```

| Item                 | Value |
|:---------------------|------:|
| Genes (nodes)        |  1000 |
| Edges                | 10520 |
| Median degree        |    19 |
| Isolated genes       |     0 |
| Connected components |     1 |

**The communities correspond to real similarity structure.** Mean cosine
similarity is 0.167 within groups against 0.033 between them, a
five-fold separation, so the partition is not an arbitrary cut through
an unstructured cloud.

``` r
knitr::include_graphics("analysis/figures/progress/03_fm_groups.png")
```

<img src="analysis/figures/progress/03_fm_groups.png" alt="" width="1800" style="display: block; margin: auto;" />

**Gate: every panel gene has a valid group.** All 1,000 genes are
assigned, with no missing labels and no gene left isolated, and the
group vector is stored in panel order so it aligns exactly with the
model input.

## Results

Twenty groups, ranging from 16 to 91 genes. Every group is large enough
for a group- and factor-specific inclusion probability to be informed by
its members, which is what the grouped prior needs.

The groups are interpretable as whole-blood biology, recovered from
pretraining alone with no access to these data:

``` r
ge <- file.path(project_root, "analysis", "results", "tables",
                "03_fm_group_examples.csv")
if (file.exists(ge)) {
  knitr::kable(utils::read.csv(ge, stringsAsFactors = FALSE),
               col.names = c("Group", "Genes", "Examples"))
}
```

| Group | Genes | Examples |
|:---|---:|:---|
| FM_01 | 91 | ZBTB16, TSPAN5, NCAM1, HDAC9, AUTS2, NELL2, NRCAM, BASP1 |
| FM_02 | 81 | ALOX15, SLC6A8, OR2W3, PTGDR2, SLC25A20, ESPN, NMUR1, ASCC2 |
| FM_03 | 73 | SPTB, ANK1, SMPD3, TMOD1, DMTN, NFIX, RAP1GAP, B3GAT1 |
| FM_04 | 68 | SPON2, FGFBP2, CD160, KLRF1, GZMH, S1PR5, KLRD1, SH2D1B |
| FM_05 | 68 | RPL39, RPS3A, RPS15A, RPL9, RPS5, RPS26, RPS29, RPL35 |
| FM_06 | 66 | BAG1, IGF2BP2, MYC, FBL, GADD45GIP1, FKBP4, SRP9, HELLS |
| FM_07 | 65 | FKBP5, DDIT4, PER1, DUSP2, THBS1, PDK4, IRS2, DUSP1 |
| FM_08 | 63 | ALAS2, SLC4A1, SNCA, STRADB, CA1, MYL4, GMPR, GYPC |
| FM_09 | 49 | OAS3, MX1, IFIT3, IFI6, OAS2, GBP5, RSAD2, IFIT1 |
| FM_10 | 45 | GUK1, MT-ND6, GPX1, PFDN5, PRDX6, TOMM7, SNRPD2, MZT2B |
| FM_11 | 42 | NID1, PRSS23, LGALS3, MRC2, IFITM3, COL9A3, PDGFRB, PTGDS |
| FM_12 | 41 | KRT1, PI3, LTF, IL5RA, MMP9, DEFA3, VCAN, PADI4 |
| FM_13 | 40 | SIGLEC8, ADORA3, SIGLEC1, CCR2, CD300E, STAB1, CMKLR1, CHST2 |
| FM_14 | 39 | JCHAIN, HLA-DRB5, HLA-DQB1, PLD4, IL13RA1, UBE2J1, CD79A, HLA-DQA1 |
| FM_15 | 39 | TLR2, FLT3, CD163, HCAR3, RNF144B, IRAK3, ALOX5AP, CLEC4E |
| FM_16 | 33 | ALPL, PROK2, FFAR2, LIMK2, ADGRG3, CYP4F3, MGAM, MME |
| FM_17 | 32 | CPT1A, SLC14A1, ABCA1, LGR6, TCF7L2, COL5A3, TRPM6, ARHGAP31 |
| FM_18 | 25 | TUBB2A, HSPH1, UBB, PEBP1, HSPB1, CLU, HSP90AB1, TUBA1A |
| FM_19 | 24 | TXNDC5, LDLR, DHCR24, FADS2, FADS1, SCD, AK1, CYP51A1 |
| FM_20 | 16 | ITGA2B, PPBP, ITGB3, PF4, RGS18, GNG11, GP1BB, TUBB1 |

Among them are recognisable programmes: interferon-stimulated genes
(`OAS3`, `MX1`, `IFIT3`, `RSAD2`), erythroid genes (`ALAS2`, `SLC4A1`,
`CA1`, `GYPC`), platelet genes (`ITGA2B`, `PPBP`, `PF4`, `GP1BB`),
ribosomal proteins, glucocorticoid and immediate-early responders
(`FKBP5`, `DDIT4`, `PER1`, `DUSP1`), NK and cytotoxic markers (`KLRF1`,
`GZMH`, `KLRD1`), B and plasma cells with MHC class II (`JCHAIN`,
`CD79A`, `HLA-DQB1`), neutrophil granule genes (`LTF`, `DEFA3`, `MMP9`)
and cholesterol biosynthesis (`LDLR`, `DHCR24`, `FADS1`, `SCD`).

That the pretrained representation recovers this structure is a
precondition for the project rather than a result. It shows the external
information is meaningful; whether it helps the longitudinal model is
what the held-out comparison will decide.

## Figures and tables

- `analysis/objects/groups/03_fm_groups.csv` — one group per panel gene
- `analysis/figures/progress/03_fm_groups.png`
- `analysis/results/tables/03_fm_group_examples.csv`
- `analysis/results/metrics/03_fm_*.csv`

## Decisions

The LayerNorm from the scGPT gene encoder is applied, matching the
published workflow rather than reading the raw embedding matrix.

The graph uses the union of each gene’s 15 nearest neighbours by cosine
similarity, so a gene that is nobody else’s neighbour keeps its own
edges and cannot become isolated. Edges with negative similarity are
dropped, since they would assert that two genes belong together because
they point in opposite directions.

The Leiden resolution follows the prespecified group-count rule above,
with a fixed and recorded seed. Group labels are reassigned by
decreasing size so that they do not depend on Leiden’s internal
ordering.

## Open issues

The chosen resolution of 2.7 sits on a steep part of the resolution
curve, where the number of communities changes quickly with the
resolution. The prespecified rule reached its target cleanly and the
resulting groups are biologically coherent, but the partition is not
deeply stable to that choice. This matters mainly for interpretation;
the matched random controls test the grouping mechanism regardless of
exactly where the boundaries fall.

Group sizes are uneven, from 16 to 91. The size-adjusted prior is
designed for exactly this, since the hyperparameters scale with group
size, and Test C will check that the expected sparsity does not change
with the partition.

## Files created or changed

- `analysis/python/01_extract_scgpt_gene_embeddings.py`
- `analysis/R/03_build_fm_groups.R`
- `analysis/R/00_setup.R` — added the community-detection seed

## Next step

Stage 4, curated and random groups. Build Reactome pathway-overlap
similarities, apply the same graph and community strategy, then generate
the matched random partitions that preserve the informed group sizes
exactly.

# Stage template

Copy the section below for each substantive stage. Keep provisional and
negative results when they influence later choices.

## Objective

State the question or gate.

## Work completed

Describe what was run or changed and point to the scripts.

## Checks and QC

Record diagnostics, tests and important numerical checks.

## Results

Report the first useful numerical or qualitative findings. Include null
or negative results.

## Figures and tables

Prefer figures generated from saved outputs. For an existing image file,
use for example:

``` r
knitr::include_graphics("analysis/figures/progress/01_subject_time_availability.png")
```

For small result tables, read the saved CSV/RDS rather than hard-coding
values.

## Decisions

Record choices that affect later analyses and why they were made.

## Open issues

List unresolved points that could affect interpretation or
implementation.

## Files created or changed

List important scripts, data products, results and figures.

## Next step

State the smallest next action and the gate it addresses.
