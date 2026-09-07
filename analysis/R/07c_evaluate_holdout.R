## Stage 7c: held-out reconstruction error.
##
## Compares each condition against the observations that were hidden from it.
## For every subject the whole 1,000-gene expression vector at one internal
## post-vaccination visit was removed before fitting; here the fitted
## trajectory is read at that time, returned to the original analysis scale and
## compared with what was actually measured.
##
## Errors are summarised per subject first, so that each subject contributes
## one number to the comparison and the conditions can be compared in pairs on
## the same subjects. Pooling genes and subjects into one number would be
## dominated by whichever genes happen to be most variable.
##
## A reference predictor is included: each subject's own mean across its
## retained visits, gene by gene. It uses no model and no held-out value, and it
## says whether the fitted trajectories are worth anything at all at this time
## point.
##
## Runtime: a few minutes, dominated by reading the cached fits.
##
## Run with:
##   Rscript analysis/R/07c_evaluate_holdout.R

source(here::here("analysis", "R", "00_setup.R"))

REPLICATES <- 1L

dat <- readRDS(path_data_processed("01_gse194378_longitudinal.rds"))
panel <- readRDS(path_data_processed("02_gene_panel.rds"))
masks <- readRDS(path_masks("07_holdout_masks.rds"))

expr <- dat$expr
samples <- dat$samples

CONDITIONS <- c("vanilla", "curated", "fm",
                sprintf("random_fm_%d", 1:5),
                sprintf("random_curated_%d", 1:5))

ARM <- c(vanilla = "vanilla", curated = "informed", fm = "informed",
         subject_mean = "reference")
arm_of <- function(condition) {
  ifelse(condition %in% names(ARM), ARM[condition], "random")
}

## 1. Observed held-out data -----------------------------------------------------

#' Held-out expression, genes by subjects, on the original analysis scale.
observed_holdout <- function(mask_r) {
  out <- expr[panel$row_id, mask_r$library_id, drop = FALSE]
  colnames(out) <- mask_r$subject_id
  out
}

#' Reference prediction: each subject's mean over its retained visits.
#'
#' Uses only observations the models were also given, so it is a fair floor
#' rather than an oracle.
subject_mean_reference <- function(mask_r) {
  retained <- samples[!samples$library_id %in% mask_r$library_id, ]
  out <- vapply(mask_r$subject_id, function(s) {
    libs <- retained$library_id[retained$subject_id == s]
    rowMeans(expr[panel$row_id, libs, drop = FALSE])
  }, numeric(nrow(panel)))
  dimnames(out) <- list(panel$row_id, mask_r$subject_id)
  out
}

## 2. Errors --------------------------------------------------------------------

#' Per-subject error summaries for one genes-by-subjects prediction matrix.
#'
#' Two error columns are reported. `rmse` is the pre-specified primary metric:
#' the prediction against the observation, as they stand. `rmse_offset` grants
#' the prediction each subject's own per-gene level, measured on the retained
#' visits alone, and so measures the temporal shape without the subject offset
#' the model does not parameterise. See `subject_offset()` for why that
#' distinction matters here.
#'
#' @param predicted,observed Matrices with matching dimnames.
#' @param mask_r One replicate of the held-out mask.
#' @param label Condition name.
#' @param covered Optional logical matrix, whether each held-out value fell
#'   inside its 95% credible band.
#' @param offset Optional genes-by-subjects matrix of per-gene subject offsets.
#' @return One row per subject.
subject_errors <- function(predicted, observed, mask_r, label, covered = NULL,
                           offset = NULL) {
  stopifnot(identical(dimnames(predicted), dimnames(observed)))

  residual <- predicted - observed
  residual_offset <- if (is.null(offset)) residual else predicted + offset - observed

  data.frame(
    replicate = mask_r$replicate,
    condition = label,
    arm = arm_of(label),
    subject_id = mask_r$subject_id,
    study_group = mask_r$study_group,
    day = mask_r$day,
    rmse = sqrt(colMeans(residual^2)),
    mae = colMeans(abs(residual)),
    bias = colMeans(residual),
    rmse_offset = sqrt(colMeans(residual_offset^2)),
    coverage = if (is.null(covered)) NA_real_ else colMeans(covered),
    stringsAsFactors = FALSE
  )
}

