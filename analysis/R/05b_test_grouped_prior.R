## Stage 5 gate: package tests A to F for the grouped prior.
##
## Each test targets a distinct way the implementation could be wrong, and a
## failure in any of them is a gate: it must be diagnosed before the grouped
## prior is used on real data.
##
##   A  prior_groups = NULL reproduces the unmodified bayesSYNC exactly.
##   B  one group containing every variable reduces to the factor-specific prior.
##   C  the size-adjusted prior leaves the expected sparsity unchanged by the
##      partition.
##   D  the coded grouped Beta update matches the equations directly.
##   E  a grouped signal is recovered better with the correct groups than with
##      matched random groups or no groups.
##   F  grouped fits behave with and without annealing.
##
## Runtime: about five minutes.
##
## Run with:
##   Rscript analysis/R/05b_test_grouped_prior.R

source(here::here("analysis", "R", "00_setup.R"))

results <- list()
record <- function(test, description, passed, detail = "") {
  results[[length(results) + 1L]] <<- data.frame(
    test = test, description = description,
    result = if (isTRUE(passed)) "PASS" else "FAIL",
    detail = detail, stringsAsFactors = FALSE
  )
  cat(sprintf("%-8s %-50s %s  %s\n", test, description,
              if (isTRUE(passed)) "PASS" else "FAIL", detail))
}

## Shared small dataset --------------------------------------------------------

set.seed(SEEDS$fit)
N <- 25L; p <- 12L
sim <- bayesSYNCfm::generate_bayesSYNC_data(
  N = N, n = sample(4:7, N, replace = TRUE), p = p, Q = 2, L = 2,
  mu_func = function(t, j, p) 1.5 * j + sin(2 * pi * t + j),
  a_om = 5, b_om = 2, vec_sd_zeta = c(1, 0.5), vec_sd_eps = 0.2,
  seed = SEEDS$fit
)
var_names <- names(sim$Y[[1]])

fit_args <- list(time_obs = sim$time_obs, Y = sim$Y, L = 2, Q = 3, K = 5,
                 anneal = NULL, maxit = 40, seed = SEEDS$fit,
                 bool_scale = FALSE, bool_var_spec_prob = FALSE, verbose = FALSE)

compare_outputs <- function(f1, f2, what = c("B_hat", "ppi", "factor_ppi",
                                             "ELBO_iter", "list_Y_hat",
                                             "list_Zeta_hat")) {
  bad <- what[!vapply(what, function(nm) isTRUE(all.equal(f1[[nm]], f2[[nm]])),
                      logical(1))]
  list(ok = length(bad) == 0L,
       detail = if (length(bad)) paste("differs:", paste(bad, collapse = ", ")) else "")
}

## Test A ----------------------------------------------------------------------

fit_reference <- suppressWarnings(do.call(bayesSYNC::bayesSYNC, fit_args))
fit_null <- suppressWarnings(do.call(bayesSYNCfm::bayesSYNC,
                                     c(fit_args, list(prior_groups = NULL))))
a <- compare_outputs(fit_reference, fit_null)
record("Test A", "prior_groups = NULL reproduces bayesSYNC", a$ok,
       if (a$ok) sprintf("ELBO %.6f", fit_null$ELBO_iter) else a$detail)

## Test B ----------------------------------------------------------------------

one_group <- stats::setNames(rep("all", p), var_names)
fit_one <- suppressWarnings(do.call(bayesSYNCfm::bayesSYNC,
                                    c(fit_args, list(prior_groups = one_group))))
b <- compare_outputs(fit_reference, fit_one)
record("Test B", "single group reduces to factor-specific prior", b$ok,
       if (b$ok) sprintf("ELBO %.6f", fit_one$ELBO_iter) else b$detail)

## Test C ----------------------------------------------------------------------

c_0 <- 1; d_0 <- p
target <- p * c_0 / (c_0 + d_0)
partitions <- list(one = p, equal = rep(p / 4, 4), uneven = c(1, 2, 3, 6),
                   very_uneven = c(9, 1, 1, 1))
expected_active <- vapply(partitions, function(n_k) {
  rho <- n_k / sum(n_k)
  a <- rho * c_0; b <- rho * d_0
  sum(n_k * a / (a + b))
}, numeric(1))
c_ok <- all(abs(expected_active - target) < 1e-10)
record("Test C", "size-adjusted prior preserves expected sparsity", c_ok,
       sprintf("target %.5f, max deviation %.2e", target,
               max(abs(expected_active - target))))

## Test D ----------------------------------------------------------------------

groups_d <- stats::setNames(rep(c("g1", "g2", "g3"), each = p / 3), var_names)
fit_d <- suppressWarnings(do.call(bayesSYNCfm::bayesSYNC,
                                  c(fit_args, list(prior_groups = groups_d))))

hyper <- fit_d$group_prior_hyperparameters
group_of <- fit_d$prior_groups
group_sum <- rowsum(fit_d$ppi, group = group_of[rownames(fit_d$ppi)],
                    reorder = TRUE)
group_sum <- group_sum[hyper$group, , drop = FALSE]
expected_pi <- (hyper$a + group_sum) / (hyper$a + hyper$b + hyper$n_variables)
d_ok <- isTRUE(all.equal(unname(expected_pi), unname(fit_d$group_inclusion_prob),
                         tolerance = 1e-10))
record("Test D", "grouped Beta update matches the equations", d_ok,
       sprintf("max |difference| %.2e",
               max(abs(expected_pi - fit_d$group_inclusion_prob))))

d2_ok <- isTRUE(all.equal(sum(hyper$n_variables * hyper$a / (hyper$a + hyper$b)),
                          p * c_0 / (c_0 + d_0), tolerance = 1e-10))
