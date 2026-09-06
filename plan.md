# EmbedSYNC: foundation-model-informed bayesSYNC

## Aim

EmbedSYNC is a small, reproducible extension of **bayesSYNC** that asks:

> **Can biological structure learnt from a large pretrained single-cell model help recover more stable and predictive longitudinal biological programmes from a comparatively small repeated-measures transcriptomic study?**

The project combines two sources of information:

1. a frozen single-cell foundation model, used only to obtain **gene-level representations** learnt during pretraining;
2. a longitudinal transcriptomic study, analysed with bayesSYNC to learn dynamic latent factors and subject-specific trajectories.

The foundation model supplies external information about relationships among genes. The longitudinal data remain responsible for deciding which dynamic programmes are supported, how genes load onto them, how those programmes evolve over time, and how individuals differ.

This is deliberately a bounded proof of concept. It is not a foundation-model training project and it is not intended to redesign the functional part of bayesSYNC.

---

## Repository layout

Recommended layout:

```text
EmbedSYNC/
├── README.md
├── plan.md
├── PROGRESS.Rmd
├── .gitignore
├── analysis/
│   ├── README.md
│   ├── R/
│   │   ├── 00_setup.R
│   │   ├── 01_prepare_data.R
│   │   ├── 02_define_gene_panel.R
│   │   ├── 03_build_fm_groups.R
│   │   ├── 04_build_curated_groups.R
│   │   ├── 05_build_random_groups.R
│   │   ├── 06_fit_models.R
│   │   ├── 07_holdout_evaluation.R
│   │   ├── 08_stability_analysis.R
│   │   └── 09_make_figures.R
│   ├── python/
│   │   └── 01_extract_scgpt_gene_embeddings.py
│   ├── data/
│   │   ├── raw/
│   │   ├── processed/
│   │   └── external/
│   ├── metadata/
│   ├── objects/
│   │   ├── embeddings/
│   │   ├── groups/
│   │   └── fits/
│   ├── results/
│   │   ├── metrics/
│   │   └── tables/
│   └── figures/
│       └── progress/
└── bayesSYNCfm/
    └── [the group-informed R package]
```

The top-level `EmbedSYNC` directory is the public project repository. `README.md` is the public-facing entry point; `plan.md` is the detailed technical specification.

`bayesSYNCfm/` is the R package implementing the group-informed prior. It is a derivative of bayesSYNC, carries its own package name so that it installs alongside bayesSYNC rather than replacing it, and is **tracked by the EmbedSYNC repository**. It has no Git remote of its own: EmbedSYNC is the only version-controlled directory, so the package modifications are recorded in the same history as the analysis that uses them.

The exported function names are shared with bayesSYNC. Call them with an explicit namespace, `bayesSYNCfm::bayesSYNC()` and `bayesSYNC::bayesSYNC()`, so that the two are never confused.

Record in `PROGRESS.Rmd` the upstream bayesSYNC commit the package was derived from, and the version of the installed bayesSYNC used as the reference in Test A.

### Git policy

Git operations are manual. Changes are inspected and committed by hand, so that each commit corresponds to a stage whose checks have passed.

### Public documentation policy

`README.md` is the concise public-facing description of the project. Keep it readable and current, but do not turn it into a running lab notebook.

Update `README.md` when a stable project-level fact changes, for example:

- the primary dataset has been fixed;
- the grouped-prior implementation is working;
- the evaluation design has been finalised;
- a main result or figure is ready;
- installation or reproducibility instructions change.

Detailed stage-by-stage work, diagnostics, failed attempts and provisional results belong in `PROGRESS.Rmd`.


---

# 1. Model

For subject \(i=1,\ldots,N\), gene \(j=1,\ldots,p\), and time \(t\), bayesSYNC models

\[
y_{ij}(t)
=
\mu_j(t)
+
\sum_{q=1}^{Q} b_{jq}h_{iq}(t)
+
\varepsilon_{ij}(t),
\]

where \(q\) indexes a dynamic latent factor and

\[
h_{iq}(t)
=
\sum_{\ell=1}^{L}
\zeta_{iq\ell}\psi_{q\ell}(t).
\]

