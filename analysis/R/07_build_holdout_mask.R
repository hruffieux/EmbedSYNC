## Stage 7a: fixed held-out visit masks for the primary evaluation.
##
## The primary evaluation hides the full gene-expression vector at one internal
## post-vaccination visit per subject and asks how well each model reconstructs
## it. The masks are built and saved here, before anything is refitted, so that
## every condition is evaluated on exactly the same held-out observations and
## the comparison cannot drift between runs.
##
## Nothing in a mask depends on expression values, on the groupings or on any
## fitted model. The assignment uses the visit design and a fixed seed only.
##
## Runtime: seconds.
##
## Run with:
##   Rscript analysis/R/07_build_holdout_mask.R

source(here::here("analysis", "R", "00_setup.R"))

## Matches 01_prepare_data.R: day -7 and day 0 are pre-vaccination and the last
## visit is around day 28, so days 1 and 7 are the only internal
## post-vaccination times in the design.
INTERNAL_VISITS <- c(1, 7)

## A subject must retain enough observations for its trajectory to be estimable
## from what is left.
MIN_RETAINED_VISITS <- 3L

## One mask to start with. The plan adds replicates only once the first works,
## which is then a change to this constant and nothing else.
N_MASKS <- 1L

dat <- readRDS(path_data_processed("01_gse194378_longitudinal.rds"))
samples <- dat$samples

## Stage 1 resolved duplicated subject-visit pairs, so a subject and a day
## identify one library. The mask is built by that pair, so this is checked
## rather than assumed.
stopifnot(!anyDuplicated(paste(samples$subject_id, samples$day)))

subject_meta <- unique(samples[, c("subject_id", "group")])
stopifnot(!anyDuplicated(subject_meta$subject_id))
subject_meta <- subject_meta[order(subject_meta$subject_id), ]

## 1. Candidate held-out visits ------------------------------------------------

## A visit can only be held out if the subject still has observations on both
## sides of it once it is removed. Reconstructing it is then interpolation
## between retained visits, which is the question the evaluation asks. Holding
## out a subject's last visit would instead test extrapolation beyond the
## observed range, a different and much easier thing to get wrong, and the two
## should not be mixed in one error summary.
##
## The distinction is not hypothetical here: one subject has no visit after
## day 7, so day 7 is its last observation and only day 1 is a candidate for it.
candidate_days <- function(days) {
  internal <- sort(intersect(days, INTERNAL_VISITS))
  interior <- vapply(internal, function(d) {
    retained <- setdiff(days, d)
    any(retained < d) && any(retained > d)
  }, logical(1))
  internal[interior]
}

days_by_subject <- split(samples$day, samples$subject_id)
days_by_subject <- days_by_subject[subject_meta$subject_id]

candidates <- lapply(days_by_subject, candidate_days)
n_visits <- vapply(days_by_subject, length, integer(1))

eligible <- lengths(candidates) > 0L &
  n_visits >= MIN_RETAINED_VISITS + 1L

candidates <- candidates[eligible]
strata <- subject_meta$group[eligible]

## 2. Assignment ---------------------------------------------------------------

#' Assign one held-out day per eligible subject.
#'
#' Subjects with a single candidate have no choice. The rest are allocated
#' around those forced assignments so that days 1 and 7 stay as evenly
#' represented as the design allows, within each study group. Balancing within
#' study group keeps the held-out day from being confounded with the COVR/HC
#' distinction by chance.
#'
#' @param candidates Named list of candidate days, one element per subject.
#' @param strata Study group of each subject, in the same order.
#' @param seed Integer seed.
#' @return Named numeric vector of held-out days.
assign_holdout_days <- function(candidates, strata, seed) {
  set.seed(seed)

  subjects <- names(candidates)
  assigned <- stats::setNames(rep(NA_real_, length(subjects)), subjects)

  forced <- lengths(candidates) == 1L
  assigned[forced] <- vapply(candidates[forced], function(d) d[1], numeric(1))

  for (s in unique(strata)) {
    in_stratum <- strata == s
    free <- subjects[in_stratum & !forced]
    if (length(free) == 0L) next

    n_forced_1 <- sum(assigned[in_stratum & forced] == INTERNAL_VISITS[1])
    n_total <- sum(in_stratum)

    ## Aim for an even split over the whole stratum, then give the free
    ## subjects whatever the forced ones did not already supply.
    n_free_1 <- ceiling(n_total / 2) - n_forced_1
    n_free_1 <- min(max(n_free_1, 0L), length(free))

    draw <- rep(INTERNAL_VISITS, c(n_free_1, length(free) - n_free_1))
    ## Index rather than sample() on the vector itself, which would resample
    ## from seq_len(x) if a stratum ever left a single free subject.
    assigned[free] <- draw[sample.int(length(draw))]
  }

  stopifnot(!anyNA(assigned))
  assigned
}

