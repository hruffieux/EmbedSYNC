## Stage 1 gate: fit vanilla bayesSYNC to a small pilot panel from GSE194378.
##
## The question is whether the model behaves sensibly on this design before any
## methodological change: whether it converges, whether the sparsity prior keeps
## a reasonable number of factors active, and whether the reconstructed
## trajectories are plausible. It is not a scientific result.
##
## The design is demanding for a functional model. Each subject has at most five
## visits, four of them inside the first week and the last around day 28, so the
## temporal basis has to interpolate a three-week gap from very few points. That
## is the main thing this pilot is checking.
##
## Gene selection uses baseline visits only, so nothing here depends on the
## post-vaccination measurements that the primary evaluation will hold out.
##
## Run with:
##   Rscript analysis/R/01b_pilot_vanilla_fit.R

source(here::here("analysis", "R", "00_setup.R"))

N_PILOT_GENES <- 300L
BASELINE_DAYS <- c(-7, -6, 0)   # pre-vaccination visits
MIN_BASELINE_EXPR <- 2          # log2-CPM, above the low-expression shoulder

Q_PILOT <- 4L

## Configurations for the temporal basis. K sets the number of O'Sullivan
## spline functions, whose interior knots are placed at quantiles of the pooled
## observation times. The design has only ten distinct days and no observation
## at all between day 7 and day 26, so the basis has to be checked rather than
## taken from the package default of K = 10. The candidates below are compared
## on fit and on how much structure they invent across the unobserved gap.
##
## L = 1 is not included. It fails in bayesSYNC, and in the unmodified package
## on its own simulated data, so this is a package limitation rather than
## anything to do with these data: in bayesSYNC_core, `setdiff(1:L, l)` is empty
## when L = 1, so the enclosing `rowSums(sapply(...))` receives an empty list
## and errors. L = 2 is therefore the smallest usable number of FPCA components.
BASIS_GRID <- data.frame(K = c(4L, 5L, 7L), L = c(2L, 2L, 2L))

## Days spanned by the gap, used for the diagnostic below.
GAP_DAYS <- c(8, 25)

dat <- readRDS(path_data_processed("01_gse194378_longitudinal.rds"))
expr <- dat$expr
samples <- dat$samples
genes <- dat$genes

## 1. Pilot gene panel ---------------------------------------------------------

## Both the filter and the ranking use pre-vaccination visits only. Subject
## means are taken first, so a subject with two baseline visits does not
## contribute twice as much to the ranking as one with a single baseline visit.
baseline <- samples$day %in% BASELINE_DAYS
stopifnot(any(baseline))

baseline_subject_mean <- vapply(
  split(samples$library_id[baseline], samples$subject_id[baseline]),
  function(libs) rowMeans(expr[, libs, drop = FALSE]),
  numeric(nrow(expr))
)

expressed <- rowMeans(baseline_subject_mean) > MIN_BASELINE_EXPR
between_subject_sd <- apply(baseline_subject_mean, 1, stats::sd)

## Rank the expressed genes by how much they vary between subjects at baseline.
## This favours genes carrying real between-person signal without looking at any
## post-vaccination measurement.
rank_score <- ifelse(expressed, between_subject_sd, -Inf)
pilot_genes <- rownames(expr)[order(rank_score, decreasing = TRUE)][seq_len(N_PILOT_GENES)]
pilot_symbols <- genes$symbol[match(pilot_genes, genes$row_id)]

## 2. bayesSYNC input format ---------------------------------------------------

## Y[[i]][[j]] holds subject i's gene j across that subject's visit times, and
## time_obs[[i]] holds those times on the normalised [0, 1] scale.
subjects <- sort(unique(samples$subject_id))

time_obs <- vector("list", length(subjects))
Y <- vector("list", length(subjects))
names(time_obs) <- names(Y) <- subjects

