## Stage 7e: does the prior have leverage in a sparser regime?
##
## Stage 7d found the informed groupings changing the selection call for 14
## genes out of 1,000. One explanation is the regime rather than the grouping:
## each active factor loads on half to three-quarters of the panel, and where
## the likelihood is that decisive a prior on inclusion has little room.
##
## This is a diagnostic of the regime, not a second run of the comparison. The
## configuration is changed after seeing the Stage 7 result, so nothing here can
## be reported as a headline; it exists to say whether the null result depends
## on the sparsity setting.
##
## Two parts. First an analytic sizing, which needs no fitting: each gene's
## inclusion log-odds splits into a data term and a prior term, so the data
## terms can be recovered from the cached vanilla fit and the selection under
## any other prior strength predicted directly. Second, three refits at the
## chosen strength: vanilla, the foundation-model grouping, and one matched
## random partition, so that the grouping can be compared against both.
##
## Everything else is held at the Stage 7 settings: same mask, same panel, same
## Q, L, K, grid, scaling, annealing, tolerances and seed.
##
## Runtime: about 55 minutes for the three fits. The sizing is instant.
##
## Run with:
##   Rscript analysis/R/07e_sparsity_diagnostic.R

source(here::here("analysis", "R", "00_setup.R"))

Q_FIT <- 5L
L_FIT <- 2L
K_FIT <- 5L
N_CPUS <- max(1L, parallel::detectCores() - 2L)

## Multiples of the default d_0 = p to evaluate analytically, and the one to
## refit at. A thousandfold is the point where predicted selection changes
## substantially while the model still selects a good part of the panel.
D0_MULTIPLIERS <- c(1, 10, 100, 1000, 1e4, 1e5)
D0_REFIT <- 1000

CONDITIONS <- c("vanilla", "fm", "random_fm_1")

dat <- readRDS(path_data_processed("01_gse194378_longitudinal.rds"))
panel <- readRDS(path_data_processed("02_gene_panel.rds"))
masks <- readRDS(path_masks("07_holdout_masks.rds"))

expr <- dat$expr
samples <- dat$samples
subjects <- sort(unique(samples$subject_id))
mask_r <- masks[masks$replicate == 1, ]

p <- nrow(panel)

## 1. Analytic sizing -------------------------------------------------------------

## Gene j's inclusion log-odds is a data term plus the prior term
## E[log omega_q] - E[log(1 - omega_q)]. The prior term is known, so subtracting
## it from the fitted log-odds recovers the data term, and the selection under a
## different prior strength follows by holding those data terms fixed. The rate
## and the inclusions depend on each other, so the prediction is iterated to its
## fixed point.
##
## Holding the data terms fixed ignores the factors and loadings reorganising
## under a different prior, so this sizes the experiment rather than replacing
## it. The refits below test the prediction.
dense <- readRDS(path_fits("07_r1_vanilla.rds"))
active <- which(dense$factor_ppi > 0.5)
ppi_dense <- dense$ppi[, active, drop = FALSE]

c_0 <- 1
d_0 <- p
total <- c_0 + d_0 + p
c_1 <- dense$omega_hat[active] * total
d_1 <- (1 - dense$omega_hat[active]) * total
prior_lo <- digamma(c_1) - digamma(d_1)

clamp <- function(x) pmin(pmax(x, 1e-12), 1 - 1e-12)
data_lo <- sweep(stats::qlogis(clamp(ppi_dense)), 2, prior_lo, "-")

predict_selection <- function(d_0_new) {
  vapply(seq_along(active), function(q) {
    s <- sum(ppi_dense[, q])
    lo <- prior_lo[q]
    for (i in 1:200) {
      lo <- digamma(c_0 + s) - digamma(d_0_new + p - s)
      s_new <- sum(stats::plogis(data_lo[, q] + lo))
      if (abs(s_new - s) < 1e-8) break
      s <- s_new
    }
    mean(stats::plogis(data_lo[, q] + lo) > 0.5)
  }, numeric(1))
}

leverage <- do.call(rbind, lapply(D0_MULTIPLIERS, function(mult) {
  sel <- predict_selection(d_0 * mult)
  data.frame(
    d0_multiplier = mult,
    prior_log_odds = round(digamma(c_0 + mean(colSums(ppi_dense))) -
                             digamma(d_0 * mult + p - mean(colSums(ppi_dense))), 2),
    predicted_selection_1 = round(sel[1], 3),
    predicted_selection_2 = round(sel[2], 3),
    predicted_selection_3 = round(sel[3], 3),
    stringsAsFactors = FALSE
  )
}))