build_mask <- function(r) {
  ## Seeds are a deterministic function of the replicate, so a mask can be
  ## reproduced without reading the saved file.
  seed <- SEEDS$holdout_mask + r
  held_out <- assign_holdout_days(candidates, strata, seed)

  ## Every assignment must be one of that subject's own candidates.
  stopifnot(all(mapply(function(d, cand) d %in% cand, held_out, candidates)))

  rows <- match(paste(names(held_out), held_out),
                paste(samples$subject_id, samples$day))
  stopifnot(!anyNA(rows))

  data.frame(
    replicate = r,
    seed = seed,
    subject_id = names(held_out),
    study_group = strata,
    library_id = samples$library_id[rows],
    day = samples$day[rows],
    time = day_to_time(samples$day[rows]),
    n_visits = n_visits[names(held_out)],
    stringsAsFactors = FALSE
  )
}

masks <- do.call(rbind, lapply(seq_len(N_MASKS), build_mask))
rownames(masks) <- NULL

## 3. Checks -------------------------------------------------------------------

## The dense grid from Stage 6, rebuilt here so that a widened candidate set
## would be caught rather than silently producing predictions off the grid.
time_g <- sort(unique(c(seq(0, 1, length.out = 400), day_to_time(INTERNAL_VISITS))))

check_mask <- function(m) {
  masked <- samples$library_id %in% m$library_id
  retained <- samples[!masked, ]
  retained_days <- split(retained$day, retained$subject_id)

  ## Interpolation, restated on the mask as built: for every masked visit the
  ## subject still has a retained observation on each side.
  brackets <- mapply(function(subj, d) {
    rd <- retained_days[[subj]]
    any(rd < d) && any(rd > d)
  }, m$subject_id, m$day)

  list(
    one_per_subject = !anyDuplicated(m$subject_id) &&
      nrow(m) == sum(eligible),
    all_internal = all(m$day %in% INTERNAL_VISITS),
    min_retained = min(vapply(retained_days, length, integer(1))),
    all_bracketed = all(brackets),
    day_1_still_observed = sum(retained$day == 1),
    day_7_still_observed = sum(retained$day == 7),
    on_grid = all(m$time %in% time_g),
    n_masked = nrow(m),
    n_retained = nrow(retained)
  )
}

checks <- lapply(split(masks, masks$replicate), check_mask)

stopifnot(
  all(vapply(checks, function(x) x$one_per_subject, logical(1))),
  all(vapply(checks, function(x) x$all_internal, logical(1))),
  all(vapply(checks, function(x) x$all_bracketed, logical(1))),
  all(vapply(checks, function(x) x$on_grid, logical(1))),
  all(vapply(checks, function(x) x$min_retained, integer(1)) >= MIN_RETAINED_VISITS),
  all(vapply(checks, function(x) x$n_masked + x$n_retained, integer(1)) == nrow(samples))
)