for (i in seq_along(subjects)) {
  rows <- samples[samples$subject_id == subjects[i], ]
  rows <- rows[order(rows$day), ]
  time_obs[[i]] <- day_to_time(rows$day)
  sub_expr <- expr[pilot_genes, rows$library_id, drop = FALSE]
  Y[[i]] <- lapply(seq_len(nrow(sub_expr)), function(j) as.numeric(sub_expr[j, ]))
  names(Y[[i]]) <- pilot_genes
}

stopifnot(all(vapply(time_obs, function(t) all(t >= 0 & t <= 1), logical(1))))

## The dense grid is built to contain the candidate held-out days exactly, so
## that the same extraction used in the primary evaluation is exercised here.
time_g <- sort(unique(c(seq(0, 1, length.out = 400), day_to_time(c(1, 7)))))
stopifnot(all(day_to_time(c(1, 7)) %in% time_g))

## 3. Fit each basis configuration ---------------------------------------------

fit_one <- function(K, L) {
  fit_file <- path_fits(sprintf("01b_pilot_vanilla_K%d_L%d.rds", K, L))
  if (file.exists(fit_file)) return(readRDS(fit_file))

  t0 <- Sys.time()
  fit <- bayesSYNC::bayesSYNC(
    time_obs = time_obs, Y = Y,
    L = L, Q = Q_PILOT, K = K,
    time_g = time_g, n_g = NULL,
    seed = SEEDS$fit,
    bool_scale = TRUE,
    bool_var_spec_prob = FALSE,
    n_cpus = max(1L, parallel::detectCores() - 1L),
    verbose = FALSE
  )
  fit$runtime_mins <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  saveRDS(fit, fit_file)
  fit
}

fits <- Map(fit_one, BASIS_GRID$K, BASIS_GRID$L)
names(fits) <- sprintf("K%d_L%d", BASIS_GRID$K, BASIS_GRID$L)

## 4. Diagnostics --------------------------------------------------------------

#' How much structure a fit invents across the unobserved gap.
#'
#' For every subject and every selected gene, the reconstruction range across
#' days 8 to 25, where there are no observations, is compared with its range
#' over the observed part of the study. A ratio near 1 means the smoother
#' interpolates the gap without adding excursions; a large ratio means the
#' trajectory is dominated by unconstrained behaviour where there are no data.
#'
#' The upper tail is reported alongside the median because the two answer
#' different questions. The median describes the typical curve, but a basis can
#' behave well for most subject-gene pairs while producing large excursions for
#' a minority, and it is the minority that makes a fitted trajectory misleading.
#'
#' @param fit A bayesSYNC fit.
#' @return A named vector with the median and 95th percentile of the ratio.
gap_amplitude_ratio <- function(fit) {
  days_g <- time_to_day(fit$time_g)
  in_gap <- days_g >= GAP_DAYS[1] & days_g <= GAP_DAYS[2]
  observed <- !in_gap

  selected <- rownames(fit$ppi)[apply(fit$ppi, 1, max) > 0.5]
  if (length(selected) == 0L) return(c(median = NA_real_, q95 = NA_real_))
  selected <- selected[seq_len(min(50L, length(selected)))]

  ratios <- unlist(lapply(fit$list_Y_hat, function(y_i) {
    vapply(selected, function(g) {
      y <- y_i[[g]]
      obs_range <- diff(range(y[observed]))
      if (obs_range <= 0) return(NA_real_)
      diff(range(y[in_gap])) / obs_range
    }, numeric(1))
  }))
  c(median = stats::median(ratios, na.rm = TRUE),
    q95 = unname(stats::quantile(ratios, 0.95, na.rm = TRUE)))
}

gap <- vapply(fits, gap_amplitude_ratio, numeric(2))

basis_comparison <- data.frame(
  K = BASIS_GRID$K,
  L = BASIS_GRID$L,
  iterations = vapply(fits, `[[`, numeric(1), "i_iter"),
  elbo = round(vapply(fits, `[[`, numeric(1), "ELBO_iter"), 1),
  runtime_mins = round(vapply(fits, `[[`, numeric(1), "runtime_mins"), 1),
  active_factors = vapply(fits, function(f) sum(f$factor_ppi > 0.5), integer(1)),
  genes_selected = vapply(fits, function(f) sum(apply(f$ppi, 1, max) > 0.5),
                          integer(1)),
  gap_ratio_median = round(gap["median", ], 2),
  gap_ratio_q95 = round(gap["q95", ], 2),
  stringsAsFactors = FALSE
)
rownames(basis_comparison) <- NULL

