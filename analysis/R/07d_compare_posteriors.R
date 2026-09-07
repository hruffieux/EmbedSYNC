## Stage 7d: what the priors actually did to the posterior.
##
## Stage 7 found no difference between conditions in held-out reconstruction,
## while both fitting runs found the informed groupings fitting the observed
## data better than their size-matched random partitions. This script asks four
## questions of the fits already cached, and refits nothing:
##
## 1. how far apart the posteriors are at all, condition against vanilla;
## 2. where the in-sample ELBO advantage sits, prior terms or data fit;
## 3. whether informed groupings differentiate their groups more than random
##    partitions of the same sizes do;
## 4. how much each condition's programmes move when the data change, using the
##    full-data and masked fits as the two ends of one perturbation.
##
## The fourth is the Stage 8 question asked with the fits in hand. Removing one
## visit per subject is a weaker and differently shaped perturbation than
## dropping subjects, so it can justify the subject-subsampling run but not
## replace it.
##
## Runtime: about ten minutes, almost all of it reading the Stage 6 fits, which
## are 755 MB each and are read one at a time.
##
## Run with:
##   Rscript analysis/R/07d_compare_posteriors.R

source(here::here("analysis", "R", "00_setup.R"))

CONDITIONS <- c("vanilla", "curated", "fm",
                sprintf("random_fm_%d", 1:5),
                sprintf("random_curated_%d", 1:5))

INFORMED <- c(fm = "fm", curated = "curated")

ARM <- c(vanilla = "vanilla", curated = "informed", fm = "informed")
arm_of <- function(condition) {
  ifelse(condition %in% names(ARM), ARM[condition], "random")
}

## Family a condition belongs to, for pairing an informed grouping with its own
## matched nulls.
family_of <- function(condition) {
  ifelse(condition %in% c("fm", "curated"), condition,
         sub("^random_(.*)_[0-9]+$", "\\1", condition))
}

## 1. Compact fit summaries -----------------------------------------------------

#' Read a fit and keep only what these comparisons need.
#'
#' The Stage 6 objects are 755 MB, so each is dropped before the next is read.
load_compact <- function(file) {
  if (!file.exists(file)) return(NULL)
  fit <- readRDS(file)
  out <- list(
    B = fit$B_hat,
    ppi = fit$ppi,
    factor_ppi = fit$factor_ppi,
    elbo = fit$ELBO_iter,
    omega = fit$omega_hat,
    group_prob = fit$group_inclusion_prob,
    group_hyper = fit$group_prior_hyperparameters,
    groups = fit$prior_groups
  )
  rm(fit)
  gc(verbose = FALSE)
  out
}

masked <- lapply(CONDITIONS, function(cond) {
  load_compact(path_fits(sprintf("07_r1_%s.rds", cond)))
})
names(masked) <- CONDITIONS
stopifnot(!any(vapply(masked, is.null, logical(1))))

active_factors <- function(f) which(f$factor_ppi > 0.5)
stopifnot(all(vapply(masked, function(f) length(active_factors(f)), integer(1)) == 3L))

p <- nrow(masked$vanilla$ppi)

## 2. Factor matching -----------------------------------------------------------

## Factor labels and signs are arbitrary, so any comparison of loadings between
## two fits has to match factors first. With three active factors there are six
## permutations, so the best one is found exhaustively rather than greedily.
permutations <- function(n) {
  if (n == 1L) return(matrix(1L))
  sub <- permutations(n - 1L)
  do.call(rbind, lapply(seq_len(n), function(i) {
    cbind(i, matrix(ifelse(sub >= i, sub + 1L, sub), nrow = nrow(sub)))
  }))
}

#' Match the active factors of two fits.
#'
#' @return List with the permutation applied to `b` and the sign flips.
match_factors <- function(a, b) {
  ia <- active_factors(a)
  ib <- active_factors(b)
  stopifnot(length(ia) == length(ib))

  cross <- stats::cor(a$B[, ia, drop = FALSE], b$B[, ib, drop = FALSE])
  perms <- permutations(length(ia))
  score <- apply(perms, 1, function(pm) sum(abs(cross[cbind(seq_along(ia), pm)])))
  best <- perms[which.max(score), ]

  list(a_cols = ia,
       b_cols = ib[best],
       signs = sign(cross[cbind(seq_along(ia), best)]),
       cors = cross[cbind(seq_along(ia), best)])
}

