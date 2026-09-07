## Stage 7f: does an external grouping explain the model's own selection?
##
## Stage 7d found the informed groupings differentiating their groups far more
## than size-matched random partitions do. That was measured on fits which used
## the grouping, and a grouped prior induces group structure in the inclusion
## probabilities by construction, so part of the effect could be the prior
## seeing its own reflection.
##
## The clean test uses the vanilla posterior, which never saw any grouping. If a
## partition explains variation in vanilla's per-gene inclusion probabilities
## better than partitions of the same group sizes do, then the external
## information is related to which genes this dataset recruits, and nothing in
## the measurement depends on the grouped prior at all.
##
## The statistic is the proportion of variance in the inclusion probabilities
## explained by group membership, averaged over the active factors. The null
## permutes gene labels, which preserves the group sizes exactly, exactly as the
## matched random partitions of Stage 4 do, but with enough draws to give a
## p-value rather than a rank among five.
##
## Runtime: under a minute.
##
## Run with:
##   Rscript analysis/R/07f_grouping_signal.R

source(here::here("analysis", "R", "00_setup.R"))

N_PERMUTATIONS <- 10000L

panel <- readRDS(path_data_processed("02_gene_panel.rds"))
fm <- readRDS(path_groups("03_fm_groups.rds"))
curated <- readRDS(path_groups("04_curated_groups.rds"))
stopifnot(identical(fm$row_id, panel$row_id), identical(curated$row_id, panel$row_id))

GROUPINGS <- list(fm = fm$group, curated = curated$group)

## Both vanilla fits are used: the full-data one and the masked one. They are
## different data, so agreement between them is a replication rather than a
## repetition.
FITS <- c(full_data = "06_vanilla.rds", masked = "07_r1_vanilla.rds")

#' Variance in a vector explained by group membership.
#'
#' The usual one-way \eqn{\eta^2}: between-group sum of squares over total sum
#' of squares. It is bounded in [0, 1] and does not depend on how groups are
#' labelled or ordered.
eta_squared <- function(values, groups) {
  grand <- mean(values)
  group_means <- tapply(values, groups, mean)
  group_sizes <- tapply(values, groups, length)
  sum(group_sizes * (group_means - grand)^2) / sum((values - grand)^2)
}

#' Mean explained variance across a fit's active factors.
grouping_statistic <- function(ppi, groups) {
  mean(apply(ppi, 2, eta_squared, groups = groups))
}

results <- do.call(rbind, lapply(names(FITS), function(fit_label) {
  fit <- readRDS(path_fits(FITS[[fit_label]]))
  ppi <- fit$ppi[, fit$factor_ppi > 0.5, drop = FALSE]
  stopifnot(identical(rownames(ppi), panel$row_id))
  rm(fit)
  gc(verbose = FALSE)

  do.call(rbind, lapply(names(GROUPINGS), function(name) {
    groups <- GROUPINGS[[name]]
    observed <- grouping_statistic(ppi, groups)

    ## Permuting the labels preserves the multiset of group sizes, so the null
    ## holds the shape of the partition fixed and varies only its content.
    set.seed(SEEDS$random_groups)
    null <- replicate(N_PERMUTATIONS,
                      grouping_statistic(ppi, sample(as.character(groups))))

    data.frame(
      fit = fit_label,
      grouping = name,
      active_factors = ncol(ppi),
      eta_squared = round(observed, 5),
      null_mean = round(mean(null), 5),
      null_sd = round(stats::sd(null), 5),
      z = round((observed - mean(null)) / stats::sd(null), 1),
      ## One-sided: the question is whether the grouping explains more than
      ## chance, not whether it differs from chance.
      p_value = (1 + sum(null >= observed)) / (1 + length(null)),
      permutations = N_PERMUTATIONS,
      stringsAsFactors = FALSE
    )
  }))
}))

utils::write.csv(results, path_metrics("07f_grouping_signal.csv"), row.names = FALSE)
utils::write.csv(provenance(), path_metrics("00_provenance.csv"), row.names = FALSE)

## The null distributions, redrawn for the figure on the masked fit alone.
fit <- readRDS(path_fits("07_r1_vanilla.rds"))
ppi <- fit$ppi[, fit$factor_ppi > 0.5, drop = FALSE]
rm(fit); gc(verbose = FALSE)

save_progress_figure("07f_grouping_signal.png", {
  graphics::par(mfrow = c(1, 2), mar = c(4.5, 4.5, 3.5, 1))

  for (name in names(GROUPINGS)) {
    groups <- GROUPINGS[[name]]
    observed <- grouping_statistic(ppi, groups)
    set.seed(SEEDS$random_groups)
    null <- replicate(N_PERMUTATIONS,
                      grouping_statistic(ppi, sample(as.character(groups))))

    graphics::hist(null, breaks = 60, col = "grey75", border = NA,
                   xlim = range(c(null, observed)) * c(0.9, 1.05),
                   xlab = "Variance in inclusion explained by the grouping",
                   main = sprintf("%s grouping", name))
    graphics::abline(v = observed, col = "#2C7FB8", lwd = 3)
    graphics::legend("topright", bty = "n", cex = 0.85, lwd = c(3, 6),
                     col = c("#2C7FB8", "grey75"),
                     legend = c("observed", "size-matched permutations"))
  }
}, width = 10, height = 4.5)

cat("\n"); print(results, row.names = FALSE)
