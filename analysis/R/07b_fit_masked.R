## Stage 7b: refit every condition to the masked data.
##
## Same thirteen conditions as Stage 6 and the same settings throughout: gene
## panel, subjects, Q, L, K, dense grid, scaling, annealing schedule,
## tolerances and seed. The only difference from Stage 6 is the data. One
## internal post-vaccination visit per subject is removed, following the mask
## saved by 07_build_holdout_mask.R, and the conditions still differ in
## `prior_groups` and in nothing else.
##
## Each fit is cached, so the script can be interrupted and resumed, and
## rerunning it refits nothing.
##
## What is cached is a slimmed fit. The full object is about 680 MB, almost all
## of it the reconstructed trajectories and credible bands held on a 400-point
## grid for every subject and gene. The evaluation needs those three lists at
## one grid point per subject, so the held-out slice is extracted here and the
## lists are dropped before saving. Everything else the report uses (the ELBO,
## the loadings, the inclusion probabilities, the group probabilities, the
## factor trajectories) is kept, and a fit costs tens of megabytes rather than
## hundreds. Adding held-out replicates is then affordable.
##
## Predictions are stored on the fitting scale, together with the per-gene
## scaling constants. Returning them to the original analysis scale happens in
## 07c_evaluate_holdout.R, next to the observed values they are compared with.
##
## Runtime: roughly 15 to 20 minutes per fit, so three to four hours for one
## replicate.
##
## Run with:
##   Rscript analysis/R/07b_fit_masked.R

source(here::here("analysis", "R", "00_setup.R"))

## Identical to Stage 6.
Q_FIT <- 5L
L_FIT <- 2L
K_FIT <- 5L

N_CPUS <- max(1L, parallel::detectCores() - 2L)

## Replicates to fit. The mask file may hold more than one; fitting them is a
## separate decision from building them, because each costs about three and a
## half hours.
REPLICATES <- 1L

## 1. Model input ---------------------------------------------------------------

dat <- readRDS(path_data_processed("01_gse194378_longitudinal.rds"))
panel <- readRDS(path_data_processed("02_gene_panel.rds"))
masks <- readRDS(path_masks("07_holdout_masks.rds"))

expr <- dat$expr
samples <- dat$samples
subjects <- sort(unique(samples$subject_id))

stopifnot(all(REPLICATES %in% masks$replicate))

## Same grid expression as Stage 6, so the held-out days remain exact grid
## points and the two stages differ only in their data.
time_g <- sort(unique(c(seq(0, 1, length.out = 400), day_to_time(c(1, 7)))))
stopifnot(all(day_to_time(c(1, 7)) %in% time_g))

#' Assemble the bayesSYNC inputs from the retained observations.
#'
#' @param mask_r One replicate of the held-out mask.
#' @return List with `time_obs` and `Y`, both named by subject.
masked_input <- function(mask_r) {
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

  ## The mask removes one visit per subject and nothing else.
  stopifnot(
    nrow(retained) == nrow(samples) - nrow(mask_r),
    all(vapply(time_obs, length, integer(1)) >= 3L),
    !any(vapply(seq_along(subjects), function(i) {
      any(day_to_time(mask_r$day[mask_r$subject_id == subjects[i]]) %in% time_obs[[i]])
    }, logical(1)))
  )

  list(time_obs = time_obs, Y = Y)
}

## 2. Conditions ----------------------------------------------------------------

## Built exactly as at Stage 6: the groupings do not depend on the data, so the
## masking does not touch them.
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

## 3. Held-out slice ------------------------------------------------------------