#' How far apart two posteriors are, after matching factors.
posterior_agreement <- function(a, b, label_a, label_b) {
  m <- match_factors(a, b)

  ppi_a <- a$ppi[, m$a_cols, drop = FALSE]
  ppi_b <- b$ppi[, m$b_cols, drop = FALSE]

  ## Selection on a factor, and selection anywhere, at the usual 0.5 threshold.
  jaccard <- vapply(seq_along(m$a_cols), function(q) {
    sa <- ppi_a[, q] > 0.5
    sb <- ppi_b[, q] > 0.5
    if (!any(sa | sb)) return(NA_real_)
    sum(sa & sb) / sum(sa | sb)
  }, numeric(1))

  any_a <- apply(ppi_a, 1, max) > 0.5
  any_b <- apply(ppi_b, 1, max) > 0.5

  data.frame(
    reference = label_a,
    condition = label_b,
    arm = arm_of(label_b),
    loading_cor = round(mean(abs(m$cors)), 5),
    ppi_cor = round(mean(vapply(seq_along(m$a_cols), function(q) {
      stats::cor(ppi_a[, q], ppi_b[, q])
    }, numeric(1))), 5),
    mean_abs_ppi_diff = round(mean(abs(ppi_a - ppi_b)), 5),
    max_abs_ppi_diff = round(max(abs(ppi_a - ppi_b)), 5),
    jaccard = round(mean(jaccard, na.rm = TRUE), 5),
    genes_flipped = sum(any_a != any_b),
    stringsAsFactors = FALSE
  )
}

## Question 1: how far each condition's posterior is from vanilla's.
agreement <- do.call(rbind, lapply(setdiff(CONDITIONS, "vanilla"), function(cond) {
  posterior_agreement(masked$vanilla, masked[[cond]], "vanilla", cond)
}))

## 3. Where the ELBO advantage sits ---------------------------------------------

## The inclusion prior enters the ELBO through two terms: what each variable
## contributes given its group's expected log inclusion probability, and the
## Beta term for the group probabilities themselves. Both are recoverable from
## the cached posterior, since annealing has finished by convergence and the
## inverse temperature is one there. The recovery is checked below against the
## returned probabilities before any of it is used.
##
## c_0 and d_0 are read off a grouped fit rather than assumed: the size
## adjustment sets a_k = (n_k/p) c_0 and b_k = (n_k/p) d_0, and the rho_k sum to
## one, so the a_k sum to c_0 and the b_k sum to d_0.
c_0 <- sum(masked$fm$group_hyper$a)
d_0 <- sum(masked$fm$group_hyper$b)

beta_parameters <- function(f) {
  if (is.null(f$groups)) {
    list(a = rep(c_0, ncol(f$ppi)), b = rep(d_0, ncol(f$ppi)),
         sums = colSums(f$ppi), n = rep(nrow(f$ppi), ncol(f$ppi)),
         index = rep(1L, nrow(f$ppi)))
  } else {
    labels <- f$group_hyper$group
    index <- match(f$groups, labels)
    indicator <- stats::model.matrix(~ 0 + factor(index, levels = seq_along(labels)))
    list(a = f$group_hyper$a, b = f$group_hyper$b,
         sums = crossprod(indicator, f$ppi),
         n = f$group_hyper$n_variables,
         index = index)
  }
}