## The basis is chosen on fit and on gap behaviour only: no external grouping
## and no held-out visit enters this comparison.
##
## Among configurations whose upper-tail gap behaviour is controlled, the one
## with the highest ELBO is taken. The tail threshold is set at 2, meaning that
## for 95% of subject-gene curves the reconstruction varies no more than twice
## as much across the three unobserved weeks as it does over the whole observed
## study. If no configuration meets it, the one with the smallest tail is taken
## and the gate is reported as failed on the temporal representation.
GAP_TAIL_THRESHOLD <- 2

acceptable <- which(basis_comparison$gap_ratio_q95 <= GAP_TAIL_THRESHOLD)
basis_gate_passed <- length(acceptable) > 0L
chosen <- if (basis_gate_passed) {
  acceptable[which.max(basis_comparison$elbo[acceptable])]
} else {
  which.min(basis_comparison$gap_ratio_q95)
}

K_PILOT <- basis_comparison$K[chosen]
L_PILOT <- basis_comparison$L[chosen]
fit <- fits[[chosen]]

pilot_summary <- data.frame(
  item = c("Subjects", "Genes", "Observations", "Q", "L", "K",
           "Iterations to convergence", "Final ELBO", "Runtime (minutes)",
           "Active factors (factor PPI > 0.5)",
           "Genes with PPI > 0.5 on any factor",
           "Gap amplitude ratio (median)",
           "Gap amplitude ratio (95th percentile)",
           "Temporal basis gate"),
  value = c(
    length(subjects),
    length(pilot_genes),
    sum(vapply(time_obs, length, integer(1))),
    Q_PILOT, L_PILOT, K_PILOT,
    fit$i_iter,
    sprintf("%.1f", fit$ELBO_iter),
    sprintf("%.1f", fit$runtime_mins),
    sum(fit$factor_ppi > 0.5),
    sum(apply(fit$ppi, 1, max) > 0.5),
    sprintf("%.2f", basis_comparison$gap_ratio_median[chosen]),
    sprintf("%.2f", basis_comparison$gap_ratio_q95[chosen]),
    if (basis_gate_passed) "passed" else "FAILED"
  ),
  stringsAsFactors = FALSE
)

factor_summary <- data.frame(
  factor = colnames(fit$ppi),
  factor_ppi = round(fit$factor_ppi, 4),
  n_genes_ppi_gt_0.5 = colSums(fit$ppi > 0.5),
  max_abs_loading = round(apply(abs(fit$B_hat), 2, max), 3),
  pve_component_1 = round(vapply(fit$list_cumulated_pve, `[`, numeric(1), 1), 1),
  stringsAsFactors = FALSE
)

utils::write.csv(basis_comparison, path_metrics("01b_basis_comparison.csv"),
                 row.names = FALSE)

gene_panel <- data.frame(
  row_id = pilot_genes,
  symbol = pilot_symbols,
  baseline_mean = round(rowMeans(baseline_subject_mean)[pilot_genes], 3),
  baseline_between_subject_sd = round(between_subject_sd[pilot_genes], 3),
  stringsAsFactors = FALSE
)

utils::write.csv(pilot_summary, path_metrics("01b_pilot_summary.csv"),
                 row.names = FALSE)
utils::write.csv(factor_summary, path_metrics("01b_pilot_factors.csv"),
                 row.names = FALSE)
utils::write.csv(gene_panel, path_metadata("01b_pilot_gene_panel.csv"),
                 row.names = FALSE)

## 5. Figures ------------------------------------------------------------------

## Reconstructed trajectories for the gene with the strongest loading on the
## most active factor, shown against the observed values on the analysis scale.
active <- which.max(fit$factor_ppi)
lead_gene <- names(which.max(abs(fit$B_hat[, active])))