check_summary <- do.call(rbind, lapply(names(checks), function(r) {
  x <- checks[[r]]
  data.frame(
    replicate = as.integer(r),
    item = c("Held-out observations",
             "Exactly one per eligible subject",
             "All held-out visits internal post-vaccination",
             "All held-out visits bracketed by retained visits",
             "Held-out times fall on the fitting grid",
             "Minimum retained visits per subject",
             "Day 1 observations retained in other subjects",
             "Day 7 observations retained in other subjects",
             "Observations used for fitting"),
    ## Converted one by one: combining logicals and counts in a single c()
    ## would coerce TRUE to 1 and make the check column harder to read.
    value = c(as.character(x$n_masked),
              as.character(x$one_per_subject), as.character(x$all_internal),
              as.character(x$all_bracketed), as.character(x$on_grid),
              as.character(x$min_retained),
              as.character(x$day_1_still_observed),
              as.character(x$day_7_still_observed),
              as.character(x$n_retained)),
    stringsAsFactors = FALSE
  )
}))

## 4. Design summary ------------------------------------------------------------

## Subjects excluded from the evaluation, and why, so the eligible set is
## readable from the results rather than only from the code.
n_no_candidate <- sum(lengths(lapply(days_by_subject, candidate_days)) == 0L)
n_too_few <- sum(n_visits < MIN_RETAINED_VISITS + 1L)
n_forced <- sum(lengths(candidates) == 1L)

mask_summary <- data.frame(
  item = c("Subjects in the dataset",
           "Subjects with no interior internal visit",
           "Subjects with too few visits",
           "Subjects eligible",
           "Subjects with a single candidate visit",
           "Masks built",
           "Held-out visits per mask"),
  value = as.character(c(nrow(subject_meta), n_no_candidate, n_too_few,
                         sum(eligible), n_forced, N_MASKS,
                         nrow(masks) / N_MASKS)),
  stringsAsFactors = FALSE
)

balance <- as.data.frame(table(replicate = masks$replicate,
                               study_group = masks$study_group,
                               day = masks$day),
                         stringsAsFactors = FALSE)
names(balance)[4] <- "n_subjects"

## 5. Save ----------------------------------------------------------------------

saveRDS(masks, path_masks("07_holdout_masks.rds"))
utils::write.csv(masks, path_masks("07_holdout_masks.csv"), row.names = FALSE)
utils::write.csv(mask_summary, path_metrics("07_mask_summary.csv"), row.names = FALSE)
utils::write.csv(check_summary, path_metrics("07_mask_checks.csv"), row.names = FALSE)
utils::write.csv(balance, path_metrics("07_mask_balance.csv"), row.names = FALSE)
utils::write.csv(provenance(), path_metrics("00_provenance.csv"), row.names = FALSE)

save_progress_figure("07_holdout_mask.png", {
  graphics::par(mfrow = c(1, 2), mar = c(4.5, 4.5, 3, 1))

  first <- masks[masks$replicate == 1, ]
  tab <- table(first$study_group, first$day)
  graphics::barplot(tab, beside = TRUE, col = c("#2C7FB8", "#7FBC41"),
                    border = NA, xlab = "Held-out day", ylab = "Subjects",
                    main = "Held-out visit by study group",
                    ylim = c(0, max(tab) * 1.25),
                    legend.text = rownames(tab),
                    args.legend = list(x = "top", horiz = TRUE, bty = "n",
                                       cex = 0.8, border = NA))

  before <- table(samples$day)
  after <- table(samples$day[!samples$library_id %in% first$library_id])
  after <- after[names(before)]
  after[is.na(after)] <- 0
  graphics::barplot(rbind(as.vector(after), as.vector(before) - as.vector(after)),
                    col = c("grey70", "#D95F02"), border = NA,
                    names.arg = names(before), las = 2,
                    xlab = "Day", ylab = "Observations",
                    main = "Observations retained and held out",
                    legend.text = c("Retained", "Held out"),
                    args.legend = list(bty = "n", cex = 0.8))
}, width = 10, height = 4.5)

cat("\n"); print(mask_summary, row.names = FALSE)
cat("\nBalance:\n"); print(balance[balance$n_subjects > 0, ], row.names = FALSE)
cat("\nChecks:\n"); print(check_summary[, c("item", "value")], row.names = FALSE)