#' Contribution of the inclusion prior to the ELBO.
#'
#' Returns the two terms that involve the inclusion probabilities, and the
#' entropy of the inclusion indicators, which is the remaining part of the
#' same ELBO block that is recoverable from what is cached.
#'
#' The Beta parameters are rebuilt from the returned probabilities rather than
#' from the inclusion sums. Their total does not depend on those sums, since
#' \eqn{c_1 + d_1 = a_k + b_k + n_k}, so multiplying the returned probability by
#' that total recovers the internal parameters exactly. Rebuilding from the sums
#' instead is very slightly off, because the probabilities are updated before
#' the inclusion indicators within a sweep and the two are therefore one
#' iteration apart at convergence. That lag is returned as a diagnostic.
inclusion_terms <- function(f) {
  bp <- beta_parameters(f)
  Q <- ncol(f$ppi)

  stored <- if (is.null(f$groups)) matrix(f$omega, ncol = Q) else f$group_prob
  total <- if (is.null(f$groups)) {
    matrix(bp$a + bp$b + bp$n, ncol = Q)
  } else {
    matrix(rep(bp$a + bp$b + bp$n, Q), ncol = Q)
  }

  c_1 <- stored * total
  d_1 <- (1 - stored) * total

  ## Test D of Stage 5, repeated on the returned quantities: rebuilding the same
  ## parameters from the inclusion sums must agree to within the one-iteration
  ## lag described above. The lag is measured in inclusion counts rather than on
  ## the probability scale, because a fixed fraction of a gene is a large shift
  ## inside a 16-gene group and a negligible one inside the whole panel.
  from_sums <- if (is.null(f$groups)) {
    matrix(bp$a + bp$sums, ncol = Q)
  } else {
    sweep(bp$sums, 1, bp$a, "+")
  }
  lag <- max(abs(from_sums - c_1))
  stopifnot(lag < 2)

  e_log <- digamma(c_1) - digamma(c_1 + d_1)
  e_log_1m <- digamma(d_1) - digamma(c_1 + d_1)

  expand <- function(m) if (is.null(f$groups)) {
    matrix(rep(m, each = nrow(f$ppi)), ncol = Q)
  } else {
    m[bp$index, , drop = FALSE]
  }

  eps <- .Machine$double.eps
  data.frame(
    inclusion_term = sum(f$ppi * expand(e_log) + (1 - f$ppi) * expand(e_log_1m)),
    beta_term = sum((bp$a - c_1) * e_log + (bp$b - d_1) * e_log_1m +
                      lbeta(c_1, d_1) - lbeta(bp$a, bp$b)),
    gamma_entropy = -sum(f$ppi * log(f$ppi + eps) +
                           (1 - f$ppi) * log(1 - f$ppi + eps)),
    update_lag = lag,
    stringsAsFactors = FALSE
  )
}

elbo_parts <- do.call(rbind, lapply(CONDITIONS, function(cond) {
  parts <- inclusion_terms(masked[[cond]])
  data.frame(condition = cond, arm = arm_of(cond), family = family_of(cond),
             elbo = masked[[cond]]$elbo, parts,
             stringsAsFactors = FALSE)
}))
elbo_parts$prior_total <- elbo_parts$inclusion_term + elbo_parts$beta_term
elbo_parts$remainder <- elbo_parts$elbo - elbo_parts$prior_total -
  elbo_parts$gamma_entropy

## Gap between each informed grouping and the mean of its own matched nulls,
## for the total and for each recoverable part.
elbo_gap <- do.call(rbind, lapply(names(INFORMED), function(fam) {
  informed <- elbo_parts[elbo_parts$condition == fam, ]
  nulls <- elbo_parts[elbo_parts$arm == "random" & elbo_parts$family == fam, ]
  data.frame(
    grouping = fam,
    total_elbo_gain = round(informed$elbo - mean(nulls$elbo), 1),
    inclusion_term_gain = round(informed$inclusion_term - mean(nulls$inclusion_term), 1),
    beta_term_gain = round(informed$beta_term - mean(nulls$beta_term), 1),
    prior_total_gain = round(informed$prior_total - mean(nulls$prior_total), 1),
    entropy_gain = round(informed$gamma_entropy - mean(nulls$gamma_entropy), 1),
    remainder_gain = round(informed$remainder - mean(nulls$remainder), 1),
    stringsAsFactors = FALSE
  )
}))

## 4. Group differentiation ------------------------------------------------------

## If a grouping carries structure the data support, the inferred group
## probabilities should differ from one group to the next. A random partition of
## the same sizes should smear that out, since each of its groups holds a
## roughly representative mixture of genes.
group_spread <- do.call(rbind, lapply(setdiff(CONDITIONS, "vanilla"), function(cond) {
  f <- masked[[cond]]
  probs <- f$group_prob[, active_factors(f), drop = FALSE]
  data.frame(
    condition = cond,
    arm = arm_of(cond),
    family = family_of(cond),
    n_groups = nrow(probs),
    mean_prob = round(mean(probs), 4),
    sd_across_groups = round(mean(apply(probs, 2, stats::sd)), 5),
    range_across_groups = round(mean(apply(probs, 2, function(x) diff(range(x)))), 4),
    stringsAsFactors = FALSE
  )
}))

## 5. Stability across the two fitting runs --------------------------------------

## Each condition was fitted twice on the same subjects with the same seed: once
## on all 363 observations, once on the 290 that survive the mask. Comparing a
## condition's two fits measures how much its programmes move when the data
## change, and the five matched random partitions give that measure a null.
full_data_agreement <- do.call(rbind, lapply(CONDITIONS, function(cond) {
  full <- load_compact(path_fits(sprintf("06_%s.rds", cond)))
  if (is.null(full)) return(NULL)
  message(sprintf("[%s] comparing full-data and masked fits", cond))
  out <- posterior_agreement(full, masked[[cond]], "full_data", cond)
  out$family <- family_of(cond)
  rm(full)
  gc(verbose = FALSE)
  out
}))