data_lo_quantiles <- data.frame(
  quantile = c("10%", "25%", "50%", "75%", "90%"),
  data_log_odds = round(stats::quantile(data_lo, c(0.1, 0.25, 0.5, 0.75, 0.9)), 2),
  stringsAsFactors = FALSE
)

utils::write.csv(leverage, path_metrics("07e_prior_leverage.csv"), row.names = FALSE)
utils::write.csv(data_lo_quantiles, path_metrics("07e_data_log_odds.csv"), row.names = FALSE)

cat("\nPredicted selection under stronger priors:\n")
print(leverage, row.names = FALSE)

## 2. Refits ------------------------------------------------------------------------

## Mirrors 07b_fit_masked.R. The input construction is repeated rather than
## shared, so that the script which produced the Stage 7 results is left as it
## was when it produced them.
time_g <- sort(unique(c(seq(0, 1, length.out = 400), day_to_time(c(1, 7)))))

retained <- samples[!samples$library_id %in% mask_r$library_id, ]
time_obs <- vector("list", length(subjects))
Y <- vector("list", length(subjects))
names(time_obs) <- names(Y) <- subjects

for (i in seq_along(subjects)) {
  rows <- retained[retained$subject_id == subjects[i], ]
  rows <- rows[order(rows$day), ]
  time_obs[[i]] <- day_to_time(rows$day)
  sub_expr <- expr[panel$row_id, rows$library_id, drop = FALSE]
  Y[[i]] <- lapply(seq_len(nrow(sub_expr)), function(j) as.numeric(sub_expr[j, ]))
  names(Y[[i]]) <- panel$row_id
}
stopifnot(nrow(retained) == nrow(samples) - nrow(mask_r))

fm <- readRDS(path_groups("03_fm_groups.rds"))
random <- readRDS(path_groups("05_random_groups.rds"))
stopifnot(identical(fm$row_id, panel$row_id))

as_prior_groups <- function(labels) stats::setNames(as.character(labels), panel$row_id)

random_1 <- random[random$family == "fm" & random$replicate == 1, ]
random_1 <- random_1[match(panel$row_id, random_1$row_id), ]
stopifnot(identical(random_1$row_id, panel$row_id))

conditions <- list(
  vanilla = NULL,
  fm = as_prior_groups(fm$group),
  random_fm_1 = as_prior_groups(random_1$group)
)

hyper <- bayesSYNCfm::set_hyper(d_0 = D0_REFIT * p)

extract_holdout <- function(fit) {
  grid_index <- match(mask_r$time, fit$time_g)
  subject_index <- match(mask_r$subject_id, names(fit$Y))
  stopifnot(!anyNA(grid_index), !anyNA(subject_index))

  slice <- function(component) {
    out <- vapply(seq_len(nrow(mask_r)), function(m) {
      vapply(fit[[component]][[subject_index[m]]],
             function(y) y[grid_index[m]], numeric(1))
    }, numeric(length(fit$Y[[1]])))
    dimnames(out) <- list(panel$row_id, mask_r$subject_id)
    out
  }

  list(hat = slice("list_Y_hat"), low = slice("list_Y_low"), upp = slice("list_Y_upp"),
       gene_mean = fit$mean_mean_across_subjects,
       gene_sd = fit$sd_mean_across_subjects)
}

for (name in names(conditions)) {
  fit_file <- path_fits(sprintf("07e_%s.rds", name))
  if (file.exists(fit_file)) {
    message(sprintf("[%s] cached, skipping", name))
    next
  }
  message(sprintf("[%s] fitting at %s", name, format(Sys.time(), "%H:%M:%S")))
  t0 <- Sys.time()
  fit <- bayesSYNCfm::bayesSYNC(
    time_obs = time_obs, Y = Y,
    L = L_FIT, Q = Q_FIT, K = K_FIT,
    time_g = time_g, n_g = NULL,
    list_hyper = hyper,
    seed = SEEDS$fit,
    bool_scale = TRUE,
    bool_var_spec_prob = FALSE,
    prior_groups = conditions[[name]],
    n_cpus = N_CPUS,
    verbose = FALSE
  )
  fit$runtime_mins <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  fit$condition <- name
  fit$holdout <- extract_holdout(fit)
  fit[c("list_Y_hat", "list_Y_low", "list_Y_upp")] <- NULL
  saveRDS(fit, fit_file)
  message(sprintf("[%s] done in %.1f min, ELBO %.1f, %d iterations",
                  name, fit$runtime_mins, fit$ELBO_iter, fit$i_iter))
}

## 3. Compare the two regimes ---------------------------------------------------------

sparse <- lapply(CONDITIONS, function(cond) {
  file <- path_fits(sprintf("07e_%s.rds", cond))
  if (file.exists(file)) readRDS(file) else NULL
})
names(sparse) <- CONDITIONS
if (any(vapply(sparse, is.null, logical(1)))) {
  stop("Not all sparse-regime fits are present.")
}