#' Pull the reconstruction at each subject's held-out time.
#'
#' The point estimate and both credible limits are taken at the one grid index
#' that matches the subject's held-out visit, for every gene. Values stay on the
#' fitting scale; the scaling constants travel with them.
#'
#' @param fit A fitted bayesSYNC object.
#' @param mask_r One replicate of the held-out mask.
#' @return List of three genes-by-subjects matrices, plus the scaling constants.
extract_holdout <- function(fit, mask_r) {
  grid_index <- match(mask_r$time, fit$time_g)
  subject_index <- match(mask_r$subject_id, names(fit$Y))
  stopifnot(!anyNA(grid_index), !anyNA(subject_index))

  slice <- function(component) {
    out <- vapply(seq_len(nrow(mask_r)), function(m) {
      trajectories <- fit[[component]][[subject_index[m]]]
      vapply(trajectories, function(y) y[grid_index[m]], numeric(1))
    }, numeric(length(fit$Y[[1]])))
    dimnames(out) <- list(panel$row_id, mask_r$subject_id)
    out
  }

  list(
    hat = slice("list_Y_hat"),
    low = slice("list_Y_low"),
    upp = slice("list_Y_upp"),
    gene_mean = fit$mean_mean_across_subjects,
    gene_sd = fit$sd_mean_across_subjects
  )
}

## The trajectory lists are the whole of the object's size and the slice above
## is all the evaluation needs from them.
TRAJECTORY_COMPONENTS <- c("list_Y_hat", "list_Y_low", "list_Y_upp")

## 4. Fit -----------------------------------------------------------------------

fit_condition <- function(name, prior_groups, input, mask_r, r) {
  fit_file <- path_fits(sprintf("07_r%d_%s.rds", r, name))
  if (file.exists(fit_file)) {
    message(sprintf("[r%d %s] cached, skipping", r, name))
    return(invisible(NULL))
  }

  message(sprintf("[r%d %s] fitting at %s", r, name,
                  format(Sys.time(), "%H:%M:%S")))
  t0 <- Sys.time()
  fit <- bayesSYNCfm::bayesSYNC(
    time_obs = input$time_obs, Y = input$Y,
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
  fit$replicate <- r

  fit$holdout <- extract_holdout(fit, mask_r)
  fit[TRAJECTORY_COMPONENTS] <- NULL

  saveRDS(fit, fit_file)
  message(sprintf("[r%d %s] done in %.1f min, ELBO %.1f, %d iterations",
                  r, name, fit$runtime_mins, fit$ELBO_iter, fit$i_iter))
  invisible(NULL)
}

for (r in REPLICATES) {
  mask_r <- masks[masks$replicate == r, ]
  input <- masked_input(mask_r)
  message(sprintf("Replicate %d: %d observations retained, %d held out",
                  r, sum(lengths(input$time_obs)), nrow(mask_r)))

  for (name in names(conditions)) {
    fit_condition(name, conditions[[name]], input, mask_r, r)
  }
}

## 5. Summary -------------------------------------------------------------------

summarise_fit <- function(name, r) {
  fit_file <- path_fits(sprintf("07_r%d_%s.rds", r, name))
  if (!file.exists(fit_file)) return(NULL)
  fit <- readRDS(fit_file)
  data.frame(
    replicate = r,
    condition = name,
    grouping = if (is.null(fit$prior_groups)) "none" else "grouped",
    iterations = fit$i_iter,
    runtime_mins = round(fit$runtime_mins, 1),
    elbo = round(fit$ELBO_iter, 1),
    active_factors = sum(fit$factor_ppi > 0.5),
    genes_selected = sum(apply(fit$ppi, 1, max) > 0.5),
    stringsAsFactors = FALSE
  )
}

fit_summary <- do.call(rbind, lapply(REPLICATES, function(r) {
  do.call(rbind, lapply(names(conditions), summarise_fit, r = r))
}))

if (!is.null(fit_summary)) {
  utils::write.csv(fit_summary, path_metrics("07_masked_fit_summary.csv"),
                   row.names = FALSE)
  utils::write.csv(provenance(), path_metrics("00_provenance.csv"),
                   row.names = FALSE)
  print(fit_summary, row.names = FALSE)
}