stability_gap <- do.call(rbind, lapply(names(INFORMED), function(fam) {
  informed <- full_data_agreement[full_data_agreement$condition == fam, ]
  nulls <- full_data_agreement[full_data_agreement$arm == "random" &
                                 full_data_agreement$family == fam, ]
  if (nrow(informed) == 0L || nrow(nulls) == 0L) return(NULL)
  data.frame(
    grouping = fam,
    informed_loading_cor = informed$loading_cor,
    random_mean = round(mean(nulls$loading_cor), 5),
    random_sd = round(stats::sd(nulls$loading_cor), 5),
    nulls_below_informed = sum(nulls$loading_cor < informed$loading_cor),
    nulls = nrow(nulls),
    informed_jaccard = informed$jaccard,
    random_jaccard_mean = round(mean(nulls$jaccard), 5),
    stringsAsFactors = FALSE
  )
}))

## 6. Save ------------------------------------------------------------------------

utils::write.csv(agreement, path_metrics("07d_posterior_agreement.csv"), row.names = FALSE)
utils::write.csv(elbo_parts, path_metrics("07d_elbo_parts.csv"), row.names = FALSE)
utils::write.csv(elbo_gap, path_metrics("07d_elbo_decomposition.csv"), row.names = FALSE)
utils::write.csv(group_spread, path_metrics("07d_group_spread.csv"), row.names = FALSE)
utils::write.csv(full_data_agreement, path_metrics("07d_stability.csv"), row.names = FALSE)
utils::write.csv(stability_gap, path_metrics("07d_stability_gap.csv"), row.names = FALSE)
utils::write.csv(provenance(), path_metrics("00_provenance.csv"), row.names = FALSE)

arm_colour <- c(vanilla = "#D95F02", informed = "#2C7FB8", random = "grey70")

## Figure 1: how far the posteriors are from vanilla's ---------------------------

save_progress_figure("07d_posterior_agreement.png", {
  graphics::layout(matrix(c(1, 2, 3, 3), nrow = 2, byrow = TRUE))
  graphics::par(mar = c(4.5, 4.5, 3.5, 1))

  ord <- order(agreement$mean_abs_ppi_diff)
  a <- agreement[ord, ]

  graphics::barplot(a$mean_abs_ppi_diff, names.arg = a$condition, las = 2,
                    col = arm_colour[a$arm], border = NA, cex.names = 0.65,
                    ylab = "Mean |PPI difference| from vanilla",
                    main = "How far each posterior moves from vanilla")
  graphics::legend("topleft", bty = "n", cex = 0.8, fill = arm_colour,
                   legend = names(arm_colour), border = NA)

  graphics::barplot(a$genes_flipped, names.arg = a$condition, las = 2,
                    col = arm_colour[a$arm], border = NA, cex.names = 0.65,
                    ylab = "Genes", main = sprintf("Genes changing selection (of %d)", p))

  ## The per-gene picture for the foundation-model grouping, which is the
  ## condition with the largest in-sample advantage over its nulls.
  m <- match_factors(masked$vanilla, masked$fm)
  graphics::par(mar = c(4.5, 4.5, 3.5, 1))
  graphics::plot(masked$vanilla$ppi[, m$a_cols[1]], masked$fm$ppi[, m$b_cols[1]],
                 pch = 16, cex = 0.4, col = grDevices::adjustcolor("#2C7FB8", 0.4),
                 xlab = "Vanilla posterior inclusion probability",
                 ylab = "Foundation-model grouping",
                 main = "Per-gene inclusion, first matched factor")
  graphics::abline(0, 1, col = "grey40", lty = 2)
}, width = 11, height = 8.5)

## Figure 2: where the ELBO gain sits --------------------------------------------

save_progress_figure("07d_elbo_decomposition.png", {
  graphics::par(mfrow = c(1, 2), mar = c(8, 4.5, 3.5, 1))

  for (fam in names(INFORMED)) {
    g <- elbo_gap[elbo_gap$grouping == fam, ]
    bars <- c(`Total ELBO` = g$total_elbo_gain,
              `Inclusion term` = g$inclusion_term_gain,
              `Beta term` = g$beta_term_gain,
              `Indicator entropy` = g$entropy_gain,
              `Everything else` = g$remainder_gain)
    graphics::barplot(bars, las = 2, border = NA, cex.names = 0.8,
                      col = c("#2C7FB8", rep("grey60", 4)),
                      ylab = "Gain over matched random partitions (ELBO units)",
                      main = sprintf("%s grouping", fam))
    graphics::abline(h = 0, col = "grey40")
  }
}, width = 10, height = 5.5)

