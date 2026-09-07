## Stage 6 summary: compare the full-data fits across conditions.
##
## Reads the cached fits and extracts small summaries, so this can be rerun
## without refitting. The fitted objects are large, so each is loaded, reduced
## and discarded rather than all held at once.
##
## The ELBO comparison here is a model-fit summary, not the primary evaluation.
## It is a lower bound on the log marginal likelihood of each model, and the
## models differ in their prior, so the comparison is legitimate but the bounds
## need not be equally tight. The held-out reconstruction in Stage 7 is what the
## project rests on.
##
## Runtime: a few minutes, mostly reading 13 large files.
##
## Run with:
##   Rscript analysis/R/06b_compare_fits.R

source(here::here("analysis", "R", "00_setup.R"))

conditions <- c("vanilla", "curated", "fm",
                sprintf("random_fm_%d", 1:5),
                sprintf("random_curated_%d", 1:5))

extract <- function(name) {
  f <- readRDS(path_fits(sprintf("06_%s.rds", name)))
  out <- list(
    condition = name,
    elbo = f$ELBO_iter,
    iterations = f$i_iter,
    runtime_mins = f$runtime_mins,
    active_factors = sum(f$factor_ppi > 0.5),
    selected_per_factor = colSums(f$ppi > 0.5),
    selected_any = sum(apply(f$ppi, 1, max) > 0.5),
    group_prob = f$group_inclusion_prob
  )
  rm(f); gc(verbose = FALSE)
  out
}

fits <- lapply(conditions, extract)
names(fits) <- conditions

## 1. Comparison table ----------------------------------------------------------

arm <- function(name) {
  if (name == "vanilla") "vanilla"
  else if (name %in% c("fm", "curated")) "informed"
  else "random"
}

comparison <- do.call(rbind, lapply(fits, function(x) data.frame(
  condition = x$condition,
  arm = arm(x$condition),
  elbo = round(x$elbo, 1),
  iterations = x$iterations,
  runtime_mins = round(x$runtime_mins, 1),
  active_factors = x$active_factors,
  selected_any = x$selected_any,
  stringsAsFactors = FALSE
)))
rownames(comparison) <- NULL
comparison <- comparison[order(-comparison$elbo), ]

## 2. Informed against its own matched null ------------------------------------

## Each informed grouping is compared with the mean of the five random
## partitions that share its group sizes. That difference isolates the effect of
## what the grouping says from the effect of grouping at all.
elbo_of <- vapply(fits, function(x) x$elbo, numeric(1))
null_gap <- do.call(rbind, lapply(c("fm", "curated"), function(g) {
  nulls <- elbo_of[sprintf("random_%s_%d", g, 1:5)]
  data.frame(
    grouping = g,
    elbo_informed = round(elbo_of[[g]], 1),
    elbo_random_mean = round(mean(nulls), 1),
    elbo_random_sd = round(stats::sd(nulls), 1),
    gain_over_matched_random = round(elbo_of[[g]] - mean(nulls), 1),
    gap_to_vanilla = round(elbo_of[[g]] - elbo_of[["vanilla"]], 1),
    stringsAsFactors = FALSE
  )
}))

utils::write.csv(comparison, path_metrics("06_condition_comparison.csv"),
                 row.names = FALSE)
utils::write.csv(null_gap, path_metrics("06_informed_vs_random.csv"),
                 row.names = FALSE)

## 3. Figure --------------------------------------------------------------------

save_progress_figure("06_full_data_comparison.png", {
  graphics::par(mfrow = c(1, 3), mar = c(8, 4.5, 3, 1))

  cols <- c(vanilla = "grey35", informed = "#D95F02", random = "#2C7FB8")
  ord <- order(-comparison$elbo)
  graphics::barplot(
    comparison$elbo[ord] - min(comparison$elbo) + 1,
    names.arg = comparison$condition[ord], las = 2, cex.names = 0.65,
    col = cols[comparison$arm[ord]], border = NA,
    ylab = "ELBO above the lowest fit",
    main = "Model fit by condition"
  )
  graphics::legend("topright", fill = cols, border = NA, bty = "n", cex = 0.8,
                   legend = names(cols))

  ## Selection per factor, to show how dense the loadings are.
  sel <- vapply(fits[c("vanilla", "curated", "fm")],
                function(x) x$selected_per_factor[1:3], numeric(3))
  graphics::barplot(sel, beside = TRUE, col = c("#2C7FB8", "#7FBC41", "#D95F02"),
                    border = NA, las = 2, ylab = "Genes with PPI > 0.5",
                    main = "Selection per active factor")
  graphics::legend("topright", fill = c("#2C7FB8", "#7FBC41", "#D95F02"),
                   border = NA, bty = "n", cex = 0.8,
                   legend = paste("Factor", 1:3))

  ## Whether the grouped prior differentiates groups at all.
  gp_fm <- fits$fm$group_prob[, 1:3]
  gp_cur <- fits$curated$group_prob[, 1:3]
  graphics::boxplot(list(`FM F1` = gp_fm[, 1], `FM F2` = gp_fm[, 2],
                         `FM F3` = gp_fm[, 3], `Cur F1` = gp_cur[, 1],
                         `Cur F2` = gp_cur[, 2], `Cur F3` = gp_cur[, 3]),
                    col = c(rep("#D95F02", 3), rep("#7FBC41", 3)),
                    las = 2, ylab = expression(E(pi[kq] * "|" * Y)),
                    main = "Group inclusion probabilities")
}, width = 13, height = 5)

print(comparison, row.names = FALSE)
cat("\nInformed groupings against their matched nulls:\n")
print(null_gap, row.names = FALSE)