The loading \(b_{jq}\) quantifies the contribution of gene \(j\) to factor \(q\). The current factor-specific spike-and-slab formulation is

\[
b_{jq}\mid\gamma_{jq}
\sim
\gamma_{jq}N(0,1)+(1-\gamma_{jq})\delta_0,
\]

\[
\gamma_{jq}\mid\omega_q
\sim
\operatorname{Bernoulli}(\omega_q),
\qquad
\omega_q\sim\operatorname{Beta}(c_0,d_0).
\]

With the current default \(c_0=1\), \(d_0=p\), the prior expected number of active genes per factor is

\[
p\,E(\omega_q)
=
p\frac{1}{p+1}
\approx 1.
\]

The proposed extension changes the prior sharing structure for \(\gamma_{jq}\), not the likelihood, temporal basis, FPCA representation or slab distribution.

---

# 2. Group-informed prior

Suppose each gene is assigned to one externally defined group,

\[
m(j)\in\{1,\ldots,K_G\}.
\]

For group \(k\), let

\[
G_k=\{j:m(j)=k\},
\qquad
n_k=|G_k|.
\]

Introduce a group- and factor-specific inclusion probability,

\[
\pi_{kq}\sim\operatorname{Beta}(a_k,b_k),
\]

\[
\gamma_{jq}\mid m(j)=k,\pi_{kq}
\sim
\operatorname{Bernoulli}(\pi_{kq}).
\]

The loading prior remains

\[
b_{jq}\mid\gamma_{jq}
\sim
\gamma_{jq}N(0,1)+(1-\gamma_{jq})\delta_0.
\]

There is no one-to-one correspondence between external groups and dynamic factors:

- \(k\) indexes an externally supplied gene group;
- \(q\) indexes a dynamic factor learnt from the longitudinal data.

Several external groups may contribute to one dynamic factor, and the same external group may contribute to several factors.

The external grouping informs **co-selection propensity only**. It does not force genes in the same group to have the same loading sign or magnitude. Those remain data-driven.

## 2.1 Prior calibration

Do **not** simply assign the original \(\operatorname{Beta}(c_0,d_0)\) prior independently to every group. That would multiply the effective prior concentration by the number of groups and, with the sparse default \(d_0=p\), would make each group unnecessarily difficult to update.

Use size-adjusted group hyperparameters:

\[
\rho_k=\frac{n_k}{p},
\qquad
a_k=\rho_k c_0,
\qquad
b_k=\rho_k d_0.
\]

This preserves the original prior mean,

\[
E(\pi_{kq})
=
\frac{c_0}{c_0+d_0},
\]

so the prior expected total number of active genes remains

\[
\sum_k n_kE(\pi_{kq})
=
p\frac{c_0}{c_0+d_0}.
\]

It also scales the prior concentration with group size. If all genes belong to one group, \(n_1=p\), then \(a_1=c_0\) and \(b_1=d_0\), so the grouped model reduces exactly to the original factor-specific model.

This calibration should be treated as part of the model definition and tested explicitly.

A sensitivity analysis using unscaled group hyperparameters can be considered later, but it is not part of the minimum project.

---

# 3. Variational update

Let \(c=T^{-1}\) denote the inverse temperature used by the current annealed variational algorithm.

For each group \(k\) and factor \(q\),

\[
a^*_{kq}
=
c\left(
a_k+\sum_{j\in G_k}E_q[\gamma_{jq}]
\right)-c+1,
\]

\[
b^*_{kq}
=
c\left(
b_k+n_k-\sum_{j\in G_k}E_q[\gamma_{jq}]
\right)-c+1.
\]

Then

\[
E_q[\log \pi_{kq}]
=
\psi(a^*_{kq})
-
\psi(a^*_{kq}+b^*_{kq}),
\]

\[
E_q[\log(1-\pi_{kq})]
=
\psi(b^*_{kq})
-
\psi(a^*_{kq}+b^*_{kq}).
\]

For gene \(j\), the spike-and-slab inclusion update uses the expectations associated with \(m(j)\).