## Figure 3: group differentiation ------------------------------------------------

## Sorting each factor's group probabilities and averaging the sorted profiles
## across the active factors gives a curve that does not depend on how factors
## or groups happen to be labelled. A flat curve means the grouping tells the
## model nothing: every group ends up with the same inclusion rate. A steep one
## means the partition separates genes that load from genes that do not.
sorted_profile <- function(f) {
  probs <- f$group_prob[, active_factors(f), drop = FALSE]
  rowMeans(apply(probs, 2, sort))
}

save_progress_figure("07d_group_probabilities.png", {
  graphics::par(mfrow = c(1, 2), mar = c(4.5, 4.5, 3.5, 1))

  for (fam in names(INFORMED)) {
    nulls <- sprintf("random_%s_%d", fam, 1:5)
    nulls <- nulls[nulls %in% names(masked)]
    informed_profile <- sorted_profile(masked[[fam]])

    graphics::plot(seq_along(informed_profile), informed_profile, type = "n",
                   ylim = c(0, max(informed_profile) * 1.05),
                   xlab = "Group, ordered by inclusion probability",
                   ylab = "Group inclusion probability",
                   main = sprintf("%s grouping against its nulls", fam))
    for (cond in nulls) {
      graphics::lines(sorted_profile(masked[[cond]]), col = arm_colour["random"], lwd = 2)
    }
    graphics::lines(informed_profile, col = arm_colour["informed"], lwd = 3)
    graphics::points(seq_along(informed_profile), informed_profile,
                     pch = 16, col = arm_colour["informed"], cex = 0.7)
    graphics::legend("topleft", bty = "n", cex = 0.85, lwd = c(3, 2),
                     col = c(arm_colour["informed"], arm_colour["random"]),
                     legend = c(fam, "matched random"))
  }
}, width = 11, height = 5)

## Figure 4: stability across the two fitting runs ---------------------------------

save_progress_figure("07d_stability.png", {
  graphics::par(mfrow = c(1, 2), mar = c(4.5, 5, 3.5, 1))

  for (metric in c("loading_cor", "jaccard")) {
    label <- if (metric == "loading_cor") {
      "Loading correlation, full data against masked"
    } else {
      "Jaccard overlap of selected genes"
    }

    at <- seq_along(names(INFORMED))
    graphics::plot(NA, xlim = c(0.5, length(at) + 0.5),
                   ylim = range(full_data_agreement[[metric]], na.rm = TRUE),
                   xaxt = "n", xlab = "", ylab = label,
                   main = if (metric == "loading_cor") "Programme stability" else
                     "Selection stability")
    graphics::axis(1, at = at, labels = names(INFORMED))

    for (i in seq_along(names(INFORMED))) {
      fam <- names(INFORMED)[i]
      nulls <- full_data_agreement[full_data_agreement$arm == "random" &
                                     full_data_agreement$family == fam, ]
      informed <- full_data_agreement[full_data_agreement$condition == fam, ]
      graphics::points(rep(i, nrow(nulls)) + stats::runif(nrow(nulls), -0.08, 0.08),
                       nulls[[metric]], pch = 16, col = arm_colour["random"])
      graphics::points(i, informed[[metric]], pch = 18, cex = 2,
                       col = arm_colour["informed"])
    }

    van <- full_data_agreement[full_data_agreement$condition == "vanilla", ]
    graphics::abline(h = van[[metric]], lty = 2, col = arm_colour["vanilla"])
    graphics::legend("bottomright", bty = "n", cex = 0.8,
                     pch = c(18, 16, NA), lty = c(NA, NA, 2), pt.cex = c(1.6, 1, NA),
                     col = c(arm_colour["informed"], arm_colour["random"],
                             arm_colour["vanilla"]),
                     legend = c("Informed", "Matched random", "Vanilla"))
  }
}, width = 10, height = 5)

cat("\nPosterior agreement with vanilla:\n")
print(agreement[, c("condition", "arm", "loading_cor", "ppi_cor",
                    "mean_abs_ppi_diff", "jaccard", "genes_flipped")],
      row.names = FALSE)
cat("\nELBO decomposition, gain over matched random:\n")
print(elbo_gap, row.names = FALSE)
cat("\nGroup differentiation:\n"); print(group_spread, row.names = FALSE)
cat("\nStability across the two runs:\n"); print(stability_gap, row.names = FALSE)
