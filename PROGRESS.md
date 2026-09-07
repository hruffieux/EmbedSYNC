EmbedSYNC progress report
================
07 September 2026

- [Status](#status)
- [Reproducibility snapshot](#reproducibility-snapshot)
- [Stage 0 — Software baseline](#stage-0--software-baseline)
  - [Objective](#objective)
  - [Implementation](#implementation)
  - [Checks](#checks)
  - [Results](#results)
  - [Saved outputs](#saved-outputs)
  - [Decisions](#decisions)
  - [Limitations and open points](#limitations-and-open-points)
  - [Files](#files)
  - [Next](#next)
- [Stage 1 — Data and temporal
  feasibility](#stage-1--data-and-temporal-feasibility)
  - [Objective](#objective-1)
  - [Implementation](#implementation-1)
  - [Checks](#checks-1)
  - [Results](#results-1)
  - [Saved outputs](#saved-outputs-1)
  - [Decisions](#decisions-1)
  - [Limitations and open points](#limitations-and-open-points-1)
  - [Files](#files-1)
  - [Next](#next-1)
- [Stage 2 — Gene panel](#stage-2--gene-panel)
  - [Objective](#objective-2)
  - [Implementation](#implementation-2)
  - [Checks](#checks-2)
  - [Results](#results-2)
  - [Saved outputs](#saved-outputs-2)
  - [Decisions](#decisions-2)
  - [Limitations and open points](#limitations-and-open-points-2)
  - [Files](#files-2)
  - [Next](#next-2)
- [Stage 3 — Foundation-model groups](#stage-3--foundation-model-groups)
  - [Objective](#objective-3)
  - [Implementation](#implementation-3)
  - [Checks](#checks-3)
  - [Results](#results-3)
  - [Saved outputs](#saved-outputs-3)
  - [Decisions](#decisions-3)
  - [Limitations and open points](#limitations-and-open-points-3)
  - [Files](#files-3)
  - [Next](#next-3)
- [Stage 4 — Curated and random
  controls](#stage-4--curated-and-random-controls)
  - [Objective](#objective-4)
  - [Implementation](#implementation-4)
  - [Checks](#checks-4)
  - [Results](#results-4)
  - [Saved outputs](#saved-outputs-4)
  - [Decisions](#decisions-4)
  - [Limitations and open points](#limitations-and-open-points-4)
  - [Files](#files-4)
  - [Next](#next-4)
- [Stage 5 — Grouped-prior
  implementation](#stage-5--grouped-prior-implementation)
  - [Objective](#objective-5)
  - [Implementation](#implementation-5)
  - [Checks](#checks-5)
  - [Results](#results-5)
  - [Saved outputs](#saved-outputs-5)
  - [Decisions](#decisions-5)
  - [Limitations and open points](#limitations-and-open-points-5)
  - [Files](#files-5)
  - [Next](#next-5)
- [Stage 6 — Full-data comparison](#stage-6--full-data-comparison)
  - [Objective](#objective-6)
  - [Implementation](#implementation-6)
  - [Checks](#checks-6)
  - [Results](#results-6)
  - [Saved outputs](#saved-outputs-6)
  - [Decisions](#decisions-6)
  - [Limitations and open points](#limitations-and-open-points-6)
  - [Files](#files-6)
  - [Next](#next-6)
- [Stage 7 — Held-out evaluation](#stage-7--held-out-evaluation)
  - [Objective](#objective-7)
  - [Implementation](#implementation-7)
  - [Checks](#checks-7)
  - [Results](#results-7)
  - [Saved outputs](#saved-outputs-7)
  - [Decisions](#decisions-7)
  - [Limitations and open points](#limitations-and-open-points-7)
  - [Files](#files-7)
  - [Next](#next-7)
- [Stage 7d — Why the two comparisons
  disagree](#stage-7d--why-the-two-comparisons-disagree)
  - [Objective](#objective-8)
  - [Implementation](#implementation-8)
  - [Checks](#checks-8)
  - [Results](#results-8)
    - [The priors barely move the
      posterior](#the-priors-barely-move-the-posterior)
    - [The in-sample advantage sits in the prior, not the
      fit](#the-in-sample-advantage-sits-in-the-prior-not-the-fit)
    - [The groupings do capture something
      real](#the-groupings-do-capture-something-real)
    - [It does not buy stability
      either](#it-does-not-buy-stability-either)
  - [Saved outputs](#saved-outputs-8)
  - [Decisions](#decisions-8)
  - [Limitations and open points](#limitations-and-open-points-8)
  - [Files](#files-8)
  - [Next](#next-8)
- [Stage 7e — Does the prior have leverage in a sparser
  regime?](#stage-7e--does-the-prior-have-leverage-in-a-sparser-regime)
  - [Objective](#objective-9)
  - [Implementation](#implementation-9)
  - [Checks](#checks-9)
  - [Results](#results-9)
  - [Saved outputs](#saved-outputs-9)
  - [Decisions](#decisions-9)
  - [Limitations and open points](#limitations-and-open-points-9)
  - [Files](#files-9)
  - [Next](#next-9)

# Status

Stages 0–7 are complete, which is the minimum project described in
`plan.md`. The package extension and its validation tests are in place,
the 1,000-gene panel is frozen, and all 13 conditions have been fitted
twice, once to the full data and once with one internal visit per
subject held out.

The two comparisons disagree, and the disagreement is the result. Both
informed groupings fit the observed data better than their size-matched
random partitions, reproducibly across the two fitting runs. Neither
reconstructs a held-out visit better than any other condition, and every
model is beaten by a per-subject mean, for reasons traced to the model
having no per-gene subject intercept.

Stage 7d resolves the disagreement without refitting. The priors move
the posterior very little, the foundation-model grouping furthest at 14
genes of 1,000 changing selection; the in-sample gain sits entirely in
the terms involving the inclusion prior, while the block containing the
data fit is slightly worse; and the groupings differentiate their groups
far beyond any matched random partition, so they do track real structure
in which genes load. That structure does not reach either prediction or
stability at this panel size and sparsity.

| Stage | Status |
|:---|:---|
| 0 — Software baseline | Complete. `bayesSYNCfm` installs alongside the unmodified `bayesSYNC` and reproduces it exactly. |
| 1 — Data feasibility | Complete. GSE194378 supports the design and vanilla bayesSYNC fits it cleanly. |
| 2 — Gene panel | Complete. The 1,000-gene panel is covered by scGPT and Reactome. |
| 3 — FM groups | Complete. All genes assigned to 20 groups of 16–91 genes. |
| 4 — Comparator groups | Complete. Curated and matched-random groups built; 12 grouping vectors aligned to the panel. |
| 5 — Grouped prior | Complete. Tests A–F pass. |
| 6 — Full-data comparison | Complete. All 13 conditions fit cleanly under identical settings. |
| 7 — Held-out evaluation | Complete. All 13 conditions refitted on masked data. No grouping reconstructs held-out visits better than any other, and all are beaten by a per-subject mean. |
| 7d — Diagnosis | Complete. The priors move the posterior very little, the in-sample gain sits in the prior terms rather than in data fit, and the groupings differentiate their groups far beyond matched random partitions. |
| 7e — Sparsity diagnostic | Complete. A much stronger prior gives the grouping more leverage and reverses the ELBO ordering, but leaves held-out error unchanged between conditions. |

The report records the analyses, checks and decisions as the work
progresses. Expensive fits are run by the analysis scripts and saved;
the report reads their outputs so that it can be rendered without
refitting the models.

# Reproducibility snapshot

Software provenance is read from
`analysis/results/metrics/00_provenance.csv`, which is written by the
analysis scripts. The table therefore reflects the versions recorded
when the analyses were run.

| Item | Value |
|:---|:---|
| EmbedSYNC commit | 154cdc5c534367dc99da1c6d433893f08d4797a0 |
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

# Stage 0 — Software baseline

## Objective

Establish the software baseline against which the grouped prior will be
developed and tested.

## Implementation

The group-informed prior is implemented in **bayesSYNCfm**, derived from
bayesSYNC at commit `de32614`. The package has its own name and can be
installed alongside the unmodified version. Both can be used in the same
session through explicit namespaces, `bayesSYNC::bayesSYNC()` and
`bayesSYNCfm::bayesSYNC()`, without attaching either with `library()`.

Keeping an unmodified reference allows every change to be checked
numerically against the original implementation, rather than relying on
the diff alone. At this stage the packages differ only in their
identity: the likelihood, temporal basis, FPCA representation,
variational updates and ELBO are untouched. Their outputs should
therefore agree exactly. This establishes the baseline for Test A and
makes it possible to attribute later differences to the prior extension.

The analysis scaffold was also created. `analysis/R/00_setup.R` holds
the path helpers, the seeds used throughout, and a `provenance()`
function recording the R version, the package versions and the commits,
which every script saves alongside its results.

## Checks

`analysis/R/00_check_package_rename.R` simulates a small dataset from
the model, fits it under both packages with the same seed and identical
arguments, and compares every output that later stages depend on. The
fits are capped at 30 iterations, since the check is exact agreement
between two runs rather than convergence.

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
contains the variational algorithm. It is byte-identical at this stage.
Once the grouped prior is added, numerical agreement on the unchanged
path becomes the operative check.

## Results

Every compared output agrees exactly, including the ELBO, `B_hat`, `ppi`
and the reconstructed trajectories. This is the baseline for Test A:
after the extension, `prior_groups = NULL` must still reproduce these
values.

## Saved outputs

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

## Limitations and open points

None.

## Files

- `bayesSYNCfm/` — the group-informed package, derived from bayesSYNC
  `de32614`
- `analysis/README.md`
- `analysis/R/00_setup.R`
- `analysis/R/00_check_package_rename.R`

## Next

Stage 1, data feasibility. Retrieve the GSE194378 processed matrix and
metadata, separate biological samples from technical controls and
resequenced samples, reconstruct the subject and time structure, and
inspect the expression scale.

# Stage 1 — Data and temporal feasibility

## Objective

Establish whether GSE194378 supports the analysis, and whether vanilla
bayesSYNC behaves sensibly on it, before any methodological change.

## Implementation

`analysis/R/01_prepare_data.R` retrieves the processed data and
metadata, reconstructs the design and checks the expression scale.
`analysis/R/01b_pilot_vanilla_fit.R` fits vanilla bayesSYNC to a small
pilot panel.

The series description does not fully specify the analysis-ready sample
set. Three aspects of the design needed to be resolved from the
metadata.

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

The sample metadata are stored as ragged key/value characteristics.
COVID-19 recovered subjects have four fields that healthy controls do
not, so the entries cannot be aligned by position. Parsing by key avoids
silently misassigning visit day and subject group.

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

## Checks

The nominal visits are days -7, 0, 1, 7 and 28, but the actual days
recorded are -7, -6, 0, 1, 7, 26, 27, 28, 29 and 30. The drift is
confined to the day -7 and day 28 visits; days 0, 1 and 7 are exact for
every subject. The actual days are kept rather than rounded to the
nominal visit, since bayesSYNC models irregular observation times and
does not require a shared grid, and rounding would discard real
information about when blood was drawn. Days 1 and 7, the candidate
held-out visits, remain exact, so they can be placed exactly on the
dense grid `time_g` as the evaluation requires.

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

The final sample set contains 73 subjects, 363 libraries, 71 subjects
with all five visits and 2 with four.

<img src="analysis/figures/progress/01_subject_time_availability.png" alt="" width="960" style="display: block; margin: auto;" />

The authors’ normalised matrix is on a log2 counts-per-million scale:
continuous, roughly symmetric about 5 for expressed genes, with 18% of
values negative. No further transformation is needed for the Gaussian
observation model. Variance is concentrated in lowly expressed genes,
the usual behaviour of log counts-per-million at low counts, which is
what the baseline expression filter in Stage 2 is for.

| Item                   |   Value |
|:-----------------------|--------:|
| Minimum                | -11.460 |
| 1st quartile           |   0.910 |
| Median                 |   3.660 |
| 3rd quartile           |   5.440 |
| Maximum                |  13.910 |
| Proportion negative    |   0.184 |
| Spearman cor(mean, sd) |  -0.797 |

<img src="analysis/figures/progress/01_expression_scale.png" alt="" width="960" style="display: block; margin: auto;" />

The matrix rows are NCBI Entrez gene identifiers carrying a `gene`
prefix. 16,865 of 17,060 map to a current symbol, so identifier
resolution is not an obstacle to the scGPT and Reactome coverage checks
in Stage 2.

## Results

The design is well suited to the project: near-complete five-visit
longitudinal sampling on 73 subjects, with days 1 and 7 available as
internal post-vaccination visits for every subject bar one.

The main difficulty is temporal. Four of the five visits fall within the
first week, with the last around day 28, leaving three weeks without
observations. The interior knots of the O’Sullivan basis are placed at
quantiles of the pooled observation times, so none fall in this gap and
the spline spans it as one long segment. The missing interval cannot be
recovered from the data; the concern is whether the basis introduces
implausible structure there.

We therefore checked the basis explicitly. Candidate values of `K` were
compared on how much each varies across the gap, measured for every
subject and selected gene as the reconstruction range over days 8 to 25
relative to its range over the observed part of the study. Both the
median and the 95th percentile are reported, since a basis may behave
well for most curves while producing large excursions for a minority.
The comparison uses no external grouping or held-out visit.

| K | L | Iterations | ELBO | Runtime (min) | Active factors | Genes selected | Gap ratio (median) | Gap ratio (95th pct) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 4 | 2 | 130 | -158363.6 | 5.1 | 3 | 256 | 0.99 | 1.20 |
| 5 | 2 | 126 | -158248.2 | 5.7 | 3 | 259 | 0.91 | 1.32 |
| 7 | 2 | 283 | -158317.1 | 12.2 | 3 | 254 | 1.09 | 1.63 |

All three configurations keep the 95th percentile below 1.7, so none is
dominated by unconstrained behaviour. `K = 5` is used: it has the best
ELBO, the lowest median gap ratio and the fastest convergence, and
`K = 7` shows visibly more spread across the gap for no gain in fit.

<img src="analysis/figures/progress/01b_pilot_basis_comparison.png" alt="" width="1200" style="display: block; margin: auto;" />

With `K = 5`, `L = 2` and `Q = 4` deliberately over-specified, the model
converged in 126 iterations over about six minutes and switched one
factor off entirely, leaving three active. This is the intended
behaviour of the sparsity prior under over-specification. Individual
trajectories are well constrained where data exist, fan out moderately
across the gap and reconverge at day 28, retaining between-subject
variation.

Vanilla bayesSYNC fits this design cleanly and the temporal
representation behaves sensibly. The Stage 1 gate is therefore passed,
without needing a fallback dataset.

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

| Factor | Factor PPI | Genes with PPI \> 0.5 | Max \|loading\| | PVE component 1 (%) |
|:---|---:|---:|---:|---:|
| Factor_1 | 1 | 206 | 2.702 | 98.7 |
| Factor_2 | 1 | 181 | 2.104 | 93.5 |
| Factor_3 | 0 | 0 | 0.000 | NA |
| Factor_4 | 1 | 95 | 3.182 | 86.8 |

<img src="analysis/figures/progress/01b_pilot_trajectories.png" alt="" width="1200" style="display: block; margin: auto;" />

## Saved outputs

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

## Limitations and open points

The pilot selection rule favoured static structure. Ranking genes by
between-subject standard deviation at baseline selects for large, stable
individual differences. Decomposing each active factor’s latent
trajectories over the observed window shows the consequence: for two of
the three active factors the within-subject temporal variation is far
smaller than the variation between subject means (ratios 0.23 and 0.15),
so those factors largely encode which subject a sample came from rather
than how that subject responded. Only one factor is genuinely dynamic
(ratio 1.11).

A panel dominated by stable individual differences would make the main
comparison less informative: each method could reconstruct a held-out
visit largely by estimating the subject’s own level, leaving little room
for the external grouping to distinguish itself. The final panel is
therefore ranked by within-subject change between day -7 and day 0, both
pre-vaccination and so leakage-free, which concentrates the panel where
the grouping can matter. The residual risk, that only two
pre-vaccination visits make this ranking partly sensitive to technical
noise, is carried forward to Stage 2.

There are no observations between day 7 and day 28. The basis check
suggests that the fitted curves do not introduce much structure there,
but the curves remain interpolations rather than evidence about the
intervening period. Interpretation should focus on the first week after
vaccination and the day 28 endpoint. The held-out evaluation is
unaffected by this gap because it uses visits inside the observed
window.

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

## Files

- `analysis/R/01_prepare_data.R`
- `analysis/R/01b_pilot_vanilla_fit.R`
- `analysis/R/00_setup.R` — fixed day-to-time mapping shared by all
  stages

## Next

Stage 2, the final gene panel. Check scGPT vocabulary and Reactome
coverage for the mapped genes, apply the prespecified baseline-only
feature rule, and freeze one ordered gene list for every model.

# Stage 2 — Gene panel

## Objective

Freeze one ordered gene list, covered by both external information
sources, for every model to use.

## Implementation

`analysis/R/02_define_gene_panel.R` builds the panel. Genes must be
reliably measured, present in the scGPT vocabulary and annotated in
Reactome. Requiring all three costs little, because the eligible pool is
far larger than the panel, and it removes the need for the `unassigned`
curated group that the analysis plan holds in reserve.

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

## Checks

Globin transcripts are excluded. Ranking on within-subject change placed
HBD, HBB, HBA2 and HBA1 at four of the top six positions. Globins are
expressed here at log2 counts-per-million of 8 to 9, and their abundance
varies between blood draws largely through handling and globin-depletion
efficiency, so they would carry large loadings and risk anchoring a
factor that represents how much globin was in the tube. Excluding them
is standard for whole-blood RNA-seq. The exclusion is deliberately
narrow: erythroid genes that are not globins, such as ALAS2, SLC4A1 and
CA1, are kept, because their variation reflects genuine reticulocyte
content.

The ranking is corrected for the expression trend in variability. Raw
within-subject standard deviation selects partly for noise, because
variability falls steeply with expression on this scale and lowly
expressed genes therefore show large apparent change simply from being
measured less precisely. Without correction the panel fills from the low
end of the expression range. The panel instead ranks on the residual
from a fitted trend of log variability against mean expression, which
selects genes whose change is large *for their expression level*. This
is the same idea as variance-stabilised feature selection in single-cell
analysis, and it keeps the criterion pre-vaccination and leakage-free.

<img src="analysis/figures/progress/02_panel_selection.png" alt="" width="960" style="display: block; margin: auto;" />

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

## Saved outputs

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

## Limitations and open points

The ranking uses only one pre-vaccination interval, from day -7 to day
0, and therefore one paired difference per subject. The trend correction
removes systematic mean-dependent variability but not random noise. Some
genes may consequently enter the panel through chance variation. This
limitation remains despite the correction.

`KRT1` ranks eighth. Keratins in whole blood commonly reflect skin
contamination during the draw rather than blood biology. It is retained
to avoid introducing ad hoc exclusions, but should be treated cautiously
if it appears with a large loading.

## Files

- `analysis/R/02_define_gene_panel.R`
- `analysis/data/external/scgpt_human_vocab.json`,
  `scgpt_human_args.json`

## Next

Stage 3, foundation-model groups. Download the whole-human scGPT
checkpoint, extract the static gene-token embeddings for the panel once
and cache them, then build the nearest-neighbour graph and communities.

# Stage 3 — Foundation-model groups

## Objective

Turn the scGPT gene representations into one group per panel gene,
without letting the grouping see the longitudinal data.

## Implementation

`analysis/python/01_extract_scgpt_gene_embeddings.py` extracts the
embeddings and `analysis/R/03_build_fm_groups.R` builds the groups. The
Python step is the only part of the project that is not R, and exists
solely because the checkpoint is a PyTorch `state_dict`. It runs once
and writes a cached CSV; everything after that is R.

The model is used as a lookup table. There is no fine-tuning, no
expression data are passed through the network, and bulk longitudinal
samples are not embedded as cells. The representations were learnt
during pretraining on the CellxGene census and are therefore independent
of GSE194378 by construction.

The scGPT `GeneEncoder` is an embedding lookup followed by a LayerNorm.
The published gene-embedding workflow calls this encoder rather than
reading the embedding matrix directly, and we do the same. The learned
elementwise scale and shift change the direction of each gene vector.
Since the groups are built from cosine similarity, applying the
LayerNorm is important for reproducing the intended representation.

The pipeline follows the published workflow: L2 normalisation, a cosine
nearest-neighbour graph with `k = 15`, then Leiden communities.

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

The Leiden resolution follows a prespecified rule. The plan targets
roughly 10–30 groups at this panel size. From a fixed grid, we choose
the resolution giving a community count closest to 20, breaking ties
towards the coarser resolution. No model fit, held-out visit or
comparison between grouping schemes enters this choice.

## Checks

The nearest-neighbour structure is biologically coherent, providing a
useful check on the tensor, normalisation and vocabulary mapping:
`ALAS2` sits with `SLC4A1`, `FECH`, `BPGM` and `SPTA1`; `IFIT1` with
`IFIT3`, `IFIT2`, `MX1` and `OAS2`; `JCHAIN` with `DERL3`, `CD79A` and
`CD27`; `FKBP5` with `ZBTB16` and `PDK4`; `LYZ` with `S100A8`, `S100A9`
and `FCN1`. These relationships are consistent with the intended
representation.

The graph is connected, with no gene assigned by default for lack of
edges.

| Item                 | Value |
|:---------------------|------:|
| Genes (nodes)        |  1000 |
| Edges                | 10520 |
| Median degree        |    19 |
| Isolated genes       |     0 |
| Connected components |     1 |

Mean cosine similarity is 0.167 within groups and 0.033 between them, a
five-fold separation. The partition therefore captures structure in the
embedding space rather than an arbitrary division of an unstructured
cloud.

<img src="analysis/figures/progress/03_fm_groups.png" alt="" width="1440" style="display: block; margin: auto;" />

All 1,000 genes are assigned, with no missing labels or isolated genes.
The group vector is stored in panel order and aligns exactly with the
model input. The Stage 3 gate is passed.

## Results

Twenty groups, ranging from 16 to 91 genes. Every group is large enough
for a group- and factor-specific inclusion probability to be informed by
its members, which is what the grouped prior needs.

The groups are interpretable as whole-blood biology, recovered from
pretraining alone with no access to these data:

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

Recovering this structure is a useful prerequisite, not the main result.
It shows that the external information is meaningful. Whether it
improves the longitudinal model will be assessed through held-out
reconstruction.

## Saved outputs

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

## Limitations and open points

The chosen resolution of 2.7 sits on a steep part of the resolution
curve, where the number of communities changes quickly with the
resolution. The prespecified rule reached its target cleanly and the
resulting groups are biologically coherent, but the partition is not
deeply stable to that choice. This mainly affects interpretation; the
matched random controls test the grouping mechanism regardless of
exactly where the boundaries fall.

Group sizes are uneven, from 16 to 91. The size-adjusted prior is
designed for exactly this, since the hyperparameters scale with group
size, and Test C will check that the expected sparsity does not change
with the partition.

## Files

- `analysis/python/01_extract_scgpt_gene_embeddings.py`
- `analysis/R/03_build_fm_groups.R`
- `analysis/R/00_setup.R` — added the community-detection seed

## Next

Stage 4, curated and random groups. Build Reactome pathway-overlap
similarities, apply the same graph and community strategy, then generate
the matched random partitions that preserve the informed group sizes
exactly.

# Stage 4 — Curated and random controls

## Objective

Build the curated comparator and the matched random controls, and check
that every grouping vector lines up with the frozen panel.

## Implementation

`analysis/R/04_build_curated_groups.R` builds the Reactome groups and
`analysis/R/05_build_random_groups.R` the random partitions.

The curated groups exist to ask whether a foundation model adds anything
over established curated biology. For that question to be about the
information rather than the method, the two must be built the same way,
so the graph construction, community algorithm, resolution rule and seed
are all identical to Stage 3, and only the similarity changes: cosine
similarity between embeddings becomes Jaccard similarity between the
Reactome pathway sets of each gene.

One difference is deliberate and required by the analysis plan. Genes
sharing no pathway have Jaccard similarity exactly zero, and no edge is
created between them. A nearest-neighbour rule applied blindly would
connect every gene to its fifteen closest others whether or not Reactome
asserts any relationship, inventing curated structure that does not
exist.

| Item                    | Value                           |
|:------------------------|:--------------------------------|
| Source                  | Reactome via reactome.db 1.95.0 |
| Pathways used           | 1765                            |
| Neighbours per gene (k) | 15                              |
| Zero-similarity edges   | dropped                         |
| Minimum group size      | 5                               |
| Chosen resolution       | 1.6                             |
| Groups                  | 20                              |
| Unassigned genes        | 3                               |
| Leiden seed             | 10                              |

The random partitions are the negative control for the grouping
mechanism itself. Grouping genes at all changes the prior, quite apart
from whether the grouping is meaningful, because pooling inclusion
indicators shrinks them towards a common rate within each group. Each
informed grouping therefore gets its own null family, built by permuting
which genes carry which labels while leaving the group-size distribution
exactly as it was, so the null differs from the informed grouping in
content and not in shape. Five replicates per family are generated with
deterministic seeds and saved before any model is fitted.

## Checks

The two graphs are comparable in size and connectivity. Foundation
model: 10,520 edges, median degree 19. Curated: 10,582 edges, median
degree 19. Both have a single connected component and no isolated genes.
The two comparators are therefore matched in graph structure and differ
in their similarity source, which is what the comparison requires.

| Item                 | Value |
|:---------------------|------:|
| Genes (nodes)        |  1000 |
| Edges                | 10582 |
| Median degree        |    19 |
| Isolated genes       |     0 |
| Connected components |     1 |
| Largest component    |  1000 |

Mean Jaccard similarity is 0.223 within groups and 0.021 between them.
About 66% of gene pairs share no pathway at all, which is why the
zero-similarity rule matters.

Three genes could not be placed. Genes with no positive-similarity
neighbour, or left in communities of fewer than five genes, are
collected into one explicit `CUR_unassigned` group rather than left as
singletons; a group of one carries no pooling, since its inclusion
probability would be informed by a single Bernoulli draw. The analysis
plan allows this rule, and at three genes it barely engages.

The random partitions preserve the intended group sizes.

| Check                                            | Value |
|:-------------------------------------------------|:------|
| Families                                         | 2     |
| Replicates per family                            | 5     |
| Partitions                                       | 10    |
| Group sizes match the informed grouping          | TRUE  |
| Any partition identical to its informed grouping | FALSE |
| Mean gene-level agreement with informed grouping | 0.062 |
| Expected agreement if labels were independent    | 0.059 |

Group sizes match their informed grouping exactly, no permutation
reproduces the grouping it is a null for, and gene-level agreement with
the informed grouping is 0.062 against 0.059 expected under
independence.

All twelve grouping vectors, comprising the two informed groupings and
ten random partitions, are complete and aligned to the panel. The Stage
4 gate is passed.

| Check                           | Value |
|:--------------------------------|------:|
| Grouping vectors checked        |    12 |
| All aligned to the panel order  |     1 |
| All complete (no missing group) |     1 |

## Results

The two informed sources produce substantially different partitions of
the same genes.

| Item                                                           |  Value |
|:---------------------------------------------------------------|-------:|
| Foundation-model groups                                        | 20.000 |
| Curated groups                                                 | 20.000 |
| Adjusted Rand index between them                               |  0.085 |
| Mean adjusted Rand index, random against its informed grouping | -0.001 |

<img src="analysis/figures/progress/05_grouping_comparison.png" alt="" width="1200" style="display: block; margin: auto;" />

The adjusted Rand index between them is 0.085, against essentially zero
for the random partitions. Both are individually coherent, so the low
agreement is not a failure of either: they organise the same genes along
different axes. The overlap map shows agreement in several readily
interpretable biological groups. The foundation-model ribosomal group
maps onto the curated ribosomal groups, which Reactome splits into large
and small subunit; the interferon groups correspond; so do the cytotoxic
lymphocyte groups. Elsewhere the partitions diverge, because pathway
co-membership and the co-expression context learnt from single cells are
different relations.

If the partitions agreed closely, the foundation-model arm might add
little over curated biology. Their difference makes the comparison
informative.

## Saved outputs

- `analysis/objects/groups/04_curated_groups.csv`,
  `05_random_groups.csv`
- `analysis/figures/progress/05_grouping_comparison.png`
- `analysis/results/tables/04_curated_group_examples.csv`
- `analysis/results/metrics/04_*.csv`, `05_*.csv`

## Decisions

The curated grouping uses the same graph, algorithm, resolution rule and
seed as the foundation-model grouping, so the two differ only in
similarity.

Zero-similarity edges are dropped, so Reactome is never asked to assert
a relationship it does not record.

Genes Reactome cannot place are collected into one `CUR_unassigned`
group rather than left as singleton groups.

Random partitions are generated once, with deterministic seeds, and
saved before fitting. They are never regenerated inside a fitting
function, so every model sees the same partitions.

## Limitations and open points

Jaccard similarity on pathway membership is sensitive to how deeply a
gene is annotated. A gene in three pathways and a gene in three hundred
can share all three and still score low, and Reactome’s hierarchy means
broad parent pathways are counted alongside specific ones. The
prespecified similarity is applied as written, but these properties of
Reactome annotation should be kept in mind when interpreting the curated
comparator.

`CUR_unassigned` holds three genes. It is a legitimate group for the
model, but it is a group only in the sense of being a residual, so it
should not be interpreted as a programme.

## Files

- `analysis/R/04_build_curated_groups.R`
- `analysis/R/05_build_random_groups.R`

## Next

Stage 5, the grouped prior itself. Add `prior_groups` to bayesSYNCfm
with size-adjusted hyperparameters, implement the grouped variational
updates and ELBO terms, expose the group-level inclusion probabilities,
and run package tests A to F.

# Stage 5 — Grouped-prior implementation

## Objective

Implement the group-informed prior in bayesSYNCfm and establish, by test
rather than by inspection, that it is correct and that the original
model is untouched.

## Implementation

`bayesSYNC()` gains one argument, `prior_groups`, a named vector or
factor of length p whose names are the variable names. Everything else
about the interface is unchanged, and `prior_groups = NULL` is the
original model.

The change is confined to the prior on the loading inclusion indicators.
The likelihood, the temporal basis, the FPCA representation, the slab
distribution, the annealing schedule, the orthonormalisation and the
factor-selection machinery are all untouched.

Group `k` of size $n_k$ receives $\pi_{kq}\sim\mathrm{Beta}(a_k, b_k)$
with $\rho_k = n_k/p$, $a_k = \rho_k c_0$ and $b_k = \rho_k d_0$. This
holds the prior mean at $c_0/(c_0+d_0)$ for every group, so the prior
expected number of active variables per factor stays at
$p\,c_0/(c_0+d_0)$ whatever the partition, while the prior concentration
scales with group size. With one group containing every variable,
$n_1 = p$ gives $a_1 = c_0$ and $b_1 = d_0$.

The variational Beta update becomes a sum within each group rather than
over all variables:

$$
a^{\ast}_{kq} = c\left(a_k + \sum_{j \in G_k} E_q[\gamma_{jq}]\right) - c + 1,
\qquad
b^{\ast}_{kq} = c\left(b_k + n_k - \sum_{j \in G_k} E_q[\gamma_{jq}]\right) - c + 1,
$$

with $c$ the inverse temperature of the annealing schedule. The
inclusion update for variable `j` then uses the expectations of its own
group, $m(j)$. Group sums are formed by a matrix product against a group
indicator, so the result cannot depend on how some helper happens to
order its output.

Both affected ELBO terms change consistently. The
$q(b_{jq},\gamma_{jq})$ contribution remains a sum over variables and
factors, with each variable contributing the expected log inclusion
probability of its group. The Beta contribution becomes a sum over
groups and factors, each with its own $a_k, b_k$.

A misaligned grouping could silently pool the wrong genes. The input
checks therefore reject wrong length, missing names, duplicated names, a
gene set that does not match the model variables, missing labels, or
combining the grouping with variable-specific probabilities. Reordering
by name happens only after the two name sets have been shown to agree
exactly.

All existing outputs are preserved, with three additions:
`prior_groups`, `group_inclusion_prob` (a groups-by-factors matrix of
$E(\pi_{kq}\mid Y)$) and `group_prior_hyperparameters`.

## Checks

| Test | Description | Result | Detail |
|:---|:---|:---|:---|
| Test A | prior_groups = NULL reproduces bayesSYNC | PASS | ELBO -1975.097168 |
| Test B | single group reduces to factor-specific prior | PASS | ELBO -1975.097168 |
| Test C | size-adjusted prior preserves expected sparsity | PASS | target 0.92308, max deviation 2.22e-16 |
| Test D | grouped Beta update matches the equations | PASS | max \|difference\| 7.14e-14 |
| Test D2 | implemented hyperparameters preserve sparsity | PASS | sum n_k E(pi_k) = 0.92308 |
| Test E | correct groups recover the signal at least as well | PASS | AUC correct 1.000, random 0.932, vanilla 0.939 |
| Test F | grouped fits run with and without annealing | PASS | ELBO annealed -11577.7, unannealed -10420.3 |
| Outputs | original outputs preserved, new ones added | PASS | added: prior_groups, group_inclusion_prob, group_prior_hyperparameters |

Tests A and B return the identical ELBO, −1975.097168, as required by
the calibration: a single group containing every variable must reduce to
the factor-specific prior exactly, not approximately. Had the size
adjustment been wrong, these two numbers would differ.

Test D checks the coded update against the equations rather than against
a reimplementation of itself. Without annealing the inverse temperature
is one, so $E(\pi_{kq}\mid Y)$ must equal
$(a_k + \sum_{j \in G_k}\mathrm{ppi}_{jq})/(a_k + b_k + n_k)$, computed
from returned quantities alone. It matches to 7 × 10⁻¹⁴, which exercises
the group sums, the size-adjusted hyperparameters and the posterior mean
together.

## Results

All tests pass, so the Stage 5 gate is met.

Test E examines whether the implementation can exploit a known grouping.
In a small simulation where the active variables of each factor sit in
one group, recovery of the truly active set is perfect with the correct
grouping and materially worse with either alternative.

| Model   |    AUC |
|:--------|-------:|
| correct | 1.0000 |
| random  | 0.9322 |
| vanilla | 0.9389 |

The matched random grouping performs about as well as no grouping at
all, as expected: pooling genes into groups is not by itself helpful.
The matched random controls will allow the real-data comparison to
distinguish the effect of grouping from the information used to
construct the groups. This is a sanity check on a simulation built to
favour the method, not evidence about the real data.

## Saved outputs

- `analysis/results/metrics/05b_grouped_prior_tests.csv`
- `analysis/results/metrics/05b_test_e_recovery.csv`

## Decisions

In grouped mode `omega_hat` is returned as `NULL`. It describes a
factor-specific inclusion probability, which the grouped model does not
have, and filling it with a derived quantity would invite exactly the
wrong reading. The group-level probabilities are returned under their
own name instead.

Group labels supplied by the user are mapped to consecutive codes
internally, and the original labels are kept for the returned object.
Unused factor levels are dropped rather than becoming empty groups.

The grouped prior is refused in combination with
`bool_var_spec_prob = TRUE`, since the two specify incompatible sharing
structures for the same indicators.

A stale default was corrected in the package documentation:
`bayesSYNC.Rd` still described `bool_var_spec_prob` as defaulting to
`TRUE`, which it has not for some time. The `.Rd` files were edited by
hand rather than regenerated, because the installed roxygen2 is a major
version ahead of the one that produced them and regenerating would have
rewritten every file in `man/`, mixing unrelated formatting changes into
this change.

## Limitations and open points

Test E uses one simulation with one seed, block-structured so that each
factor’s active variables lie entirely within one group. Real groupings
will not align with the factors that neatly, so it shows the
implementation can exploit a grouping when one is genuinely there, not
how much it will help in practice.

The grouped prior is not wired into `bayesSYNC_model_choice()`, which
selects the number of factors or components. Model choice will therefore
be run without grouping, or the number of factors fixed in advance, as
the analysis plan already assumes.

## Files

- `bayesSYNCfm/R/bayesSYNC.R` — `prior_groups`, size-adjusted
  hyperparameters, grouped updates, grouped ELBO,
  `check_prior_groups()`, new outputs
- `bayesSYNCfm/man/bayesSYNC.Rd`
- `analysis/R/05b_test_grouped_prior.R`

## Next

Stage 6, the first full-data comparison. Fit vanilla, curated-group and
foundation-model bayesSYNC to the same 1,000-gene panel with identical
settings, together with the matched random controls, and check that
every method converges cleanly.

# Stage 6 — Full-data comparison

## Objective

Fit every condition to the same data under identical settings, and check
that each converges before anything is held out.

## Implementation

`analysis/R/06_fit_models.R` fits thirteen models to the frozen
1,000-gene panel: vanilla bayesSYNC, the curated grouping, the
foundation-model grouping, and five matched random partitions for each
informed grouping. `analysis/R/06b_compare_fits.R` summarises them.

The gene panel, subjects, observations and all other fitting settings
are held fixed: $Q = 5$, $L = 2$, $K = 5$, the dense grid, the scaling,
the annealing schedule, the tolerances and the seed. The conditions
differ in `prior_groups` and in nothing else, and no model is tuned
separately.

Each fit took about seventeen minutes, three and a half hours in total.

## Checks

All thirteen converged, in 115 or 116 iterations. `Q = 5` was
deliberately over-specified and every condition pruned to the same three
active factors, with the two unused ones driven to exactly zero.

Selection is not saturated but it is dense: the three active factors
carry roughly 640, 750 and 500 genes at posterior inclusion probability
above 0.5. The inclusion probabilities are sharply bimodal, so genes are
decisively in or out rather than uncertain.

The grouped prior is doing real work rather than shrinking every group
to a common rate. Group inclusion probabilities range from about 0.09 to
0.49 across foundation-model groups on the first factor.

<img src="analysis/figures/progress/06_full_data_comparison.png" alt="" width="1560" style="display: block; margin: auto;" />

## Results

| Condition | Arm | ELBO | Iterations | Runtime (min) | Active factors | Genes selected |
|:---|:---|---:|---:|---:|---:|---:|
| vanilla | vanilla | -569084.2 | 115 | 15.6 | 3 | 962 |
| fm | informed | -569210.5 | 116 | 16.8 | 3 | 962 |
| curated | informed | -569245.4 | 116 | 16.4 | 3 | 961 |
| random_curated_5 | random | -569280.1 | 115 | 16.8 | 3 | 959 |
| random_fm_1 | random | -569284.6 | 116 | 16.6 | 3 | 962 |
| random_fm_2 | random | -569284.7 | 116 | 17.1 | 3 | 961 |
| random_curated_4 | random | -569284.8 | 116 | 16.7 | 3 | 961 |
| random_fm_4 | random | -569287.0 | 115 | 17.3 | 3 | 962 |
| random_fm_3 | random | -569287.8 | 115 | 17.0 | 3 | 961 |
| random_fm_5 | random | -569288.2 | 115 | 17.6 | 3 | 961 |
| random_curated_2 | random | -569288.5 | 115 | 16.4 | 3 | 960 |
| random_curated_1 | random | -569289.4 | 115 | 17.0 | 3 | 963 |
| random_curated_3 | random | -569290.4 | 115 | 16.8 | 3 | 962 |

| Grouping | ELBO informed | ELBO random mean | Random SD | Gain over matched random | Gap to vanilla |
|:---|---:|---:|---:|---:|---:|
| fm | -569210.5 | -569286.5 | 1.7 | 76.0 | -126.3 |
| curated | -569245.4 | -569286.6 | 4.2 | 41.3 | -161.2 |

The full-data comparison gives two contrasting results. Both informed
groupings fit substantially better than their size-matched random
partitions: the foundation-model grouping by 76 units of ELBO against a
spread of 1.7 among its five nulls, the curated grouping by 41 against a
spread of 4.2. These are large separations relative to the variation
among the nulls. Because the random partitions preserve the group-size
distribution, this difference cannot be attributed to the generic effect
of pooling genes into groups; it is attributable to which genes are
grouped together. The foundation-model grouping also fits better than
the curated one, by about 35.

Vanilla bayesSYNC nevertheless has the highest ELBO of all thirteen,
ahead of the foundation-model grouping by 126 and the curated grouping
by 161. On this dataset, at this panel size, the ungrouped prior
describes the observed data better than any grouping tried.

These results need to be interpreted with some care. The ELBO is a lower
bound on the log marginal likelihood, and the conditions differ in their
prior, so the comparison is a legitimate one between models but the
bounds need not be equally tight. A difference of this size is unlikely
to be explained by that alone, but it is not a certainty either.

The ELBO also measures fit to the data used to estimate the model. The
main question is whether external biological structure helps recover
programmes that generalise, which requires the held-out comparison in
Stage 7.

Selection is dense: each active factor loads on half to three-quarters
of the panel. In that regime the likelihood dominates the prior for most
genes, so the grouped prior has limited leverage, and its main effect is
on the minority of genes whose loading is genuinely uncertain. A sparser
regime would give the mechanism more room. This is a property of
whole-blood data with strong shared structure rather than a fault in the
implementation, and it is not something to tune away after seeing the
result.

## Saved outputs

- `analysis/figures/progress/06_full_data_comparison.png`
- `analysis/results/metrics/06_condition_comparison.csv`,
  `06_informed_vs_random.csv`, `06_fit_summary.csv`

## Decisions

We retain `Q = 5` and allow the model to prune to three active factors,
rather than fixing the number of factors in advance.

The dense grid used here already contains the candidate held-out days
exactly, so Stage 7 changes the data and nothing else.

## Limitations and open points

The fitted objects are about 680 MB each, so this stage occupies 8.9 GB,
driven by the reconstructed trajectories and their credible bands stored
on a 400-point grid for every subject and gene. There is ample disk
here, but each held-out replicate costs the same again, so the grid size
is the thing to reduce first if space becomes a constraint.

Vanilla ranks first by ELBO. This is not yet an answer to the primary
question, and it should still be reported if the held-out results
differ. The two comparisons measure different things and both are
relevant.

## Files

- `analysis/R/06_fit_models.R`
- `analysis/R/06b_compare_fits.R`

## Next

Stage 7, the primary evaluation. Create and save a fixed
subject-specific mask holding out one internal post-vaccination visit
per eligible subject, balanced across days 1 and 7, refit every
condition to exactly the same masked data, and compare paired
reconstruction error on the original analysis scale.

# Stage 7 — Held-out evaluation

## Objective

Ask whether an informed prior improves reconstruction of observations
that were not used for fitting. One internal post-vaccination visit per
subject is hidden, every condition is refitted on identical masked data,
and the hidden expression vectors are compared against their predictions
on the original analysis scale.

The masks come first and are saved before anything is refitted, so that
every condition is evaluated on exactly the same held-out observations.

## Implementation

`analysis/R/07_build_holdout_mask.R` builds the masks. Nothing in the
assignment uses expression values, the groupings or any fitted model:
only the visit design and a fixed seed.

A visit is a candidate for masking if the subject still has observations
on both sides of it once it is removed. Reconstructing it is then
interpolation between retained visits, which is the question the
evaluation asks. Holding out a subject’s last visit would instead test
extrapolation beyond the observed range, and the two should not be mixed
in one error summary. The distinction is not hypothetical: one subject
has no visit after day 7, so for that subject only day 1 is a candidate.
A second subject has no day 1 visit and is therefore assigned day 7. The
remaining 71 subjects have both days available and are assigned at
random.

The assignment is balanced between day 1 and day 7 within each study
group, so the held-out day is not confounded with the COVR/HC
distinction by chance. Subjects must also retain at least three visits.

| Item                                     | Value |
|:-----------------------------------------|------:|
| Subjects in the dataset                  |    73 |
| Subjects with no interior internal visit |     0 |
| Subjects with too few visits             |     0 |
| Subjects eligible                        |    73 |
| Subjects with a single candidate visit   |     2 |
| Masks built                              |     1 |
| Held-out visits per mask                 |    73 |

Subjects held out at each day, by study group.

|      |   1 |   7 |
|:-----|----:|----:|
| COVR |  17 |  16 |
| HC   |  20 |  20 |

`analysis/R/07b_fit_masked.R` refits the thirteen conditions to the
masked data, with the gene panel, $Q$, $L$, $K$, the grid, the scaling,
the annealing schedule, the tolerances and the seed all as they were at
Stage 6. Only the data change.

What it caches is a slimmed fit. Almost the whole of a 755 MB fitted
object is the reconstructed trajectories and their credible bands, held
on a 400-point grid for every subject and gene, and the evaluation needs
those at one grid point per subject. The script takes that slice, drops
the three trajectory lists and keeps everything else, which brings a
cached fit to 25 MB and a full set of thirteen to about 0.3 GB.
Replicates are then affordable.

`analysis/R/07c_evaluate_holdout.R` scores the fits. It returns the
predictions to the original analysis scale, summarises the error per
subject across the 1,000 genes, and compares conditions in pairs on the
same subjects. It also scores a reference predictor, each subject’s own
mean across its retained visits, which uses no model and no hidden value
and says whether the fitted trajectories are worth anything at this time
point.

## Checks

| Check                                            | Value |
|:-------------------------------------------------|:------|
| Held-out observations                            | 73    |
| Exactly one per eligible subject                 | TRUE  |
| All held-out visits internal post-vaccination    | TRUE  |
| All held-out visits bracketed by retained visits | TRUE  |
| Held-out times fall on the fitting grid          | TRUE  |
| Minimum retained visits per subject              | 3     |
| Day 1 observations retained in other subjects    | 35    |
| Day 7 observations retained in other subjects    | 37    |
| Observations used for fitting                    | 290   |

The mask hides 73 of the 363 observations, one per subject, leaving 290
for fitting. Both internal days remain well represented among the
retained observations, 35 at day 1 and 37 at day 7, so neither day
disappears from the data the models are fitted to.

The held-out times fall exactly on the dense grid used at Stage 6. This
is checked rather than assumed: the script rebuilds the grid and tests
membership, so widening the candidate set later would be caught rather
than silently producing predictions off the grid. Days 1 and 7 are on
the grid by construction, and day 0 and day 28 are not, which is why the
candidate set is restricted to the two internal days.

The extraction and unscaling were verified against the Stage 6 fits
before any refitting. Undoing the per-gene scaling recovers the stored
observations exactly. Reading the fitted trajectories at a grid point
and unscaling them reproduces the fitted values in the right subject:
across genes and subjects at day 1, within-gene predicted and observed
values correlate at 0.46, against 0.04 when the subject labels are
shuffled, so the subject alignment is real rather than assumed. The 95%
bands cover 95% of the in-sample values at those times.

<img src="analysis/figures/progress/07_holdout_mask.png" alt="" width="1200" style="display: block; margin: auto;" />

All thirteen masked fits converged, in 121 to 130 iterations, each
pruning $Q = 5$ to the same three active factors and selecting between
931 and 941 genes. Runtimes were 17 to 20 minutes, four hours in total.

| Grouping | ELBO informed | ELBO random mean | Random SD | Gain over matched random | Gap to vanilla |
|:---|---:|---:|---:|---:|---:|
| fm | -456755.7 | -456837.1 | 11.5 | 81.4 | -130.6 |
| curated | -456802.7 | -456823.1 | 6.1 | 20.4 | -177.6 |

On the masked data the Stage 6 ordering repeats. Vanilla still has the
highest ELBO, and both informed groupings still beat their size-matched
nulls: the foundation-model grouping by 81 against a spread of 12 among
its five, close to the 76 seen on the full data. Fitting a subset of the
visits did not disturb the in-sample result.

## Results

| Condition | Arm | RMSE | RMSE day 1 | RMSE day 7 | RMSE offset-corrected | Band coverage |
|:---|:---|---:|---:|---:|---:|---:|
| subject_mean | reference | 0.2848 | 0.3200 | 0.2486 | 0.2848 | NA |
| fm | informed | 0.5120 | 0.5517 | 0.4713 | 0.3110 | 0.8994 |
| random_fm_4 | random | 0.5120 | 0.5520 | 0.4709 | 0.3112 | 0.8994 |
| random_fm_1 | random | 0.5122 | 0.5524 | 0.4708 | 0.3115 | 0.8991 |
| random_fm_3 | random | 0.5122 | 0.5523 | 0.4709 | 0.3114 | 0.8991 |
| curated | informed | 0.5126 | 0.5529 | 0.4712 | 0.3119 | 0.8988 |
| random_fm_2 | random | 0.5127 | 0.5532 | 0.4710 | 0.3122 | 0.8986 |
| random_curated_1 | random | 0.5128 | 0.5533 | 0.4710 | 0.3123 | 0.8987 |
| random_curated_2 | random | 0.5128 | 0.5533 | 0.4711 | 0.3123 | 0.8988 |
| random_fm_5 | random | 0.5128 | 0.5534 | 0.4710 | 0.3123 | 0.8988 |
| vanilla | vanilla | 0.5128 | 0.5534 | 0.4710 | 0.3124 | 0.8987 |
| random_curated_3 | random | 0.5129 | 0.5536 | 0.4711 | 0.3125 | 0.8985 |
| random_curated_4 | random | 0.5130 | 0.5536 | 0.4712 | 0.3126 | 0.8987 |
| random_curated_5 | random | 0.5132 | 0.5542 | 0.4711 | 0.3129 | 0.8983 |

| Comparison | Metric | Error | Reference error | Difference | Subjects better | p |
|:---|:---|---:|---:|---:|---:|:---|
| FM vs vanilla | rmse | 0.5120 | 0.5128 | -0.0008 | 29 | 0.495 |
| Curated vs vanilla | rmse | 0.5126 | 0.5128 | -0.0002 | 32 | 0.590 |
| FM vs matched random | rmse | 0.5120 | 0.5124 | -0.0003 | 26 | 0.096 |
| Curated vs matched random | rmse | 0.5126 | 0.5129 | -0.0003 | 34 | 0.758 |
| Vanilla vs subject mean | rmse | 0.5128 | 0.2848 | 0.2280 | 0 | 1.16e-13 |
| FM vs vanilla | rmse_offset | 0.3110 | 0.3124 | -0.0014 | 41 | 0.037 |
| Curated vs vanilla | rmse_offset | 0.3119 | 0.3124 | -0.0005 | 38 | 0.178 |
| FM vs matched random | rmse_offset | 0.3110 | 0.3117 | -0.0007 | 35 | 0.413 |
| Curated vs matched random | rmse_offset | 0.3119 | 0.3125 | -0.0006 | 41 | 0.041 |
| Vanilla vs subject mean | rmse_offset | 0.3124 | 0.2848 | 0.0276 | 41 | 0.767 |

<img src="analysis/figures/progress/07_holdout_comparison.png" alt="" width="1320" style="display: block; margin: auto;" />

No condition reconstructs the held-out visits better than any other. The
thirteen mean per-subject errors span 0.5120 to 0.5132, a range of about
two parts in a thousand. The foundation-model grouping is nominally
first on both metrics, but three of its own five random partitions fall
between it and vanilla, which is the clearest statement of the result: a
grouping cannot be said to beat its nulls when its nulls are interleaved
with it.

The paired tests agree. Against matched random partitions the
foundation-model grouping differs by −0.0003 on the primary metric and
−0.0007 on the offset-corrected one, neither reliable. Two of the ten
comparisons fall below 0.05, both on the secondary metric and both
unadjusted, with differences of two to four parts in a thousand of the
error and with 41 of 73 subjects on the better side. That is what a set
of ten tests looks like when nothing is there.

The result that does stand out is the reference predictor. Each
subject’s own mean over its retained visits reconstructs the held-out
visit with error 0.285, against 0.513 for vanilla, and it wins for every
one of the 73 subjects. The models are beaten by an average.

The reason is structural rather than a fault in the fitting. bayesSYNC
writes each observation as a per-gene population curve plus a subject
term that passes through three active factors with two spline components
each, so six numbers carry everything that distinguishes one subject
from another across 1,000 genes and five visits. A per-gene subject
intercept is not in the model. On these data the between-subject
variation in a gene has median standard deviation 0.31 against 0.162
within subject, so the missing intercept is most of what there is to
predict, and the fitted residual correlates 0.65 with it.

Granting every condition that offset, measured on the retained visits
alone, is what the second metric does. It brings the error down to 0.311
for the foundation-model grouping and 0.312 for vanilla, and leaves them
no better than assuming the subject does not move between visits, which
is what the reference amounts to once the level is given: the paired
difference between vanilla and the reference is 0.028 with $p = 0.77$.

Day 1 is harder than day 7 for every condition, 0.552 against 0.471,
consistent with day 1 sitting nearer the peak of the response. Credible
bands cover 89.9% of held-out values against a nominal 95%, so they are
slightly too narrow out of sample, having covered 95% in sample at Stage
6.

The honest summary is that the informed prior improves fit to the data
the model sees, reproducibly and by an amount that survives a change of
dataset, and that this improvement does not reach a visit the model
never saw. Two things could produce that, and this experiment does not
separate them. The prior may be adding something real that
reconstruction at one time point is too blunt to detect, or the ELBO
gain may reflect a better description of the observed data that carries
no predictive content. What the experiment does show is that the
temporal part of the model, on this dataset and this panel, barely
improves on assuming no change, and a prior on which genes load on which
factor cannot help predict through factors that carry little.

## Saved outputs

- `analysis/objects/masks/07_holdout_masks.rds`, `07_holdout_masks.csv`
- `analysis/figures/progress/07_holdout_mask.png`,
  `07_holdout_comparison.png`
- `analysis/results/metrics/07_mask_summary.csv`, `07_mask_checks.csv`,
  `07_mask_balance.csv`
- `analysis/results/metrics/07_masked_fit_summary.csv`,
  `07_holdout_summary.csv`, `07_holdout_paired.csv`,
  `07_holdout_subject_errors.csv`

## Decisions

Candidate visits are interior to each subject’s own retained observation
times, not merely internal to the study design. This keeps every
held-out point an interpolation.

Day 1 and day 7 are balanced within study group rather than across the
sample as a whole.

One mask to begin with. The saved table already carries a `replicate`
column, so adding three to five further masks is a change to one
constant in the script and nothing else.

The masks are saved under `analysis/objects/masks/` and tracked, since
`analysis/data/processed/` is not in the repository and the comparison
has to be reproducible from a fresh clone.

Cached masked fits drop the full trajectory lists and keep the held-out
slice. The trajectories can be regenerated by refitting if they are ever
wanted, and keeping them would cost thirty times the disk for output the
evaluation does not read.

Errors are summarised per subject before conditions are compared, so
each subject contributes one number and the comparisons are paired on
the same subjects. Pooling all genes and subjects into one figure would
be dominated by whichever genes happen to be most variable.

A second error metric was added after the vanilla fit was scored and
before any grouped condition was fitted, so it could not be chosen for
the answer it gives. The model places each subject on Q factor loadings
above a population mean curve and has no per-gene subject intercept,
while between-subject variation per gene is about twice the
within-subject temporal variation on these data. The raw error is
therefore dominated by a subject offset that no condition models, which
compresses the differences the project is asking about. The second
metric grants every condition the same offset, measured on the retained
visits alone and computed identically for each, and so isolates the
temporal shape. The pre-specified raw error remains the primary metric
and both are reported.

## Limitations and open points

Every subject contributes one held-out point, so the paired comparison
has 73 pairs and each pair is a whole 1,000-gene expression vector.

Day 1 and day 7 are not equally hard to reconstruct: day 1 sits near the
peak of the innate response, day 7 on a flatter part of the trajectory.
Errors should be reported by day as well as pooled, since pooling could
hide a difference in one and not the other.

Each masked fit estimates its own scaling constants from the retained
observations, so the scaling differs slightly from Stage 6 and between
replicates. This is the right way round, since a scaling estimated with
the held-out visit included would leak it into the fit, but it means
predictions must always be returned to the original scale with the
constants of the fit that produced them.

The reference predictor was included as a floor and turned out to be a
ceiling. A subject mean cannot represent any time trend, so a model that
fails to beat it at the held-out visit is not using the temporal
structure it was given, and none of the thirteen did.

One mask, one panel, one dataset. The evaluation is a single held-out
visit per subject, so it asks a narrow question, and a prior could
matter for programme recovery while making no difference to
interpolation at one time point. Replicate masks would sharpen the
estimate of each difference, but with the informed groupings interleaved
among their own nulls there is no effect for further replicates to
resolve.

The comparison is also underpowered by construction, since the quantity
being compared is mostly the subject offset that no condition models.
The offset-corrected metric removes that, and it does not change the
conclusion.

## Files

- `analysis/R/07_build_holdout_mask.R`
- `analysis/R/07b_fit_masked.R`
- `analysis/R/07c_evaluate_holdout.R`
- `analysis/R/00_setup.R` (adds `path_masks()`)

## Next

The gate in `plan.md` is met: one fair out-of-fit comparison is
complete, and the minimum project is finished. Stage 8, programme
stability under subject subsampling, was conditional on the held-out
comparison working, and the sense in which it did not work matters for
what comes next. The comparison ran as designed and gave a clean answer;
the answer is that no grouping helps at this task.

Adding held-out replicates would not change that, since the informed
groupings sit among their own nulls rather than close to them. The open
question is whether the reproducible in-sample gain means anything, and
reconstruction at one visit cannot answer it. Stage 7d takes that
question to the fits themselves.

# Stage 7d — Why the two comparisons disagree

## Objective

Both fitting runs found the informed groupings fitting the observed data
better than their size-matched random partitions, and the held-out
comparison found no difference between any of the thirteen conditions.
Four questions of the cached fits, with nothing refitted, ask where that
gap comes from: how far the priors move the posterior at all, where the
in-sample advantage sits, whether the groupings capture anything real,
and whether they buy stability instead of accuracy.

## Implementation

`analysis/R/07d_compare_posteriors.R` runs all four on the 26 fits
already saved.

Factor labels and signs are arbitrary, so every comparison of two fits
matches their three active factors first, by loading correlation,
choosing the best of the six permutations exhaustively rather than
greedily.

The ELBO decomposition needs the variational Beta parameters, which are
not returned. They are recovered exactly from the probabilities that are
returned, because their total does not depend on the inclusion sums:
$c^{\ast}_{kq} + d^{\ast}_{kq} = a_k + b_k + n_k$, so multiplying the
returned probability by that total gives back the internal parameters.

## Checks

Rebuilding the same parameters from the inclusion sums instead gives a
slightly different answer, because the group probabilities are updated
before the inclusion indicators within a sweep and the two are therefore
one iteration apart at convergence. The discrepancy is at most 0.58 of a
gene across all thirteen fits, and it is recorded per fit in
`07d_elbo_parts.csv`. It is reported rather than hidden because a fixed
fraction of a gene is negligible across the whole panel and not
negligible inside a 16-gene group.

All thirteen fits have three active factors, so the matching compares
like with like throughout.

## Results

### The priors barely move the posterior

| Condition | Arm | Loading correlation | PPI correlation | Mean \|PPI difference\| | Jaccard | Genes flipped |
|:---|:---|---:|---:|---:|---:|---:|
| fm | informed | 0.99875 | 0.97955 | 0.03689 | 0.94444 | 14 |
| curated | informed | 0.99960 | 0.99148 | 0.02264 | 0.96147 | 6 |
| random_fm_4 | random | 0.99963 | 0.99348 | 0.01704 | 0.97036 | 4 |
| random_curated_5 | random | 0.99988 | 0.99719 | 0.01492 | 0.97595 | 6 |
| random_fm_3 | random | 0.99980 | 0.99588 | 0.01476 | 0.97926 | 4 |
| random_fm_1 | random | 0.99984 | 0.99664 | 0.01303 | 0.97653 | 6 |
| random_curated_1 | random | 0.99991 | 0.99776 | 0.01218 | 0.98142 | 7 |
| random_curated_4 | random | 0.99992 | 0.99818 | 0.01021 | 0.98422 | 5 |
| random_curated_2 | random | 0.99995 | 0.99866 | 0.01014 | 0.97926 | 6 |
| random_curated_3 | random | 0.99996 | 0.99883 | 0.01013 | 0.98115 | 5 |
| random_fm_2 | random | 0.99996 | 0.99879 | 0.00994 | 0.98365 | 6 |
| random_fm_5 | random | 0.99995 | 0.99872 | 0.00994 | 0.98576 | 4 |

<img src="analysis/figures/progress/07d_posterior_agreement.png" alt="" width="1320" style="display: block; margin: auto;" />

Every condition’s loadings correlate with vanilla’s at 0.9987 or above.
The foundation-model grouping moves the posterior furthest, and moving
furthest means a mean change in inclusion probability of 0.037 and a
different selection call for 14 genes out of 1,000. Its matched random
partitions move it by 0.010 to 0.017, flipping four to seven genes.

So the informed groupings do something, and they do about three times as
much as a random partition of the same group sizes. They also do very
little. With posteriors this close, the held-out predictions could not
have differed, and Stage 7 was in that sense answering a question the
fits had already settled.

### The in-sample advantage sits in the prior, not the fit

| Grouping | Total ELBO | Inclusion term | Beta term | Prior terms | Indicator entropy | Everything else |
|:---|---:|---:|---:|---:|---:|---:|
| fm | 81.5 | 165.4 | 11.0 | 176.4 | -56.9 | -38.0 |
| curated | 20.4 | 57.4 | 5.3 | 62.6 | -23.6 | -18.6 |

<img src="analysis/figures/progress/07d_elbo_decomposition.png" alt="" width="1200" style="display: block; margin: auto;" />

The 81 units by which the foundation-model grouping beats its nulls
decompose into 165 gained on the term that rewards each gene’s inclusion
probability for agreeing with its group’s rate, 11 on the Beta term, 57
paid back in the entropy of the inclusion indicators, and 38 paid back
in everything else. Curated shows the same pattern at a quarter of the
size.

Two things follow. The grouped prior sharpens selection: the indicators
become more decisive, which costs entropy. And the block that contains
the data-fit term is 38 units worse for the informed grouping than for
its nulls, so the informed grouping does not describe the observed data
better.

The gain is real and it replicates, but it measures how well the
partition matches the selection pattern the model infers, not how well
the model accounts for the data. A prior that matches the posterior it
induces earns a higher marginal likelihood bound legitimately, and that
is a different claim from predicting a new observation better. The Stage
6 comparison and the group differentiation below are close to two views
of one quantity.

The parts are not orthogonal, since the inclusion probabilities differ
between conditions and enter every term, and the remainder holds the
spline and Gaussian loading contributions as well as the likelihood. The
signs and magnitudes are unambiguous even so.

### The groupings do capture something real

| Condition | Arm | Mean group probability | SD across groups | Range across groups |
|:---|:---|---:|---:|---:|
| curated | informed | 0.2921 | 0.08333 | 0.3691 |
| fm | informed | 0.2813 | 0.10570 | 0.4068 |
| random_fm_1 | random | 0.2917 | 0.03601 | 0.1413 |
| random_fm_2 | random | 0.2922 | 0.03641 | 0.1364 |
| random_fm_3 | random | 0.2961 | 0.03925 | 0.1676 |
| random_fm_4 | random | 0.2970 | 0.03745 | 0.1555 |
| random_fm_5 | random | 0.2947 | 0.03696 | 0.1440 |
| random_curated_1 | random | 0.2891 | 0.05375 | 0.2357 |
| random_curated_2 | random | 0.2970 | 0.04119 | 0.1763 |
| random_curated_3 | random | 0.2948 | 0.04344 | 0.1768 |
| random_curated_4 | random | 0.2927 | 0.04901 | 0.2325 |
| random_curated_5 | random | 0.2965 | 0.05294 | 0.1974 |

<img src="analysis/figures/progress/07d_group_probabilities.png" alt="" width="1320" style="display: block; margin: auto;" />

This is the clearest positive result in the project. Sorting each
factor’s group probabilities and averaging the sorted profiles gives a
curve that does not depend on how groups or factors are labelled. The
foundation-model grouping runs from 0.05 to 0.46 across its twenty
groups, while all five of its size-matched random partitions stay
between about 0.20 and 0.36. Its standard deviation across groups is
0.106 against 0.036 to 0.039 for the nulls, and every null is below it.
Curated sits in between, at 0.083 against 0.041 to 0.054.

The scGPT partition separates genes that load on the inferred factors
from genes that do not, and it does so far beyond what group sizes alone
can produce. Whatever the embeddings encode about these genes is related
to how the genes behave in this dataset.

### It does not buy stability either

| Condition | Arm | Loading correlation | Jaccard of selected genes | Genes flipped |
|:---|:---|---:|---:|---:|
| vanilla | vanilla | 0.84586 | 0.69763 | 29 |
| curated | informed | 0.84006 | 0.70059 | 32 |
| fm | informed | 0.83059 | 0.69663 | 35 |
| random_fm_1 | random | 0.84025 | 0.69550 | 35 |
| random_fm_2 | random | 0.84597 | 0.69762 | 30 |
| random_fm_3 | random | 0.83831 | 0.70544 | 30 |
| random_fm_4 | random | 0.83444 | 0.70136 | 31 |
| random_fm_5 | random | 0.84467 | 0.70135 | 30 |
| random_curated_1 | random | 0.84529 | 0.69553 | 35 |
| random_curated_2 | random | 0.84353 | 0.70037 | 31 |
| random_curated_3 | random | 0.84528 | 0.70052 | 30 |
| random_curated_4 | random | 0.84536 | 0.70290 | 33 |
| random_curated_5 | random | 0.84953 | 0.70198 | 26 |

<img src="analysis/figures/progress/07d_stability.png" alt="" width="1200" style="display: block; margin: auto;" />

Every condition was fitted twice on the same subjects with the same
seed, once on all 363 observations and once on the 290 that survive the
mask, so comparing a condition’s two fits measures how much its
programmes move when the data change, and the five matched partitions
give that measure a null.

Nothing moves in the direction the project hoped for. The
foundation-model grouping’s loadings correlate at 0.831 between its two
fits, against a null mean of 0.841 with all five nulls above it, and
vanilla at 0.846. Curated is 0.840 against 0.846, again with all five
nulls above. Selection overlap tells the same story more weakly.

Taken singly, an informed grouping falling below all five of its nulls
has probability one in six under exchangeability, which is not evidence.
It happens in both families, in the same direction, on a measure where
the informed groupings started with no reason to be worse. The reading
consistent with everything above is that the prior displaces the
posterior slightly from where the likelihood alone would put it, and
that displacement is not reproduced when the data change.

## Saved outputs

- `analysis/figures/progress/07d_posterior_agreement.png`,
  `07d_elbo_decomposition.png`, `07d_group_probabilities.png`,
  `07d_stability.png`
- `analysis/results/metrics/07d_posterior_agreement.csv`,
  `07d_elbo_parts.csv`, `07d_elbo_decomposition.csv`,
  `07d_group_spread.csv`, `07d_stability.csv`, `07d_stability_gap.csv`

## Decisions

The stability question is asked with the fits in hand rather than by
refitting. The perturbation is the mask, which removes one visit per
subject, and it is identical for every condition.

The Beta parameters are recovered from the returned probabilities rather
than rebuilt from the inclusion sums, so that the decomposition uses the
internal state at convergence rather than a version of it one iteration
out of date.

## Limitations and open points

The mask is a weaker and differently shaped perturbation than dropping
subjects. It removes 20% of observations while keeping every subject, so
it disturbs the temporal estimates more than the subject-level ones, and
subject subsampling would do the reverse. A positive stability result
here would have justified the full subsampling run; a null one makes it
less attractive, but does not settle it.

The ELBO parts are not an orthogonal decomposition, and the remainder is
not the likelihood alone.

The group differentiation result is the one that deserves following up.
It says the scGPT partition tracks something real about which genes
load, and the project has so far only asked whether that helps the two
things bayesSYNC was measured on. It might matter for interpretation, or
in a sparser regime where the prior has more leverage, and neither has
been tested.

## Files

- `analysis/R/07d_compare_posteriors.R`

## Next

The four diagnostics leave a coherent picture and a clear choice. The
prior acts, its action is aligned with real structure, and at this panel
size and sparsity the likelihood is strong enough that the action
changes almost nothing the model then does.

Two things follow from that and neither is Stage 8 as written. Stage 7e
tests whether the prior has leverage when selection is not dense.
Separately, the group differentiation result stands on its own and is
worth reporting whatever happens next.

# Stage 7e — Does the prior have leverage in a sparser regime?

## Objective

Stage 7d found the foundation-model grouping changing the selection call
for 14 genes out of 1,000. One explanation is the regime rather than the
grouping: each active factor loads on half to three-quarters of the
panel, and where the likelihood is that decisive a prior on inclusion
has little room to act.

This is a diagnostic of the regime. The configuration is changed after
seeing the Stage 7 result, so nothing here can be reported as a
headline; it exists to say whether the null result depends on the
sparsity setting.

## Implementation

`analysis/R/07e_sparsity_diagnostic.R` does two things.

The first needs no fitting. A gene’s inclusion log-odds is a data term
plus a prior term, and the prior term is known, so the data terms can be
recovered from the cached vanilla fit and the selection under any other
prior strength predicted by holding them fixed and iterating the rate to
its fixed point. This sizes the experiment.

The second refits three conditions at the chosen strength: vanilla, the
foundation-model grouping, and one matched random partition, so the
grouping can be compared against both. Everything else is held at the
Stage 7 settings, including the mask, the panel and the seed. Only $d_0$
changes, from $p$ to $1000p$.

| $d_0$ as a multiple of $p$ | Prior log-odds | Predicted selection, factor 1 | Factor 2 | Factor 3 |
|---:|---:|---:|---:|---:|
| 1e+00 | -0.87 | 0.664 | 0.533 | 0.459 |
| 1e+01 | -2.87 | 0.566 | 0.479 | 0.361 |
| 1e+02 | -5.14 | 0.497 | 0.430 | 0.296 |
| 1e+03 | -7.44 | 0.449 | 0.383 | 0.241 |
| 1e+04 | -9.74 | 0.410 | 0.355 | 0.198 |
| 1e+05 | -12.04 | 0.364 | 0.326 | 0.182 |

The prior term enters as $\psi(c_0 + s) - \psi(d_0 + p - s)$, which
moves about as $-\log d_0$, so each tenfold increase in $d_0$ buys
roughly 2.3 of log-odds. The data log-odds are bimodal, with a quarter
of gene-factor pairs below $-1.25$ and a quarter above $+18$. Genuine
sparsity would need $d_0$ larger by something like $e^{18}$, which is
not a prior anyone would defend. The dense selection is a property of
the evidence, not a tuning choice.

## Checks

At $d_0 = 1000p$ the prediction was that selection on the leading factor
would fall from 0.665 to 0.449. The refit gave 0.448.

It also did something the prediction could not anticipate, since the
prediction holds the factor structure fixed: the model pruned from three
active factors to one. The sparser regime is therefore not the same
model with fewer genes selected, but a smaller model.

## Results

| Regime | Condition | ELBO | Active factors | Selection per factor | Genes selected | Genes flipped vs vanilla |
|:---|:---|---:|---:|---:|---:|---:|
| dense | vanilla | -456625.1 | 3 | 0.552 | 941 | NA |
| sparse | vanilla | -491765.3 | 1 | 0.448 | 448 | NA |
| dense | fm | -456755.7 | 3 | 0.544 | 931 | 14 |
| sparse | fm | -491748.0 | 1 | 0.454 | 454 | 20 |
| dense | random_fm_1 | -456842.0 | 3 | 0.553 | 937 | 6 |
| sparse | random_fm_1 | -491833.5 | 1 | 0.448 | 448 | 0 |

<img src="analysis/figures/progress/07e_sparsity.png" alt="" width="1320" style="display: block; margin: auto;" />

The prior does gain leverage, and the ordering reverses. In the sparser
regime the foundation-model grouping has the highest ELBO of the three,
ahead of vanilla by 17 and ahead of its matched random partition by 85.
In the dense regime vanilla led both. The contrast between informed and
random widens at the same time: the grouping now changes the selection
call for 20 genes against vanilla, while the random partition of the
same group sizes changes none at all, against 14 and 6 before.

| Regime | Condition | Mean group probability | SD across groups | Coefficient of variation |
|:---|:---|---:|---:|---:|
| dense | fm | 0.281000 | 1.06e-01 | 0.380 |
| sparse | fm | 0.000441 | 2.68e-04 | 0.608 |
| dense | random_fm_1 | 0.292000 | 3.60e-02 | 0.129 |
| sparse | random_fm_1 | 0.000449 | 7.52e-05 | 0.167 |

Group differentiation survives the change of scale and increases in
relative terms. The absolute probabilities collapse, from about 0.28 to
about 0.0004, so the spread has to be read as a coefficient of variation
to be comparable: the foundation-model grouping goes from 0.38 to 0.61,
its matched random partition from 0.13 to 0.17. The grouping separates
its groups more sharply, not less, when the prior is stronger.

| Regime | Condition   | Mean per-subject RMSE |
|:-------|:------------|----------------------:|
| dense  | vanilla     |                0.5128 |
| sparse | vanilla     |                0.4985 |
| dense  | fm          |                0.5120 |
| sparse | fm          |                0.4981 |
| dense  | random_fm_1 |                0.5122 |
| sparse | random_fm_1 |                0.4986 |

None of it reaches prediction. The three sparse conditions differ from
each other by 0.0005 in held-out error, the same negligible margin as
before, and the foundation-model grouping is again nominally first.

The regime itself does far more than any prior information. Every sparse
fit reconstructs the held-out visits better than every dense fit, 0.498
against 0.512, an improvement of about 0.014, which is roughly
twenty-five times the largest difference between conditions in either
regime. A model with one factor and 448 selected genes predicts better
than one with three factors and 941. All of them remain far behind the
per-subject mean at 0.285.

## Saved outputs

- `analysis/figures/progress/07e_sparsity.png`
- `analysis/results/metrics/07e_prior_leverage.csv`,
  `07e_data_log_odds.csv`, `07e_regime_summary.csv`,
  `07e_group_spread.csv`, `07e_holdout_error.csv`

## Decisions

$d_0 = 1000p$ was chosen from the analytic prediction, as the point
where selection changes substantially while the model still selects a
good part of the panel, and fixed before the refits.

One matched random partition rather than five, because the diagnostic
asks whether the informed grouping acts differently from a random one of
the same shape, not how large that difference is relative to a null
distribution.

## Limitations and open points

The reversal of the ELBO ordering is measured against a single random
partition, so there is no null spread to judge the gap of 85 against.
Reading it as evidence that content matters more in the sparser regime
requires the other four partitions, and this diagnostic does not have
them.

The prior used here has an implied mean inclusion probability of about
$10^{-6}$. It is a device for probing the regime, not a defensible
prior, and the fact that it improves held-out reconstruction says more
about the model being over-parameterised at $Q = 5$ with dense selection
than about the prior being right.

Pruning to a single factor makes the comparison between regimes one
between two different models. The held-out improvement cannot be
attributed to sparsity alone.

## Files

- `analysis/R/07e_sparsity_diagnostic.R`

## Next

The diagnostic answers its question. The Stage 7 null is not simply an
artefact of dense selection, since the prior does gain leverage when it
is strong enough to matter, and the informed grouping separates from a
random one more clearly there than it did before. The leverage is still
far too small to move prediction, and the largest effect in this table
belongs to model size rather than to any external information.

The result worth following up is the one the diagnostic strengthened
rather than the one it was aimed at: the foundation-model partition
differentiates its groups about three times as sharply as a size-matched
random partition in both regimes. That is a statement about what the
embeddings know, and it has not yet been asked in a form where the
answer could matter, which reconstruction at one visit and this model’s
three loadings per subject cannot provide.

<!-- Reusable stage template: analysis/report/stage_template.Rmd -->