dense_fits <- lapply(CONDITIONS, function(cond) {
  readRDS(path_fits(sprintf("07_r1_%s.rds", cond)))
})
names(dense_fits) <- CONDITIONS

## Factor matching, as in 07d: labels and signs are arbitrary.
permutations <- function(n) {
  if (n == 1L) return(matrix(1L))
  sub <- permutations(n - 1L)
  do.call(rbind, lapply(seq_len(n), function(i) {
    cbind(i, matrix(ifelse(sub >= i, sub + 1L, sub), nrow = nrow(sub)))
  }))
}

active_of <- function(f) which(f$factor_ppi > 0.5)

## Whether a gene is selected anywhere does not depend on how factors are
## labelled or on how many are active, so it is comparable between two fits in
## any case. The loading and inclusion comparisons need matched factors, and
## the sparser prior can prune a different number of them, so those are
## returned as missing when the counts differ rather than forced.
agreement_with <- function(a, b) {
  ia <- active_of(a); ib <- active_of(b)

  any_a <- apply(a$ppi[, ia, drop = FALSE], 1, max) > 0.5
  any_b <- apply(b$ppi[, ib, drop = FALSE], 1, max) > 0.5
  out <- list(loading_cor = NA_real_, mean_abs_ppi_diff = NA_real_,
              genes_flipped = sum(any_a != any_b))

  if (length(ia) != length(ib)) return(out)

  cross <- stats::cor(a$B_hat[, ia, drop = FALSE], b$B_hat[, ib, drop = FALSE])
  perms <- permutations(length(ia))
  best <- perms[which.max(apply(perms, 1, function(pm) {
    sum(abs(cross[cbind(seq_along(ia), pm)]))
  })), ]

  out$loading_cor <- mean(abs(cross[cbind(seq_along(ia), best)]))
  out$mean_abs_ppi_diff <- mean(abs(a$ppi[, ia, drop = FALSE] -
                                      b$ppi[, ib[best], drop = FALSE]))
  out
}

regime_summary <- do.call(rbind, lapply(CONDITIONS, function(cond) {
  do.call(rbind, lapply(c("dense", "sparse"), function(regime) {
    f <- if (regime == "dense") dense_fits[[cond]] else sparse[[cond]]
    act <- active_of(f)
    v <- if (regime == "dense") dense_fits$vanilla else sparse$vanilla

    ag <- if (cond == "vanilla") NULL else agreement_with(v, f)

    data.frame(
      regime = regime,
      condition = cond,
      d0_multiplier = if (regime == "dense") 1 else D0_REFIT,
      elbo = round(f$ELBO_iter, 1),
      iterations = f$i_iter,
      active_factors = length(act),
      selection_per_factor = round(mean(colMeans(f$ppi[, act, drop = FALSE] > 0.5)), 3),
      genes_selected = sum(apply(f$ppi, 1, max) > 0.5),
      mean_abs_ppi_diff_vs_vanilla = if (is.null(ag)) NA_real_ else round(ag$mean_abs_ppi_diff, 5),
      genes_flipped_vs_vanilla = if (is.null(ag)) NA_integer_ else ag$genes_flipped,
      stringsAsFactors = FALSE
    )
  }))
}))

## Held-out error in the sparse regime, scored exactly as at Stage 7c.
observed <- expr[panel$row_id, mask_r$library_id, drop = FALSE]
colnames(observed) <- mask_r$subject_id

holdout_error <- do.call(rbind, lapply(CONDITIONS, function(cond) {
  do.call(rbind, lapply(c("dense", "sparse"), function(regime) {
    f <- if (regime == "dense") dense_fits[[cond]] else sparse[[cond]]
    h <- f$holdout
    predicted <- h$hat * h$gene_sd + h$gene_mean
    residual <- predicted - observed
    data.frame(
      regime = regime, condition = cond,
      mean_rmse = round(mean(sqrt(colMeans(residual^2))), 4),
      stringsAsFactors = FALSE
    )
  }))
}))