#' Reconstruct a fit's trajectories at chosen grid points.
#'
#' 07b_fit_masked.R drops the reconstructed trajectories, which are almost the
#' whole of a fitted object's size, but keeps the pieces they are built from.
#' For subject i, gene j and grid point g the reconstruction is
#' \eqn{\mu_j(g) + \sum_q B_{jq} h_{iq}(g)}, which reproduces the dropped
#' `list_Y_hat` exactly. Values are on the fitting scale.
#'
#' @param fit A cached masked fit.
#' @param subject Subject identifier.
#' @param grid_index Indices into `fit$time_g`.
#' @return Genes-by-times matrix.
predict_at <- function(fit, subject, grid_index) {
  i <- match(subject, names(fit$Y))
  stopifnot(!is.na(i))

  mu <- do.call(rbind, lapply(fit$list_mu_hat, function(m) m[grid_index]))
  h <- do.call(cbind, lapply(fit$list_h_hat[[i]], function(hq) hq[grid_index]))
  mu + fit$B_hat %*% t(h)
}

#' Per-gene subject offset: what the model misses about each subject's level.
#'
#' The model gives each subject only Q factor loadings on top of a population
#' mean curve, so it cannot represent a per-gene subject intercept. Between
#' subjects, per-gene variation is about twice the within-subject temporal
#' variation on these data, so that missing intercept dominates the raw error
#' and compresses the differences between conditions, which is what the project
#' is actually asking about.
#'
#' The offset is the difference, on the retained visits only, between what the
#' subject actually shows and what the model predicts for it. It uses no
#' held-out value, and it is computed the same way for every condition.
#'
#' @param fit A cached masked fit.
#' @param mask_r One replicate of the held-out mask.
#' @param unscale Function returning predictions to the original scale.
#' @return Genes-by-subjects matrix.
subject_offset <- function(fit, mask_r, unscale) {
  retained <- samples[!samples$library_id %in% mask_r$library_id, ]

  out <- vapply(mask_r$subject_id, function(s) {
    rows <- retained[retained$subject_id == s, ]
    ## Retained visits need not sit on the grid: day 0 and day 28 do not. The
    ## nearest grid point is within half a spacing, under 0.05 days here.
    grid_index <- vapply(day_to_time(rows$day),
                         function(t) which.min(abs(fit$time_g - t)), integer(1))
    stopifnot(max(abs(fit$time_g[grid_index] - day_to_time(rows$day))) <
                diff(range(fit$time_g)) / length(fit$time_g))

    observed <- rowMeans(expr[panel$row_id, rows$library_id, drop = FALSE])
    predicted <- rowMeans(unscale(predict_at(fit, s, grid_index)))
    observed - predicted
  }, numeric(nrow(panel)))

  dimnames(out) <- list(panel$row_id, mask_r$subject_id)
  out
}

#' Read one cached masked fit and score it.
#'
#' Predictions are stored on the fitting scale, so they are returned to the
#' original scale here, next to the observed values. The scaling is per gene:
#' the model centred each gene by the mean across subjects of the subject means
#' and divided by their standard deviation.
score_condition <- function(condition, r, observed, mask_r) {
  fit_file <- path_fits(sprintf("07_r%d_%s.rds", r, condition))
  if (!file.exists(fit_file)) {
    message(sprintf("[r%d %s] not fitted yet, skipping", r, condition))
    return(NULL)
  }

  fit <- readRDS(fit_file)
  h <- fit$holdout
  stopifnot(identical(rownames(h$hat), panel$row_id),
            identical(colnames(h$hat), mask_r$subject_id))

  unscale <- function(m) m * h$gene_sd + h$gene_mean

  predicted <- unscale(h$hat)
  covered <- observed >= unscale(h$low) & observed <= unscale(h$upp)

  subject_errors(predicted, observed, mask_r, condition, covered,
                 offset = subject_offset(fit, mask_r, unscale))
}

