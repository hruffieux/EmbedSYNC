## Shared setup for the EmbedSYNC analysis scripts.
##
## Every numbered script starts with:
##   source(here::here("analysis", "R", "00_setup.R"))
## and then uses the path helpers below rather than relative paths, so scripts
## behave the same whether run from the console, from Rscript or when knitting
## PROGRESS.Rmd.
##
## The grouped-prior package is bayesSYNCfm, in bayesSYNCfm/. It shares its
## exported function names with the unmodified bayesSYNC, which is kept as the
## reference for the Test A regression check, so both are always called with an
## explicit namespace: bayesSYNCfm::bayesSYNC() or bayesSYNC::bayesSYNC().
## Never attach either with library().

if (!requireNamespace("here", quietly = TRUE)) {
  stop("Package 'here' is required. Install it with install.packages('here').")
}

PROJ_ROOT <- here::here()

## Paths ----------------------------------------------------------------------

path_data_raw       <- function(...) here::here("analysis", "data", "raw", ...)
path_data_processed <- function(...) here::here("analysis", "data", "processed", ...)
path_data_external  <- function(...) here::here("analysis", "data", "external", ...)
path_metadata       <- function(...) here::here("analysis", "metadata", ...)
path_embeddings     <- function(...) here::here("analysis", "objects", "embeddings", ...)
path_groups         <- function(...) here::here("analysis", "objects", "groups", ...)
path_masks          <- function(...) here::here("analysis", "objects", "masks", ...)
path_fits           <- function(...) here::here("analysis", "objects", "fits", ...)
path_metrics        <- function(...) here::here("analysis", "results", "metrics", ...)
path_tables         <- function(...) here::here("analysis", "results", "tables", ...)
path_fig_progress   <- function(...) here::here("analysis", "figures", "progress", ...)
path_pkg            <- function(...) here::here("bayesSYNCfm", ...)

## Seeds ----------------------------------------------------------------------

## One seed per purpose, so that changing the number of random-group replicates
## does not shift the seeds used elsewhere.
SEEDS <- list(
  fit          = 1L,  # bayesSYNC initialisation for every model fit
  community    = 10L, # Leiden community detection on the gene graphs
  random_groups = 20L, # matched random partitions
  holdout_mask = 30L, # subject-specific held-out visit masks
  subsample    = 40L  # subject subsamples for the stability analysis
)

## Time scale ------------------------------------------------------------------

## bayesSYNC works on normalised time in [0, 1]. The mapping is fixed here,
## from the full observed range of GSE194378 visit days, so that every stage
## uses the same time scale. This matters for the held-out evaluation, where a
## candidate held-out day must fall exactly on the dense grid `time_g`.
DAY_RANGE <- c(-7, 30)

#' Map a visit day to normalised time and back.
#'
#' @param day,t Visit day relative to vaccination, or normalised time.
#' @return The value on the other scale.
day_to_time <- function(day) (day - DAY_RANGE[1]) / diff(DAY_RANGE)
time_to_day <- function(t) t * diff(DAY_RANGE) + DAY_RANGE[1]

## Package provenance ---------------------------------------------------------

## Upstream bayesSYNC commit that bayesSYNCfm was derived from. bayesSYNCfm has
## no Git history of its own; its changes are tracked in the EmbedSYNC history.
BAYESSYNC_UPSTREAM_COMMIT <- "de326142f15c8a087f544c84f18d83511aae50f1"

#' Record the software state of a run.
#'
#' Returns a one-row-per-item data frame naming the package versions, the
#' upstream commit and the EmbedSYNC commit, for the reproducibility table in
#' PROGRESS.Rmd. Analysis scripts should save this alongside their results.
#'
#' @return A data frame with columns `item` and `value`.
provenance <- function() {

  pkg_version <- function(pkg) {
    if (requireNamespace(pkg, quietly = TRUE)) {
      as.character(utils::packageVersion(pkg))
    } else {
      NA_character_
    }
  }

  embedsync_commit <- tryCatch(
    system2("git", c("-C", shQuote(PROJ_ROOT), "rev-parse", "HEAD"),
            stdout = TRUE, stderr = FALSE),
    error = function(e) NA_character_
  )
  if (length(embedsync_commit) != 1L) embedsync_commit <- NA_character_

  data.frame(
    item = c("R version", "EmbedSYNC commit", "bayesSYNC upstream commit",
             "bayesSYNC version (reference)", "bayesSYNCfm version", "Date"),
    value = c(R.version.string, embedsync_commit, BAYESSYNC_UPSTREAM_COMMIT,
              pkg_version("bayesSYNC"), pkg_version("bayesSYNCfm"),
              format(Sys.Date())),
    stringsAsFactors = FALSE
  )
}

## Small helpers --------------------------------------------------------------

#' Save a diagnostic figure for PROGRESS.Rmd.
#'
#' @param filename File name (not path) under analysis/figures/progress/.
#' @param expr Plotting code, evaluated for its side effect.
#' @param width,height Device size in inches.
#' @param res Device resolution in dots per inch.
#' @return The full path of the file written, invisibly.
save_progress_figure <- function(filename, expr, width = 8, height = 5, res = 150) {
  file <- path_fig_progress(filename)
  grDevices::png(file, width = width, height = height, units = "in", res = res)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
  invisible(file)
}