## Group differentiation in each regime, as at Stage 7d.
group_spread <- do.call(rbind, lapply(setdiff(CONDITIONS, "vanilla"), function(cond) {
  do.call(rbind, lapply(c("dense", "sparse"), function(regime) {
    f <- if (regime == "dense") dense_fits[[cond]] else sparse[[cond]]
    probs <- f$group_inclusion_prob[, active_of(f), drop = FALSE]
    ## The two regimes put the group probabilities on completely different
    ## scales, around 0.28 against around 0.0004, so an absolute spread cannot
    ## be compared between them. The coefficient of variation can, and it is
    ## what decides how much the grouping separates one group from another.
    data.frame(
      regime = regime, condition = cond,
      mean_prob = signif(mean(probs), 3),
      sd_across_groups = signif(mean(apply(probs, 2, stats::sd)), 3),
      range_across_groups = signif(mean(apply(probs, 2, function(x) diff(range(x)))), 3),
      cv_across_groups = round(mean(apply(probs, 2, function(x) {
        stats::sd(x) / mean(x)
      })), 3),
      stringsAsFactors = FALSE
    )
  }))
}))

utils::write.csv(regime_summary, path_metrics("07e_regime_summary.csv"), row.names = FALSE)
utils::write.csv(holdout_error, path_metrics("07e_holdout_error.csv"), row.names = FALSE)
utils::write.csv(group_spread, path_metrics("07e_group_spread.csv"), row.names = FALSE)
utils::write.csv(provenance(), path_metrics("00_provenance.csv"), row.names = FALSE)

save_progress_figure("07e_sparsity.png", {
  graphics::layout(matrix(c(1, 2, 3, 4), nrow = 2, byrow = TRUE))
  graphics::par(mar = c(4.5, 4.5, 3.5, 1))

  ## Why the regime is what it is: the likelihood evidence per gene against the
  ## range of prior strengths on offer.
  graphics::hist(data_lo, breaks = 60, col = "grey75", border = NA,
                 xlab = "Inclusion log-odds from the data",
                 main = "Likelihood evidence per gene and factor")
  graphics::abline(v = 0, lty = 2, col = "grey30")
  for (i in seq_len(nrow(leverage))) {
    graphics::abline(v = -leverage$prior_log_odds[i], col = "#D95F02", lty = 3)
  }
  graphics::legend("topright", bty = "n", cex = 0.8, lty = c(2, 3),
                   col = c("grey30", "#D95F02"),
                   legend = c("no evidence", "prior strengths tried"))

  ## Predicted against achieved selection.
  graphics::plot(leverage$d0_multiplier, leverage$predicted_selection_1, log = "x",
                 type = "b", pch = 16, col = "grey40", ylim = c(0, 0.8),
                 xlab = expression(d[0] ~ "as a multiple of" ~ p),
                 ylab = "Selection on the first factor",
                 main = "Predicted, and what refitting gave")
  graphics::lines(leverage$d0_multiplier, leverage$predicted_selection_3,
                  type = "b", pch = 16, col = "grey70")
  achieved <- regime_summary[regime_summary$condition == "vanilla", ]
  graphics::points(achieved$d0_multiplier, achieved$selection_per_factor,
                   pch = 18, cex = 2, col = "#D95F02")
  graphics::legend("topright", bty = "n", cex = 0.8, pch = c(16, 18),
                   col = c("grey40", "#D95F02"),
                   legend = c("predicted", "vanilla refit, mean over factors"))

  ## Does the grouping gain leverage?
  as_regime_matrix <- function(column) {
    d <- regime_summary[regime_summary$condition != "vanilla", ]
    out <- matrix(NA_real_, nrow = 2, ncol = 2,
                  dimnames = list(c("dense", "sparse"), c("fm", "random_fm_1")))
    out[cbind(d$regime, d$condition)] <- d[[column]]
    out
  }

  mat <- as_regime_matrix("genes_flipped_vs_vanilla")
  graphics::barplot(mat, beside = TRUE, border = NA,
                    col = c("grey70", "#2C7FB8"),
                    ylab = "Genes changing selection against vanilla",
                    main = "Leverage of the grouping",
                    legend.text = c("dense prior", "sparse prior"),
                    args.legend = list(bty = "n", cex = 0.8, border = NA))

  ## Group differentiation in each regime.
  mat2 <- matrix(NA_real_, nrow = 2, ncol = 2,
                 dimnames = list(c("dense", "sparse"), c("fm", "random_fm_1")))
  mat2[cbind(group_spread$regime, group_spread$condition)] <-
    group_spread$cv_across_groups
  graphics::barplot(mat2, beside = TRUE, border = NA,
                    col = c("grey70", "#2C7FB8"),
                    ylab = "Group probability, coefficient of variation",
                    main = "Group differentiation",
                    legend.text = c("dense prior", "sparse prior"),
                    args.legend = list(bty = "n", cex = 0.8, border = NA))
}, width = 11, height = 8.5)

cat("\nRegime comparison:\n"); print(regime_summary, row.names = FALSE)
cat("\nHeld-out error:\n"); print(holdout_error, row.names = FALSE)
cat("\nGroup differentiation:\n"); print(group_spread, row.names = FALSE)
