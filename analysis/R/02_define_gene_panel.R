## Stage 2: freeze the common gene panel.
##
## One ordered gene list is used by every model: vanilla, curated, foundation
## model and the matched random controls. Fixing it once, before any grouping is
## built or any visit is held out, is what makes those comparisons fair.
##
## Genes must be reliably measured, present in the scGPT vocabulary and
## annotated in Reactome. Requiring all three costs little here, because the
## eligible pool is far larger than the panel, and it avoids having to invent an
## `unassigned` curated group.
##
## Selection uses pre-vaccination visits only. Genes are ranked by how much the
## within-subject change from the pre-vaccination visit to day 0 varies across
## subjects. Both visits precede vaccination, so this uses none of the day 1 or
## day 7 measurements that the primary evaluation holds out.
##
## The earlier pilot ranked on between-subject standard deviation at baseline
## instead. That favoured genes with large stable individual differences, and
## the resulting factors mostly encoded which subject a sample came from rather
## than how that subject responded. Ranking on within-subject change puts the
## panel where an external grouping can plausibly help.
##
## Runtime: seconds.
##
## Run with:
##   Rscript analysis/R/02_define_gene_panel.R

source(here::here("analysis", "R", "00_setup.R"))

suppressPackageStartupMessages({
  library(org.Hs.eg.db)
  library(reactome.db)
  library(jsonlite)
})

N_PANEL <- 1000L
MIN_BASELINE_EXPR <- 2          # log2-CPM
PRE_VACCINATION_DAYS <- c(-7, -6)
DAY_ZERO <- 0

## Globin transcripts are excluded, as is standard for whole-blood RNA-seq.
## They are expressed at log2-CPM 8 to 9 here and their abundance varies between
## draws largely through handling and globin-depletion efficiency, so ranking on
## within-subject change places them at the very top: without this exclusion
## they take four of the first six positions and would carry large loadings,
## risking a factor that represents globin content rather than biology.
##
## The exclusion is deliberately narrow. Erythroid genes that are not globins,
## such as ALAS2, SLC4A1 and CA1, are kept, because their variation reflects
## genuine reticulocyte content rather than sample handling. The exclusion is
## applied to the eligible pool before the top genes are taken, so the panel
## still holds exactly N_PANEL genes.
GLOBIN_GENES <- c("HBA1", "HBA2", "HBB", "HBD", "HBG1", "HBG2",
                  "HBM", "HBQ1", "HBZ", "HBE1")

dat <- readRDS(path_data_processed("01_gse194378_longitudinal.rds"))
expr <- dat$expr
samples <- dat$samples
genes <- dat$genes

## 1. Reliably measured --------------------------------------------------------

baseline <- samples$day %in% c(PRE_VACCINATION_DAYS, DAY_ZERO)
baseline_subject_mean <- vapply(
  split(samples$library_id[baseline], samples$subject_id[baseline]),
  function(libs) rowMeans(expr[, libs, drop = FALSE]),
  numeric(nrow(expr))
)
genes$baseline_mean <- rowMeans(baseline_subject_mean)
genes$expressed <- genes$baseline_mean > MIN_BASELINE_EXPR

## 2. scGPT vocabulary ---------------------------------------------------------

## The vocabulary is keyed by gene symbol and was built from a 2023 CellxGene
## release, whereas the symbols here come from a current org.Hs.eg.db. Matching
## on the current symbol alone therefore drops genes purely because the symbol
## has since changed, so unmatched genes are retried against their aliases. The
## symbol that actually matched is kept, since Stage 3 needs it to look the gene
## up in the embedding table.
vocab <- names(jsonlite::fromJSON(path_data_external("scgpt_human_vocab.json")))

genes$scgpt_symbol <- ifelse(!is.na(genes$symbol) & genes$symbol %in% vocab,
                             genes$symbol, NA_character_)

unmatched <- which(is.na(genes$scgpt_symbol) & !is.na(genes$symbol))
aliases <- suppressMessages(AnnotationDbi::mapIds(
  org.Hs.eg.db, keys = genes$entrez_id[unmatched], keytype = "ENTREZID",
  column = "ALIAS", multiVals = "list"
))
genes$scgpt_symbol[unmatched] <- vapply(aliases, function(a) {
  hit <- intersect(a, vocab)
  if (length(hit)) hit[1] else NA_character_
}, character(1))

genes$in_scgpt <- !is.na(genes$scgpt_symbol)

## 3. Reactome membership ------------------------------------------------------

entrez_to_pathway <- as.list(reactomeEXTID2PATHID)
genes$reactome_pathways <- vapply(genes$entrez_id, function(id) {
  p <- entrez_to_pathway[[id]]
  if (is.null(p)) 0L else sum(grepl("^R-HSA-", p))
}, integer(1))
genes$in_reactome <- genes$reactome_pathways > 0L