The ELBO contribution of the Beta terms becomes a sum over groups and factors. The existing \(q(b_{jq},\gamma_{jq})\) contribution remains a sum over genes and factors, with the corresponding group-specific expected log inclusion probabilities.

Before coding these changes, verify the exact current update and ELBO in the checked-out package and in the bayesSYNC supplement. The package implementation is the operational source of truth for code changes.

---

# 4. External information sources

The same grouped bayesSYNC implementation will be used with several group assignments.

## 4.1 M0: vanilla bayesSYNC

No groups.

This is the essential baseline and answers:

> Does introducing external grouping information improve on the original model?

Use the factor-specific prior, i.e. `bool_var_spec_prob = FALSE`.

## 4.2 M1: curated-biology groups

Use **Reactome** gene-pathway membership.

For gene \(j\), let \(A_j\) be the set of Reactome pathways containing that gene. Define

\[
S^{curated}_{jj'}
=
\frac{|A_j\cap A_{j'}|}
{|A_j\cup A_{j'}|}.
\]

Construct a weighted gene graph from **positive** pathway-overlap similarities and then obtain a non-overlapping partition using the same broad graph/community-detection strategy used for the foundation-model representation. Do not create arbitrary nearest-neighbour edges between genes whose Reactome similarity is exactly zero. Inspect isolates explicitly; if there are many, revisit the common gene panel or use a documented `unassigned` rule.

Why not use raw Reactome pathways directly?

- pathways overlap;
- the first grouped-prior implementation assigns one group per gene;
- using a common partitioning strategy makes the comparator easier to interpret.

Record the Reactome data source/version or retrieval date. Do not tune the grouping against predictive performance.

## 4.3 M2: foundation-model groups

Initial foundation model: **scGPT**.

scGPT is a single-cell foundation model. We do **not** pass the bulk longitudinal samples through it as though they were cells. We extract the static gene-token representation learnt during pretraining.

For gene \(g_j\),

\[
e_j
=
E_{\widehat\theta_{\mathrm{pre}}}(g_j)
\in\mathbb R^d.
\]

Read \(d\) from the actual checkpoint. Do not hard-code it.

The official scGPT workflow exposes data-independent gene embeddings and uses them to construct a gene-embedding network and gene programmes. We will follow that principle rather than invent a separate foundation-model workflow.

No fine-tuning is planned.

### FM similarity and groups

L2-normalise the embeddings and use cosine similarity,

\[
S^{FM}_{jj'}
=
\frac{e_j^\top e_{j'}}
{\|e_j\|\,\|e_{j'}\|}.
\]

Construct a nearest-neighbour graph and obtain communities with Leiden or Louvain.

For a first run with 1,000–2,000 genes, roughly 10–30 groups is a practical target, not a parameter to optimise against model performance.

Do not infer biological meaning from the magnitude of cosine similarities alone.

## 4.4 M3: matched random controls

Random grouping is a negative control for the **grouping mechanism itself**.

For each informed grouping, generate random partitions by permuting the gene labels while preserving the complete group-size distribution.

Thus there are two matched null families:

- random partitions matched to the FM groups;
- random partitions matched to the curated groups.

Use at least 5 random permutations for a first comparison. Increase to 10–20 only if model fits are cheap.

Do not regenerate random partitions inside fitting functions. Save them with fixed seeds.

---

# 5. Primary dataset

Start with **GSE194378**, a longitudinal whole-blood RNA-seq study around seasonal influenza vaccination.

The GEO record reports:

- 33 participants recovered from mild SARS-CoV-2 infection;
- 40 age- and sex-matched controls;
- blood collection at multiple times around vaccination;
- RNA-seq selected at days approximately \(-7,0,1,7,28\);
- technical controls and some resequenced samples;
- processed gene-count matrices available from GEO.

This gives approximately 73 biological participants with up to five transcriptomic measurements each, but the exact usable sample set must be reconstructed from metadata rather than assumed.

Why this dataset is attractive:

- enough subjects to study between-person heterogeneity;
- a real longitudinal perturbation;
- five transcriptomic time points rather than only two;
- whole-blood RNA-seq aligns naturally with gene-level foundation-model information;
- processed files are modest enough for a laptop.

## 5.1 Fallbacks

If GSE194378 becomes disproportionately awkward to prepare, switch rather than spending a day repairing metadata.

First fallback: **GSE48018**

- approximately 116 male participants after QC;
- days 0, 1, 3 and 14;
- whole-blood microarray;
- companion female cohort GSE48023 could later provide replication.

Second fallback: **GSE45735**

- five subjects;
- daily RNA-seq from day 0 through day 10.

GSE45735 is useful for debugging or visualisation, but \(N=5\) is not sufficient for the main claim about stable between-person programmes.

---

# 6. Feasibility gate before package modification

Do not modify bayesSYNC until the real dataset works with vanilla bayesSYNC.

For GSE194378:

1. download only processed data and metadata;
2. distinguish biological samples, technical controls and resequenced samples;
3. create a subject-by-time availability table;
4. establish the exact five RNA-seq times used;
5. resolve technical replicates with a documented rule;
6. inspect missingness;
7. inspect the processed expression scale;
8. map row identifiers to stable gene identifiers;
9. determine overlap with the chosen scGPT vocabulary;
10. fit vanilla bayesSYNC to a 200–500-gene pilot;
11. inspect convergence, factor activity and reconstructed trajectories.

### Stop/go rule

Proceed only if vanilla bayesSYNC fits cleanly and the temporal representation behaves sensibly.

If the five-time-point design proves unsuitable for the current functional implementation, switch dataset. Do not rewrite the trajectory model as part of this project.

---

# 7. Expression preprocessing

bayesSYNC uses a Gaussian observation model. Use a continuous, approximately variance-stabilised expression scale.

For GSE194378:

1. inspect the authors' processed normalised count matrix first;
2. document how the original study normalised the data;
3. if values remain count-like and strongly mean-variance dependent, use a simple documented transformation such as \(\log_2(x+1)\);
4. do not reprocess FASTQ files.

Do not use subject labels, prior infection status, antibody response or post-vaccination phenotypes to select genes.

---

# 8. Gene panel

Use the same genes in M0, M1, M2 and the corresponding random controls.

Target roughly **1,000–2,000 genes** initially.

Required:

1. reliably measured in the longitudinal dataset;
2. represented in the scGPT vocabulary;
3. usable in the curated comparator, or handled by an explicit documented rule;
4. one unambiguous identifier per gene.

### Feature selection

Avoid using the held-out post-vaccination measurements to decide which genes enter the model.

Preferred primary rule:

- filter on baseline detectability/expression;
- rank genes using baseline information only, if ranking is needed;
- fix the panel before the primary holdout comparison.

A simple expression-based baseline filter is preferable to a complex outcome-aware selection rule.

If Reactome coverage would discard an excessive fraction of otherwise suitable genes, assess two options before proceeding:

- an explicit `unassigned` curated group;
- a common panel restricted to annotated genes.

Choose the option that produces the cleaner fair comparison and document the effect on \(p\).

---

# 9. Building the external groups

All grouping tables must use stable gene identifiers and be explicitly aligned to the final bayesSYNC variable order.

Save at least:

```text
gene_id
gene_symbol
group
source
```

along with a group-size table and construction parameters.

## 9.1 FM groups

Pipeline:

```text
frozen scGPT checkpoint
        ↓
gene-token embeddings
        ↓
final common gene panel
        ↓
L2 normalisation
        ↓
nearest-neighbour graph using cosine similarity
        ↓
Leiden/Louvain
        ↓
one FM-derived group per gene
```

Cache the gene embeddings. Do not reload the foundation model during routine R analyses.

## 9.2 Curated groups

Pipeline:

```text
Reactome gene-pathway membership
        ↓
final common gene panel
        ↓
gene-gene Jaccard similarity
        ↓
nearest-neighbour graph
        ↓
same community-detection family
        ↓
one curated group per gene
```

Use a comparable graph-building strategy for FM and curated similarities. The exact partitions do not need to have identical group sizes.

## 9.3 Random controls

For each informed grouping, permute gene labels while keeping group labels and therefore group sizes fixed.

Save the partitions before fitting.

---

# 10. bayesSYNC package extension

Add an argument to `bayesSYNC()`:

```r
prior_groups = NULL
```

Expected behaviour:

- `NULL`: current model, unchanged;
- supplied named vector/factor of length \(p\): grouped prior;
- grouped mode requires `bool_var_spec_prob = FALSE`;
- missing or duplicated gene mappings fail clearly.

Do not overload `bool_var_spec_prob`.

## 10.1 Input rules

Prefer a named vector with names equal to the bayesSYNC variable names.

Validate:

- length \(p\);
- no missing group labels;
- unique gene names;
- exact gene-set agreement;
- explicit reordering by name only when safe.

Internally map arbitrary labels to consecutive group IDs, but retain original group labels in the fitted object.

## 10.2 Output

Preserve every existing output.

Add:

```text
prior_groups
group_inclusion_prob
group_prior_hyperparameters
```

`group_inclusion_prob` should be a \(K_G\times Q\) matrix of posterior means \(E(\pi_{kq}\mid Y)\), with informative row and column names.

Use a name that reflects the object rather than reusing `omega_hat` ambiguously.

---

# 11. Package validation

These checks must pass before the real grouped analysis.

## Test A: unchanged default path

With `prior_groups = NULL`, same data and seed, the modified package should reproduce the original package within numerical tolerance.

Compare at least:

- `B_hat`;
- `ppi`;
- `omega_hat`;
- factor PPIs;
- final ELBO;
- reconstructed trajectories where practical.

## Test B: one-group identity

Assign all genes to one group:

```r
prior_groups <- rep("all", p)
```

With the size-adjusted prior, this must reduce exactly to the original factor-specific Beta-Bernoulli model.

This is the strongest implementation test.

## Test C: prior-calibration check

For several artificial group-size vectors, verify numerically that

\[
\sum_k n_k E(\pi_{kq})
=
p\frac{c_0}{c_0+d_0}.
\]

This protects against inadvertently changing the expected sparsity merely by changing the partition.

## Test D: update-level check

On a tiny synthetic example, compare the coded grouped Beta update with a direct R implementation of the equations in Section 3.

## Test E: simulated grouped signal

Create a small synthetic dataset in which active genes are concentrated in known groups.

Compare:

- correct groups;
- matched random groups;
- vanilla model.

This is a sanity check, not a simulation study.

## Test F: annealing and ELBO

Run grouped fits with:

- `anneal = NULL`;
- the standard annealing schedule.

Check convergence and consistency of the ELBO implementation.

---

# 12. Main comparison

The comparison is:

\[
\text{M0: vanilla}
\]

\[
\text{M1: curated-group informed}
\]

\[
\text{M2: FM-group informed}
\]

plus matched random partitions for M1 and M2.

Keep identical across methods wherever possible:

- gene panel;
- subjects;
- observations;
- \(Q\);
- \(L\);
- spline settings;
- scaling;
- annealing schedule;
- convergence tolerances;
- initialisation seeds.

Do not tune each model separately to improve its result.

Start small:

- \(p\approx1,000\);
- conservative \(Q\) and \(L\);
- one seed;
- one full-data fit per method.

Only increase \(p\), repeated seeds or random controls after the basic comparison works.

---

# 13. Primary evaluation: held-out visits

The primary empirical evaluation is **within-subject held-out-visit reconstruction**, not pathway enrichment.

The held-out unit is the full \(p\)-gene expression vector at one subject-time visit. This tests whether a model fitted to the subject's remaining visits and the other subjects can reconstruct an unseen visit for that individual. It is not a claim about forecasting an entirely new subject.

For GSE194378, use internal post-vaccination visits such as day 1 and day 7 as the candidate masking set.

## 13.1 Mask design

Prefer repeated **subject-specific masks** rather than removing the same time point from every subject.

For each replicate:

1. restrict to subjects with enough observed visits that at least three or four remain after masking;
2. hold out one eligible internal visit per subject;
3. balance the masks so day 1 and day 7 are both represented and neither time is removed globally;
4. fit each model to exactly the same masked dataset;
5. reconstruct every held-out subject-time vector;
6. compare with the unseen observed values.

This design keeps the global temporal structure informed by other subjects at both candidate times and focuses the evaluation on subject-specific longitudinal reconstruction.

Start with 3–5 fixed masking replicates. Save the masks before any model fitting.

A harder whole-time-point ablation, for example removing day 1 from every subject, can be considered later but is not the primary evaluation.

## 13.2 Prediction extraction

bayesSYNC reconstructs trajectories on a dense `time_g`. Before fitting the holdout models, define `time_g` so that every candidate held-out time occurs **exactly** on that grid rather than relying on approximate nearest-grid matching.

After fitting:

1. locate the exact held-out time in `time_g`;
2. extract the posterior mean reconstruction for that subject and gene;
3. if `bool_scale = TRUE`, transform predictions back to the original analysis scale using the scaling parameters returned by bayesSYNC;
4. only then compute errors.

Verify this workflow on one subject/gene before running the full comparison.

### Metrics

Primary:

\[
RMSE
=
\sqrt{
\frac{1}{|\mathcal H|}
\sum_{(i,j,t)\in\mathcal H}
(y_{ij}(t)-\widehat y_{ij}(t))^2
}.
\]

Also report MAE.

Because every method predicts the same held-out observations, retain paired per-observation errors and summarise variation across masking replicates.

If a correct held-out predictive density is already available with little additional work, report it. Do not expand the project substantially to create one.

### Minimum evaluation

Minimum:

- one complete fixed mask replicated across all methods.

Preferred:

- 3–5 prespecified subject-specific masking replicates.

Do not run a large cross-validation grid before these work.

---

# 14. Secondary evaluation: programme stability

External biological information may improve **stability** even if RMSE changes little.

Procedure:

1. repeatedly sample approximately 80% of subjects;
2. refit each model;
3. match factors across fits;
4. compare loading vectors and/or high-PPI gene sets.

Factor labels and signs are arbitrary.

Use an assignment algorithm based on absolute loading correlation, then orient matched factors consistently before reporting signed correlations.

Possible summaries:

\[
\operatorname{cor}
\left(
\widehat{\mathbf b}^{(r)}_q,
\widehat{\mathbf b}^{(r')}_{q'}
\right),
\]

and Jaccard similarity of selected high-PPI genes.

Start with 3–5 subsamples.

---

# 15. Biological interpretation

Biological annotation is useful, but it is not the primary validation.

For selected factors:

- list genes with high posterior inclusion probabilities and/or large loadings;
- show the corresponding subject-specific trajectories;
- show which external groups contribute strongly;
- use independent biological annotation where possible.

Do **not** validate Reactome-derived groups by showing enrichment for the same Reactome pathways used to construct them. That is circular.

For FM-derived factors, pathway enrichment can be reported descriptively, with a clear distinction between interpretation and predictive evaluation.

---

# 16. Progress report

`PROGRESS.Rmd` is a living reproducible research report and must be updated after every substantive stage.

It should combine concise narrative with code chunks, tables and figures so that the current state of the project can be rendered directly to HTML:

```r
rmarkdown::render("PROGRESS.Rmd", output_format = "all")
```

Two formats are produced. `PROGRESS.md` is version-controlled and renders on GitHub, so the state of the project is readable without cloning. `PROGRESS.html` carries the floating table of contents and code folding, and is a local build artefact ignored by Git.

The source `PROGRESS.Rmd`, the small result tables under `analysis/results/` and the figures under `analysis/figures/progress/` are all version-controlled, since the report reads them rather than recomputing. Ignoring them would leave the report unbuildable from a fresh clone without rerunning every model fit.

The report should allow someone opening the repository to understand:

- what has been done;
- what data and software versions were used;
- which decisions were made and why;
- what passed or failed;
- the first numerical results;
- important caveats;
- what comes next.

Each substantive stage should contain:

```text
Date / stage
Objective
Work completed
Checks and QC
Results
Figures and tables
Decisions
Open issues
Next step
Files changed/created
```

Prefer executable chunks that read small saved result tables and generate figures from them. Do not rerun expensive model fits when knitting the report. Expensive analyses should save their outputs first; `PROGRESS.Rmd` should read those cached outputs.

Save useful diagnostic figures under:

```text
analysis/figures/progress/
```

Examples worth preserving as the work progresses:

- subject-by-time availability;
- expression-scale diagnostics;
- scGPT/Reactome gene coverage;
- group-size distributions;
- embedding/group diagnostic plots;
- vanilla bayesSYNC pilot trajectories;
- package identity-test results;
- held-out error comparisons;
- stability comparisons.

Keep negative findings and failed gates when they affect later decisions. Do not reconstruct the project history from memory at the end.

`README.md` should be updated only when the public-facing project state changes materially; it should link to `PROGRESS.Rmd` for the detailed research record.

---

# 17. Reproducibility

Record:

- starting bayesSYNC commit SHA;
- later bayesSYNC commit SHA used for each analysis;
- dataset accession and retrieval date;
- scGPT checkpoint identifier and source;
- scGPT vocabulary/checkpoint metadata;
- Reactome source/version or retrieval date;
- R and Python package versions;
- all random seeds;
- all final grouping parameters.

Cache expensive external artefacts locally.

Do not version-control:

- raw downloaded datasets;
- foundation-model checkpoints;
- large fitted objects;
- locally installed package libraries under `analysis/lib/`.

Version-control:

- scripts;
- the `bayesSYNCfm/` package source;
- small metadata tables under `analysis/metadata/`;
- final gene/group mappings if licensing permits;
- metrics;
- figures;
- `plan.md`;
- `PROGRESS.Rmd`;
- `README.md`.

Keep large expression matrices and model artefacts reproducible from scripts rather than committed.

---

# 18. Resource constraints

Assume laptop execution.

Before expensive work, estimate:

- download size;
- matrix dimensions;
- number of model fits;
- expected disk footprint.

Do not:

- download raw FASTQ data;
- download millions of single-cell profiles;
- fine-tune scGPT;
- run exhaustive hyperparameter searches;
- create hundreds of random-control fits;
- compute a full \(p\times p\) similarity matrix if a nearest-neighbour implementation is simpler and more memory-efficient.

For \(p\le2,000\), a full similarity matrix is still feasible, but it is not required.

---

# 19. Ordered implementation plan

Follow these gates in order.

## Stage 0: scaffold

1. create the repository structure;
2. create `.gitignore`;
3. derive `bayesSYNCfm/` from bayesSYNC, renamed so that it installs independently and tracked inside EmbedSYNC;
4. record the upstream commit it was derived from in `PROGRESS.Rmd`;
5. install both packages and run one example under each, checking that they agree.

**Gate:** `bayesSYNCfm` installs alongside `bayesSYNC` and reproduces it.

## Stage 1: data feasibility

1. download GSE194378 processed data and metadata;
2. reconstruct biological sample metadata;
3. resolve technical controls/replicates;
4. create a subject-by-time availability figure;
5. inspect normalisation and expression scale;
6. prepare a 200–500-gene pilot;
7. run vanilla bayesSYNC;
8. add outputs and figures to `PROGRESS.Rmd`.

**Gate:** vanilla bayesSYNC behaves sensibly.

If this stage takes more than roughly half a day because of dataset-specific problems, switch to the first fallback.

## Stage 2: final gene panel

1. map identifiers;
2. inspect scGPT vocabulary coverage;
3. inspect Reactome coverage;
4. apply the prespecified baseline-only feature rule;
5. freeze the common gene panel;
6. document \(p\) and excluded genes.

**Gate:** one fixed gene list is available for all comparisons.

## Stage 3: FM embeddings and groups

1. create a minimal Python environment;
2. download one frozen scGPT checkpoint;
3. extract static gene-token embeddings once;
4. cache them;
5. build the FM nearest-neighbour graph;
6. cluster genes;
7. inspect group sizes and save diagnostics.

**Gate:** every final-panel gene has a valid FM group.

## Stage 4: curated and random groups

1. obtain Reactome memberships;
2. build curated similarity/groups;
3. inspect group sizes;
4. generate matched random controls;
5. save all group mappings.

**Gate:** all group vectors are aligned to the same gene order.

## Stage 5: grouped bayesSYNC implementation

1. add `prior_groups`;
2. add size-adjusted group hyperparameters;
3. implement grouped variational updates;
4. implement grouped ELBO;
5. expose group posterior inclusion probabilities;
6. avoid unrelated refactoring.

**Gate:** package tests A–F pass.

## Stage 6: first real-data comparison

1. fit vanilla;
2. fit curated-group;
3. fit FM-group;
4. fit a small set of random controls;
5. inspect convergence and factor activity;
6. update `PROGRESS.Rmd`.

**Gate:** every method fits the same full dataset cleanly.

## Stage 7: held-out evaluation

1. create and save the first subject-specific internal-visit mask;
2. fit every model to the same masked data;
3. reconstruct the held-out visits on an exact `time_g` grid;
4. compute paired RMSE/MAE on the original analysis scale;
5. make the first comparison figure;
6. document the result without tuning;
7. add further fixed masks only after the first one works.

**Gate:** one fair out-of-fit comparison is complete.

At this point the minimum project is complete.

## Stage 8: stability

Only if Stage 7 is complete.

1. create 3–5 subject subsamples;
2. refit;
3. match factors;
4. quantify loading/selection stability;
5. make one summary figure.

## Stage 9: optional extensions

Only if they add clear information:

- second held-out time point;
- more matched random controls;
- alternative FM clustering resolution fixed without looking at outcome;
- alternative checkpoint;
- external replication using GSE48018/GSE48023;
- continuous graph-informed prior instead of hard groups.

Do not start these until the minimum project is complete.

---

# 20. Minimum viable deliverable

The project is complete enough to evaluate once it has:

1. a public, reproducible analysis workflow;
2. a grouped-prior extension of bayesSYNC;
3. regression and one-group identity tests;
4. FM, curated and matched-random gene groups;
5. one real-data fit under each main condition;
6. one held-out-time comparison;
7. one interpretable dynamic factor with subject trajectories;
8. a maintained `PROGRESS.Rmd` documenting both positive and negative findings, plus an up-to-date public `README.md`.

A negative or null FM result is acceptable. Do not tune the analysis until the FM model wins.

---

# 21. Main risks and decisions

## Risk: group prior is inadvertently much stronger than the original prior

Mitigation: use size-adjusted group hyperparameters and test the expected sparsity and one-group identity explicitly.

## Risk: five time points are insufficient for the current functional implementation

Mitigation: run vanilla bayesSYNC before changing the package and switch dataset if necessary.

## Risk: clustering choices dominate the comparison

Mitigation: use the same broad graph/community workflow for FM and curated similarities, prespecify choices before outcome evaluation, and include matched random partitions.

## Risk: feature selection leaks held-out information

Mitigation: base panel construction on baseline measurements and external coverage only.

## Risk: pathway evaluation is circular

Mitigation: use held-out time points as the primary evaluation and keep enrichment descriptive.

## Risk: package modification becomes larger than expected

Mitigation: modify only the loading-inclusion prior. Do not change the functional representation, inference architecture or post-processing unless a correctness issue forces it.

## Risk: FM embedding extraction becomes an environment project

Mitigation: use one official scGPT workflow, extract once, cache, then return to R.

---

# 22. Sources

bayesSYNC:
https://github.com/hruffieux/bayesSYNC

scGPT:
https://github.com/bowang-lab/scGPT

scGPT gene-embedding / GRN tutorial:
https://scgpt.readthedocs.io/en/latest/tutorial_grn.html

GSE194378:
https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE194378

GSE48018:
https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE48018

GSE48023:
https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE48023

GSE45735:
https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE45735

The exact mathematical updates of the original model should be checked against the bayesSYNC preprint, supplement and the pinned package code before implementation.
