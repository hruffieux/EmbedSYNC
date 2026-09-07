## Stage 6: first full-data comparison.
##
## Fits the same 1,000-gene panel under every condition: vanilla bayesSYNC, the
## curated grouping, the foundation-model grouping, and five matched random
## partitions for each informed grouping. Thirteen fits in all.
##
## Everything that could advantage one condition over another is held fixed:
## the gene panel, the subjects, the observations, Q, L, K, the dense grid, the
## scaling, the annealing schedule, the convergence tolerances and the seed.
## The conditions differ in `prior_groups` and in nothing else. No model is
## tuned separately.
##
## Each fit is cached to analysis/objects/fits/, so the script can be
## interrupted and resumed without losing completed work, and rerunning it
## refits nothing.
##
## Runtime: roughly 15 to 20 minutes per fit, so three to four hours in total.
##
## Run with:
##   Rscript analysis/R/06_fit_models.R

source(here::here("analysis", "R", "00_setup.R"))

Q_FIT <- 5L    # deliberately over-specified; the prior prunes what is unused
L_FIT <- 2L    # smallest value the package supports
K_FIT <- 5L    # chosen at Stage 1 on the temporal basis check

## Leave two cores free so the machine stays usable while this runs.
N_CPUS <- max(1L, parallel::detectCores() - 2L)

## 1. Model input ---------------------------------------------------------------

dat <- readRDS(path_data_processed("01_gse194378_longitudinal.rds"))
panel <- readRDS(path_data_processed("02_gene_panel.rds"))

expr <- dat$expr
samples <- dat$samples
subjects <- sort(unique(samples$subject_id))

time_obs <- vector("list", length(subjects))
Y <- vector("list", length(subjects))
names(time_obs) <- names(Y) <- subjects

for (i in seq_along(subjects)) {
  rows <- samples[samples$subject_id == subjects[i], ]
  rows <- rows[order(rows$day), ]
  time_obs[[i]] <- day_to_time(rows$day)
  sub_expr <- expr[panel$row_id, rows$library_id, drop = FALSE]
  Y[[i]] <- lapply(seq_len(nrow(sub_expr)), function(j) as.numeric(sub_expr[j, ]))
  names(Y[[i]]) <- panel$row_id
}

## The held-out evaluation extracts predictions at exact grid points, so the
## grid is built to contain the candidate held-out days from the outset. Using
## the same grid here means Stage 7 changes only the data, not the settings.
time_g <- sort(unique(c(seq(0, 1, length.out = 400), day_to_time(c(1, 7)))))
stopifnot(all(day_to_time(c(1, 7)) %in% time_g))

## 2. Conditions ----------------------------------------------------------------

fm <- readRDS(path_groups("03_fm_groups.rds"))
curated <- readRDS(path_groups("04_curated_groups.rds"))
random <- readRDS(path_groups("05_random_groups.rds"))

stopifnot(identical(fm$row_id, panel$row_id),
          identical(curated$row_id, panel$row_id))

as_prior_groups <- function(labels) {
  stats::setNames(as.character(labels), panel$row_id)
}

conditions <- list(
  vanilla = NULL,
  curated = as_prior_groups(curated$group),
  fm = as_prior_groups(fm$group)
)

for (family in unique(random$family)) {
  for (r in sort(unique(random$replicate))) {
    part <- random[random$family == family & random$replicate == r, ]
    part <- part[match(panel$row_id, part$row_id), ]
    stopifnot(identical(part$row_id, panel$row_id))
    conditions[[sprintf("random_%s_%d", family, r)]] <- as_prior_groups(part$group)
  }
}

## 3. Fit -----------------------------------------------------------------------

fit_condition <- function(name, prior_groups) {
  fit_file <- path_fits(sprintf("06_%s.rds", name))
  if (file.exists(fit_file)) {
    message(sprintf("[%s] cached, skipping", name))
    return(invisible(NULL))
  }

  message(sprintf("[%s] fitting at %s", name, format(Sys.time(), "%H:%M:%S")))
  t0 <- Sys.time()
  fit <- bayesSYNCfm::bayesSYNC(
    time_obs = time_obs, Y = Y,
    L = L_FIT, Q = Q_FIT, K = K_FIT,
    time_g = time_g, n_g = NULL,
    seed = SEEDS$fit,
    bool_scale = TRUE,
    bool_var_spec_prob = FALSE,
    prior_groups = prior_groups,
    n_cpus = N_CPUS,
    verbose = FALSE
  )
  fit$runtime_mins <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  fit$condition <- name
  saveRDS(fit, fit_file)
  message(sprintf("[%s] done in %.1f min, ELBO %.1f, %d iterations",
                  name, fit$runtime_mins, fit$ELBO_iter, fit$i_iter))
  invisible(NULL)
}

for (name in names(conditions)) {
  fit_condition(name, conditions[[name]])
}

## 4. Summary -------------------------------------------------------------------

summarise_fit <- function(name) {
  fit_file <- path_fits(sprintf("06_%s.rds", name))
  if (!file.exists(fit_file)) return(NULL)
  fit <- readRDS(fit_file)
  data.frame(
    condition = name,
    grouping = if (is.null(fit$prior_groups)) "none" else "grouped",
    n_groups = if (is.null(fit$prior_groups)) NA_integer_
               else length(unique(fit$prior_groups)),
    iterations = fit$i_iter,
    runtime_mins = round(fit$runtime_mins, 1),
    elbo = round(fit$ELBO_iter, 1),
    active_factors = sum(fit$factor_ppi > 0.5),
    genes_selected = sum(apply(fit$ppi, 1, max) > 0.5),
    stringsAsFactors = FALSE
  )
}

fit_summary <- do.call(rbind, lapply(names(conditions), summarise_fit))

if (!is.null(fit_summary)) {
  utils::write.csv(fit_summary, path_metrics("06_fit_summary.csv"),
                   row.names = FALSE)
  utils::write.csv(provenance(), path_metrics("00_provenance.csv"),
                   row.names = FALSE)
  print(fit_summary, row.names = FALSE)
}
