## Stage 0 check: renaming bayesSYNC to bayesSYNCfm must not change any result.
##
## bayesSYNCfm is derived from bayesSYNC by renaming the package only; no model
## code has been touched yet. Fitting the same simulated data with the same seed
## and the same arguments under each package must therefore give identical
## output. This is the baseline the Stage 5 Test A regression check builds on:
## once prior_groups is added, prior_groups = NULL must still reproduce these
## same results.
##
## Run with:
##   Rscript analysis/R/00_check_package_rename.R

source(here::here("analysis", "R", "00_setup.R"))

if (!requireNamespace("Splinets", quietly = TRUE)) {
  stop("Package 'Splinets' is required by generate_bayesSYNC_data().")
}

## Small simulated dataset --------------------------------------------------

## Deliberately small and capped at maxit = 30. The check is exact equality of
## two runs, not convergence, so the fits do not need to converge.
N <- 20L
p <- 8L

set.seed(SEEDS$fit)
n_visits <- sample(3:6, N, replace = TRUE)

sim <- bayesSYNCfm::generate_bayesSYNC_data(
  N = N, n = n_visits, p = p, Q = 2, L = 2,
  mu_func = function(t, j, p) 1.5 * j + sin(2 * pi * t + j),
  a_om = 5, b_om = 2,
  vec_sd_zeta = c(1, 0.5),
  vec_sd_eps = 0.2,
  seed = SEEDS$fit
)

fit_args <- list(
  time_obs = sim$time_obs, Y = sim$Y,
  L = 2, Q = 3,
  anneal = NULL, maxit = 30,
  seed = SEEDS$fit,
  bool_scale = FALSE,
  bool_var_spec_prob = FALSE,  # grouped mode will require this
  verbose = FALSE
)

fit_ref <- suppressWarnings(do.call(bayesSYNC::bayesSYNC,   fit_args))
fit_fm  <- suppressWarnings(do.call(bayesSYNCfm::bayesSYNC, fit_args))

## Compare every output that later stages depend on -------------------------

compared <- c("B_hat", "ppi", "omega_hat", "factor_ppi", "ELBO_iter", "i_iter",
              "list_Y_hat", "list_h_hat", "list_Zeta_hat", "list_mu_hat",
              "list_list_Phi_hat", "list_cumulated_pve", "time_g")

result <- data.frame(
  output = compared,
  identical = vapply(compared,
                     function(nm) isTRUE(all.equal(fit_ref[[nm]], fit_fm[[nm]])),
                     logical(1)),
  stringsAsFactors = FALSE
)

## bayesSYNC_core() holds the inference; comparing it directly guards against
## the installed reference drifting away from the code bayesSYNCfm came from.
core_identical <- identical(
  deparse(getFromNamespace("bayesSYNC_core", "bayesSYNC")),
  deparse(getFromNamespace("bayesSYNC_core", "bayesSYNCfm"))
)

print(result, row.names = FALSE)
cat("\nbayesSYNC_core() source identical:", core_identical, "\n")
cat("ELBO:", format(fit_ref$ELBO_iter), "(bayesSYNC) /",
    format(fit_fm$ELBO_iter), "(bayesSYNCfm)\n")

utils::write.csv(result, path_metrics("00_package_rename_check.csv"),
                 row.names = FALSE)
utils::write.csv(provenance(), path_metrics("00_provenance.csv"),
                 row.names = FALSE)

if (!all(result$identical)) {
  stop("bayesSYNCfm does not reproduce bayesSYNC. This is a gate: diagnose ",
       "before making any model change.")
}

cat("\nPASS: bayesSYNCfm reproduces bayesSYNC on every compared output.\n")