## 4. Rank on within-subject pre-vaccination change ----------------------------

## For each subject, the change between the pre-vaccination visit and day 0.
## Every subject has both, so no subject is dropped from the ranking.
pre_lib <- vapply(split(samples, samples$subject_id), function(s_i) {
  hit <- s_i$library_id[s_i$day %in% PRE_VACCINATION_DAYS]
  if (length(hit)) hit[1] else NA_character_
}, character(1))
day0_lib <- vapply(split(samples, samples$subject_id), function(s_i) {
  hit <- s_i$library_id[s_i$day == DAY_ZERO]
  if (length(hit)) hit[1] else NA_character_
}, character(1))

usable <- !is.na(pre_lib) & !is.na(day0_lib)
delta <- expr[, day0_lib[usable], drop = FALSE] - expr[, pre_lib[usable], drop = FALSE]
genes$pre_change_sd <- apply(delta, 1, stats::sd)

## Also recorded, not used for ranking: the quantity the pilot ranked on. Kept
## so the two rules can be compared in the report.
genes$between_subject_sd <- apply(baseline_subject_mean, 1, stats::sd)

## Ranking on the raw standard deviation would select partly for noise. On this
## log2-CPM scale the variability of a gene falls steeply with its expression,
## so lowly expressed genes show large apparent change simply because they are
## measured less precisely. Ranking on raw change fills the panel from the low
## end of the expression range.
##
## The genes wanted are those whose within-subject change is large *for their
## expression level*. A trend of log variability on mean expression is fitted
## across the eligible genes, and the ranking uses the residual from it. This is
## the same idea as variance-stabilised feature selection in single-cell
## analysis, and it keeps the criterion pre-vaccination and leakage-free.
trend_pool <- genes$expressed & genes$in_scgpt & genes$in_reactome &
  genes$pre_change_sd > 0
trend_fit <- stats::loess(
  log(pre_change_sd) ~ baseline_mean,
  data = genes[trend_pool, ], span = 0.5, degree = 1
)
genes$expected_log_change_sd <- NA_real_
genes$expected_log_change_sd[trend_pool] <- stats::predict(trend_fit)
genes$change_excess <- log(genes$pre_change_sd) - genes$expected_log_change_sd

## 5. Freeze the panel ---------------------------------------------------------

genes$is_globin <- !is.na(genes$symbol) & genes$symbol %in% GLOBIN_GENES

genes$eligible <- genes$expressed & genes$in_scgpt & genes$in_reactome &
  !genes$is_globin & !is.na(genes$change_excess)
stopifnot(sum(genes$eligible) >= N_PANEL)

eligible_idx <- which(genes$eligible)
ordered_idx <- eligible_idx[order(genes$change_excess[eligible_idx],
                                  decreasing = TRUE)]
panel_idx <- ordered_idx[seq_len(N_PANEL)]

## The panel is stored in a fixed order, so every downstream grouping vector and
## every fit refers to the same genes in the same positions.
panel <- data.frame(
  position = seq_len(N_PANEL),
  row_id = genes$row_id[panel_idx],
  entrez_id = genes$entrez_id[panel_idx],
  symbol = genes$symbol[panel_idx],
  scgpt_symbol = genes$scgpt_symbol[panel_idx],
  reactome_pathways = genes$reactome_pathways[panel_idx],
  baseline_mean = round(genes$baseline_mean[panel_idx], 3),
  pre_change_sd = round(genes$pre_change_sd[panel_idx], 4),
  change_excess = round(genes$change_excess[panel_idx], 4),
  between_subject_sd = round(genes$between_subject_sd[panel_idx], 4),
  stringsAsFactors = FALSE
)
stopifnot(!anyDuplicated(panel$row_id), !anyDuplicated(panel$entrez_id))

utils::write.csv(panel, path_metadata("02_gene_panel.csv"), row.names = FALSE)
saveRDS(panel, path_data_processed("02_gene_panel.rds"))

## 6. Coverage and diagnostics -------------------------------------------------

coverage <- data.frame(
  step = c("Genes in normalised matrix",
           "Mapping to a current symbol",
           "In scGPT vocabulary",
           "  of which matched via an alias",
           "Annotated in Reactome",
           sprintf("Reliably measured (baseline mean > %d)", MIN_BASELINE_EXPR),
           "Globin transcripts excluded",
           "Eligible: measured, scGPT, Reactome, non-globin",
           "Panel"),
  n = c(nrow(genes),
        sum(!is.na(genes$symbol)),
        sum(genes$in_scgpt),
        sum(genes$in_scgpt & genes$symbol != genes$scgpt_symbol, na.rm = TRUE),
        sum(genes$in_reactome),
        sum(genes$expressed),
        sum(genes$is_globin & genes$expressed & genes$in_scgpt & genes$in_reactome),
        sum(genes$eligible),
        nrow(panel)),
  stringsAsFactors = FALSE
)