errors <- do.call(rbind, lapply(REPLICATES, function(r) {
  mask_r <- masks[masks$replicate == r, ]
  observed <- observed_holdout(mask_r)

  scored <- lapply(CONDITIONS, score_condition, r = r,
                   observed = observed, mask_r = mask_r)
  reference <- subject_errors(subject_mean_reference(mask_r), observed,
                              mask_r, "subject_mean")

  do.call(rbind, c(scored, list(reference)))
}))

if (is.null(errors)) {
  stop("No masked fits found. Run analysis/R/07b_fit_masked.R first.")
}
rownames(errors) <- NULL

## 3. Summaries -----------------------------------------------------------------

condition_summary <- do.call(rbind, lapply(
  split(errors, list(errors$replicate, errors$condition), drop = TRUE),
  function(d) {
    data.frame(
      replicate = d$replicate[1],
      condition = d$condition[1],
      arm = d$arm[1],
      mean_rmse = round(mean(d$rmse), 4),
      median_rmse = round(stats::median(d$rmse), 4),
      mean_mae = round(mean(d$mae), 4),
      rmse_day_1 = round(mean(d$rmse[d$day == 1]), 4),
      rmse_day_7 = round(mean(d$rmse[d$day == 7]), 4),
      ## For the reference predictor this equals mean_rmse: it already predicts
      ## the subject's own level, so there is no offset to add.
      mean_rmse_offset = round(mean(d$rmse_offset), 4),
      mean_coverage = round(mean(d$coverage), 4),
      stringsAsFactors = FALSE
    )
  }))
condition_summary <- condition_summary[order(condition_summary$replicate,
                                             condition_summary$mean_rmse), ]
rownames(condition_summary) <- NULL

## 4. Paired comparisons ---------------------------------------------------------

## Every condition saw the same subjects and the same held-out visits, so the
## comparisons are paired within subject. The differences are reported with a
## paired Wilcoxon signed-rank test; per-subject RMSEs are right-skewed, and the
## test makes no normality assumption. These are unadjusted p-values for a small
## set of pre-specified comparisons, and they describe this one mask.
paired_difference <- function(errors_r, condition, against, label,
                              metric = "rmse") {
  a <- errors_r[errors_r$condition == condition, ]
  if (nrow(a) == 0L) return(NULL)

  b <- errors_r[errors_r$condition %in% against, ]
  if (nrow(b) == 0L) return(NULL)

  ## Matched random families are averaged within subject before differencing,
  ## so the comparison is against the typical null rather than a single draw.
  b_mean <- vapply(split(b[[metric]], b$subject_id), mean, numeric(1))
  b_mean <- b_mean[a$subject_id]

  diff <- a[[metric]] - b_mean
  test <- stats::wilcox.test(a[[metric]], b_mean, paired = TRUE)

  data.frame(
    replicate = a$replicate[1],
    metric = metric,
    comparison = label,
    mean_error = round(mean(a[[metric]]), 4),
    mean_reference_error = round(mean(b_mean), 4),
    mean_difference = round(mean(diff), 4),
    subjects_better = sum(diff < 0),
    subjects = length(diff),
    p_value = signif(unname(test$p.value), 3),
    stringsAsFactors = FALSE
  )
}

paired <- do.call(rbind, lapply(REPLICATES, function(r) {
  e <- errors[errors$replicate == r, ]
  do.call(rbind, lapply(c("rmse", "rmse_offset"), function(metric) {
    do.call(rbind, list(
      paired_difference(e, "fm", "vanilla", "FM vs vanilla", metric),
      paired_difference(e, "curated", "vanilla", "Curated vs vanilla", metric),
      paired_difference(e, "fm", sprintf("random_fm_%d", 1:5),
                        "FM vs matched random", metric),
      paired_difference(e, "curated", sprintf("random_curated_%d", 1:5),
                        "Curated vs matched random", metric),
      paired_difference(e, "vanilla", "subject_mean",
                        "Vanilla vs subject mean", metric)
    ))
  }))
}))