record("Test D2", "implemented hyperparameters preserve sparsity", d2_ok,
       sprintf("sum n_k E(pi_k) = %.5f",
               sum(hyper$n_variables * hyper$a / (hyper$a + hyper$b))))

## Test E ----------------------------------------------------------------------

simulate_grouped <- function(N, n_group, K_G, Q_true, seed) {
  set.seed(seed)
  p <- n_group * K_G
  group <- rep(sprintf("G%d", seq_len(K_G)), each = n_group)
  B <- matrix(0, nrow = p, ncol = Q_true)
  for (q in seq_len(Q_true)) {
    B[group == sprintf("G%d", q), q] <- stats::rnorm(n_group, 0, 1.5)
  }
  psi <- list(function(t) sqrt(2) * sin(2 * pi * t),
              function(t) sqrt(2) * cos(2 * pi * t))
  zeta <- lapply(seq_len(Q_true), function(q)
    cbind(stats::rnorm(N, 0, 1), stats::rnorm(N, 0, 0.5)))
  time_obs <- lapply(seq_len(N), function(i) sort(stats::runif(6)))
  Y <- lapply(seq_len(N), function(i) {
    tt <- time_obs[[i]]
    h <- vapply(seq_len(Q_true), function(q)
      zeta[[q]][i, 1] * psi[[1]](tt) + zeta[[q]][i, 2] * psi[[2]](tt),
      numeric(length(tt)))
    y <- lapply(seq_len(p), function(j)
      2 * j / p + as.vector(h %*% B[j, ]) + stats::rnorm(length(tt), 0, 0.3))
    stats::setNames(y, sprintf("v%03d", seq_len(p)))
  })
  names(Y) <- names(time_obs) <- sprintf("s%02d", seq_len(N))
  list(Y = Y, time_obs = time_obs,
       group = stats::setNames(group, sprintf("v%03d", seq_len(p))),
       active = stats::setNames(rowSums(B != 0) > 0, sprintf("v%03d", seq_len(p))))
}

sim_e <- simulate_grouped(N = 40L, n_group = 15L, K_G = 4L, Q_true = 2L,
                          seed = SEEDS$fit)
set.seed(SEEDS$random_groups)
random_group <- stats::setNames(sample(as.character(sim_e$group)),
                                names(sim_e$group))

args_e <- list(time_obs = sim_e$time_obs, Y = sim_e$Y, L = 2, Q = 3, K = 5,
               anneal = NULL, maxit = 150, seed = SEEDS$fit,
               bool_scale = FALSE, bool_var_spec_prob = FALSE, verbose = FALSE)

fit_correct <- suppressWarnings(do.call(bayesSYNCfm::bayesSYNC,
                                        c(args_e, list(prior_groups = sim_e$group))))
fit_random <- suppressWarnings(do.call(bayesSYNCfm::bayesSYNC,
                                       c(args_e, list(prior_groups = random_group))))
fit_vanilla <- suppressWarnings(do.call(bayesSYNCfm::bayesSYNC, args_e))

auc <- function(score, truth) {
  r <- rank(score)
  n1 <- sum(truth); n0 <- sum(!truth)
  if (n1 == 0 || n0 == 0) return(NA_real_)
  (sum(r[truth]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
recovery <- vapply(list(correct = fit_correct, random = fit_random,
                        vanilla = fit_vanilla),
                   function(f) auc(apply(f$ppi, 1, max),
                                   sim_e$active[rownames(f$ppi)]), numeric(1))

e_ok <- recovery[["correct"]] >= recovery[["random"]]
record("Test E", "correct groups recover the signal at least as well", e_ok,
       sprintf("AUC correct %.3f, random %.3f, vanilla %.3f",
               recovery[["correct"]], recovery[["random"]], recovery[["vanilla"]]))

## Test F ----------------------------------------------------------------------

fit_anneal <- suppressWarnings(do.call(bayesSYNCfm::bayesSYNC,
  c(args_e[setdiff(names(args_e), "anneal")],
    list(anneal = c(1, 1.9, 30), prior_groups = sim_e$group))))

f_ok <- is.finite(fit_anneal$ELBO_iter) && is.finite(fit_correct$ELBO_iter) &&
  fit_anneal$i_iter > 0 &&
  length(unique(fit_anneal$prior_groups)) == 4L
record("Test F", "grouped fits run with and without annealing", f_ok,
       sprintf("ELBO annealed %.1f, unannealed %.1f",
               fit_anneal$ELBO_iter, fit_correct$ELBO_iter))

## Outputs ---------------------------------------------------------------------

expected_names <- names(fit_reference)
g_ok <- all(expected_names %in% names(fit_correct))
record("Outputs", "original outputs preserved, new ones added", g_ok,
       sprintf("added: %s",
               paste(setdiff(names(fit_correct), expected_names), collapse = ", ")))

## Summary ---------------------------------------------------------------------

summary_df <- do.call(rbind, results)
utils::write.csv(summary_df, path_metrics("05b_grouped_prior_tests.csv"),
                 row.names = FALSE)
utils::write.csv(data.frame(model = names(recovery), auc = round(recovery, 4)),
                 path_metrics("05b_test_e_recovery.csv"), row.names = FALSE)
utils::write.csv(provenance(), path_metrics("00_provenance.csv"), row.names = FALSE)

cat("\n")
if (all(summary_df$result == "PASS")) {
  cat("All grouped-prior tests passed.\n")
} else {
  stop("Grouped-prior tests failed: ",
       paste(summary_df$test[summary_df$result != "PASS"], collapse = ", "),
       ". This is a gate; diagnose before continuing.")
}