## Two comparisons worth quantifying rather than asserting: against the rule the
## pilot used, and against ranking on raw change without the expression trend.
pilot_rule_idx <- eligible_idx[order(genes$between_subject_sd[eligible_idx],
                                     decreasing = TRUE)][seq_len(N_PANEL)]
raw_rule_idx <- eligible_idx[order(genes$pre_change_sd[eligible_idx],
                                   decreasing = TRUE)][seq_len(N_PANEL)]

rule_comparison <- data.frame(
  item = c("Shared with the pilot rule (between-subject SD)",
           "Shared with raw within-subject change, no trend correction",
           "Median baseline expression, this panel",
           "Median baseline expression, raw-change panel",
           "Median baseline expression, all eligible genes",
           "Median pathways per panel gene"),
  value = c(length(intersect(panel_idx, pilot_rule_idx)),
            length(intersect(panel_idx, raw_rule_idx)),
            round(stats::median(genes$baseline_mean[panel_idx]), 2),
            round(stats::median(genes$baseline_mean[raw_rule_idx]), 2),
            round(stats::median(genes$baseline_mean[eligible_idx]), 2),
            stats::median(panel$reactome_pathways)),
  stringsAsFactors = FALSE
)

utils::write.csv(coverage, path_metrics("02_coverage.csv"), row.names = FALSE)
utils::write.csv(rule_comparison, path_metrics("02_rule_comparison.csv"),
                 row.names = FALSE)
utils::write.csv(provenance(), path_metrics("00_provenance.csv"),
                 row.names = FALSE)

save_progress_figure("02_panel_selection.png", {
  graphics::par(mfrow = c(1, 2), mar = c(4.5, 4.5, 3, 1))

  sel <- which(genes$eligible)
  ord <- sel[order(genes$baseline_mean[sel])]

  ## Ranking on raw change would take genes from the low-expression end, where
  ## variability is inflated by measurement noise. The fitted trend and the
  ## genes actually selected show why the correction is applied.
  graphics::smoothScatter(
    genes$baseline_mean[sel], genes$pre_change_sd[sel], log = "y",
    xlab = "Baseline mean expression (log2 CPM)",
    ylab = "SD of within-subject change",
    main = "Expression trend in variability"
  )
  graphics::points(genes$baseline_mean[raw_rule_idx],
                   genes$pre_change_sd[raw_rule_idx], pch = 16, cex = 0.2,
                   col = grDevices::adjustcolor("grey35", 0.5))
  graphics::points(panel$baseline_mean, panel$pre_change_sd, pch = 16, cex = 0.2,
                   col = grDevices::adjustcolor("#D95F02", 0.6))
  graphics::lines(genes$baseline_mean[ord],
                  exp(genes$expected_log_change_sd[ord]), lwd = 2, col = "#2C7FB8")
  graphics::legend("bottomleft", bty = "n", cex = 0.75,
                   pch = c(16, 16, NA), lty = c(NA, NA, 1), lwd = c(NA, NA, 2),
                   col = c("grey35", "#D95F02", "#2C7FB8"),
                   legend = c("raw-change panel", "panel (trend corrected)",
                              "fitted trend"))

  graphics::hist(genes$baseline_mean[eligible_idx], breaks = 40, col = "grey88",
                 border = NA, xlab = "Baseline mean expression (log2 CPM)",
                 main = "Where each panel is drawn from")
  graphics::hist(genes$baseline_mean[raw_rule_idx], breaks = 40, add = TRUE,
                 col = grDevices::adjustcolor("grey35", 0.6), border = NA)
  graphics::hist(panel$baseline_mean, breaks = 40, add = TRUE,
                 col = grDevices::adjustcolor("#D95F02", 0.6), border = NA)
  graphics::legend("topright", fill = c("grey88", "grey35", "#D95F02"),
                   border = NA, bty = "n", cex = 0.75,
                   legend = c("all eligible", "raw-change panel", "panel"))
})

print(coverage, row.names = FALSE)
cat("\n"); print(rule_comparison, row.names = FALSE)
cat("\nPanel head:\n"); print(utils::head(panel[, c("position", "symbol",
    "reactome_pathways", "baseline_mean", "pre_change_sd", "change_excess")], 12),
    row.names = FALSE)