## 5. Save ----------------------------------------------------------------------

utils::write.csv(errors, path_metrics("07_holdout_subject_errors.csv"),
                 row.names = FALSE)
utils::write.csv(condition_summary, path_metrics("07_holdout_summary.csv"),
                 row.names = FALSE)
utils::write.csv(paired, path_metrics("07_holdout_paired.csv"), row.names = FALSE)
utils::write.csv(provenance(), path_metrics("00_provenance.csv"), row.names = FALSE)

save_progress_figure("07_holdout_comparison.png", {
  e <- errors[errors$replicate == REPLICATES[1], ]
  arm_colour <- c(vanilla = "#D95F02", informed = "#2C7FB8",
                  random = "grey70", reference = "grey40")

  ## The lower panels compare the informed groupings against vanilla, so they
  ## are drawn only once those fits exist. Running the script part way through
  ## a fitting run then gives the first panel rather than an error.
  informed_ready <- all(c("vanilla", "fm", "curated") %in% e$condition)

  graphics::layout(matrix(c(1, 1, 2, 3), nrow = 2, byrow = TRUE))
  graphics::par(mar = c(7.5, 4.5, 3, 1))

  ord <- names(sort(vapply(split(e$rmse, e$condition), mean, numeric(1))))
  e$condition <- factor(e$condition, levels = ord)
  ## Scale to the whiskers, not to the raw range: a few subjects are an order
  ## of magnitude worse than the rest and would flatten every box. The top of
  ## the range leaves headroom for the legend.
  whiskers <- function(x) range(vapply(split(x[[1]], x[[2]]), function(v) {
    grDevices::boxplot.stats(v)$stats[c(1, 5)]
  }, numeric(2)))

  span <- whiskers(list(e$rmse, e$condition))
  graphics::boxplot(rmse ~ condition, data = e, las = 2, xlab = "",
                    ylab = "Per-subject RMSE", outline = FALSE,
                    ylim = c(span[1], span[2] + diff(span) * 0.18),
                    col = arm_colour[vapply(split(e$arm, e$condition), function(a) a[1],
                                            character(1))],
                    border = "grey30",
                    main = "Held-out reconstruction error by condition")
  graphics::legend("top", bty = "n", cex = 0.8, horiz = TRUE, fill = arm_colour,
                   legend = names(arm_colour), border = NA)

  if (informed_ready) {
    graphics::par(mar = c(4.5, 4.5, 3, 1))

    ## Paired differences against vanilla, subject by subject.
    van <- e$rmse[e$condition == "vanilla"]
    names(van) <- e$subject_id[e$condition == "vanilla"]
    diffs <- lapply(c(fm = "fm", curated = "curated"), function(cond) {
      d <- e[e$condition == cond, ]
      d$rmse - van[d$subject_id]
    })
    diff_span <- range(vapply(diffs, function(v) {
      grDevices::boxplot.stats(v)$stats[c(1, 5)]
    }, numeric(2)))
    graphics::boxplot(diffs, ylab = "RMSE difference from vanilla",
                      col = "#2C7FB8", border = "grey30", outline = FALSE,
                      ylim = diff_span,
                      main = "Paired difference, by subject")
    graphics::abline(h = 0, lty = 2, col = "grey40")

    ## Error by held-out day, for the three conditions of interest.
    main3 <- e[e$condition %in% c("vanilla", "fm", "curated"), ]
    main3$key <- paste(main3$condition, main3$day, sep = "\nday ")
    graphics::boxplot(rmse ~ key, data = main3, las = 2, xlab = "",
                      ylab = "Per-subject RMSE", outline = FALSE,
                      col = arm_colour[main3$arm[match(levels(factor(main3$key)),
                                                       main3$key)]],
                      border = "grey30", cex.axis = 0.8,
                      main = "Error by held-out day")
  }
}, width = 11, height = 9)

cat("\n"); print(condition_summary, row.names = FALSE)
cat("\nPaired comparisons:\n"); print(paired, row.names = FALSE)