## The unobserved gap is shaded, so that trajectory behaviour that is supported
## by data is visually separated from behaviour that is not.
shade_gap <- function() {
  graphics::rect(GAP_DAYS[1], -1e6, GAP_DAYS[2], 1e6,
                 col = "grey94", border = NA)
  graphics::box()
}

save_progress_figure("01b_pilot_trajectories.png", {
  graphics::par(mfrow = c(1, 2), mar = c(4.5, 4.5, 3, 1))

  days_g <- time_to_day(fit$time_g)

  yl <- range(vapply(fit$list_Y_hat, function(y) range(y[[lead_gene]]), numeric(2)))
  graphics::plot(NA, xlim = range(days_g), ylim = yl,
                 xlab = "Day relative to vaccination",
                 ylab = "Reconstructed expression (scaled)",
                 main = paste0(pilot_symbols[match(lead_gene, pilot_genes)],
                               ": subject trajectories"))
  shade_gap()
  for (i in seq_along(subjects)) {
    graphics::lines(days_g, fit$list_Y_hat[[i]][[lead_gene]],
                    col = grDevices::adjustcolor("#2C7FB8", 0.35))
  }
  graphics::rug(time_to_day(unlist(time_obs)), col = "grey30")

  ## ylim over every subject, not just the first.
  yl_h <- range(vapply(fit$list_h_hat, function(h) range(h[[active]]), numeric(2)))
  graphics::plot(NA, xlim = range(days_g), ylim = yl_h,
                 xlab = "Day relative to vaccination",
                 ylab = "Latent trajectory",
                 main = paste0("Factor ", active, ": latent dynamics"))
  shade_gap()
  for (i in seq_along(subjects)) {
    graphics::lines(days_g, fit$list_h_hat[[i]][[active]],
                    col = grDevices::adjustcolor("#D95F02", 0.35))
  }
  graphics::rug(time_to_day(unlist(time_obs)), col = "grey30")
}, width = 10, height = 4.5)

## The same latent factor under each candidate basis, which is what the choice
## of K is actually about.
save_progress_figure("01b_pilot_basis_comparison.png", {
  graphics::par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
  for (k in seq_along(fits)) {
    f <- fits[[k]]
    q <- which.max(f$factor_ppi)
    days_g <- time_to_day(f$time_g)
    yl <- range(vapply(f$list_h_hat, function(h) range(h[[q]]), numeric(2)))
    graphics::plot(NA, xlim = range(days_g), ylim = yl,
                   xlab = "Day relative to vaccination",
                   ylab = "Latent trajectory",
                   main = sprintf("K = %d, L = %d (gap q95 %.2f)",
                                  basis_comparison$K[k], basis_comparison$L[k],
                                  basis_comparison$gap_ratio_q95[k]))
    shade_gap()
    for (i in seq_along(subjects)) {
      graphics::lines(days_g, f$list_h_hat[[i]][[q]],
                      col = grDevices::adjustcolor("#D95F02", 0.3))
    }
    graphics::rug(time_to_day(unlist(time_obs)), col = "grey30")
  }
}, width = 10, height = 8)

save_progress_figure("01b_pilot_factor_activity.png", {
  graphics::par(mfrow = c(1, 2), mar = c(4.5, 4.5, 3, 1))
  graphics::barplot(fit$factor_ppi, ylim = c(0, 1), col = "#2C7FB8",
                    border = NA, las = 2, ylab = "Factor PPI",
                    main = "Probability each factor is active")
  graphics::abline(h = 0.5, lty = 2)
  graphics::boxplot(as.data.frame(fit$ppi), col = "grey85", las = 2,
                    ylab = "Gene posterior inclusion probability",
                    main = "Loading inclusion by factor")
})

cat("Basis comparison:\n"); print(basis_comparison, row.names = FALSE)
cat("\nChosen configuration:\n")
print(pilot_summary, row.names = FALSE)
cat("\nPer-factor summary:\n"); print(factor_summary, row.names = FALSE)
