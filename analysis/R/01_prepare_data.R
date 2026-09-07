## Stage 1, data feasibility: retrieve GSE194378, reconstruct the sample design
## and prepare a longitudinal expression matrix for bayesSYNC.
##
## GSE194378 is a whole-blood RNA-seq study around seasonal influenza
## vaccination, in subjects recovered from mild COVID-19 and matched controls.
## RNA-seq was run at days -7, 0, 1, 7 and 28 relative to vaccination.
##
## The design has three features that must be resolved before modelling, and
## that cannot be taken on trust from the series description:
##
##   1. each RNA isolation batch carried a technical control, drawn from a
##      single healthy donor, so some libraries are not biological subjects;
##   2. eleven libraries were re-sequenced on a second instrument to replace
##      initial ones, so some subject-visit pairs may appear twice;
##   3. the sample metadata are stored as ragged key/value characteristics,
##      with four extra fields for COVID-19 recovered subjects, so the fields
##      do not line up by position across samples.
##
## Run with:
##   Rscript analysis/R/01_prepare_data.R

source(here::here("analysis", "R", "00_setup.R"))

suppressPackageStartupMessages(library(org.Hs.eg.db))

GEO_ACCESSION <- "GSE194378"
GEO_BASE <- "https://ftp.ncbi.nlm.nih.gov/geo/series/GSE194nnn/GSE194378"

## Candidate held-out visits for the primary evaluation. Day -7 and day 0 are
## pre-vaccination and day 28 is the last visit, so only days 1 and 7 are
## internal post-vaccination times.
INTERNAL_VISITS <- c(1, 7)

## 1. Retrieve -----------------------------------------------------------------

## Downloads are cached: the raw directory is not tracked, so a fresh checkout
## re-downloads, but repeated runs do not.
download_if_absent <- function(url, dest) {
  if (!file.exists(dest)) {
    message("Downloading ", basename(dest))
    utils::download.file(url, dest, mode = "wb", quiet = TRUE)
  }
  dest
}

series_files <- c(
  GPL18573 = "GSE194378-GPL18573_series_matrix.txt.gz",  # NextSeq 500
  GPL24676 = "GSE194378-GPL24676_series_matrix.txt.gz"   # NovaSeq 6000
)
for (f in series_files) {
  download_if_absent(file.path(GEO_BASE, "matrix", f), path_data_raw(f))
}

## The authors supply both a raw count matrix and a normalised one. bayesSYNC
## assumes a Gaussian observation model, so the normalised matrix is the
## relevant one; the counts are retrieved for the scale diagnostic below.
expr_file  <- "GSE194378_rna.seq.gene.normalized.count.matrix.txt.gz"
count_file <- "GSE194378_rna.seq.gene.count.matrix.txt.gz"
for (f in c(expr_file, count_file)) {
  download_if_absent(file.path(GEO_BASE, "suppl", f), path_data_raw(f))
}

## 2. Sample metadata ----------------------------------------------------------

#' Parse the sample metadata of a GEO series matrix file.
#'
#' The `!Sample_characteristics_ch1` lines hold one `"key: value"` entry per
#' sample, and a series can carry several such lines. Which key appears on which
#' line varies between samples whenever the samples do not all have the same
#' fields, as here, so the entries are matched on their key rather than on their
#' line position.
#'
#' @param file Path to a gzipped GEO series matrix file.
#' @return A data frame with one row per sample.
parse_series_matrix <- function(file) {

  lines <- readLines(gzfile(file), warn = FALSE)
  lines <- lines[startsWith(lines, "!Sample_")]

  split_line <- function(line) {
    parts <- scan(text = line, what = "", sep = "\t", quiet = TRUE,
                  quote = "\"")
    list(key = parts[1], values = parts[-1])
  }
  parsed <- lapply(lines, split_line)
  keys <- vapply(parsed, `[[`, character(1), "key")

  take_one <- function(key) {
    hit <- parsed[keys == key]
    if (length(hit) == 0L) return(NULL)
    hit[[1]]$values
  }

  geo_accession <- take_one("!Sample_geo_accession")
  n <- length(geo_accession)

  out <- data.frame(
    geo_accession = geo_accession,
    title = take_one("!Sample_title"),
    platform_id = take_one("!Sample_platform_id"),
    instrument = take_one("!Sample_instrument_model"),
    stringsAsFactors = FALSE
  )

  ## Collect every "key: value" characteristic, matched on its key.
  char_lines <- parsed[keys == "!Sample_characteristics_ch1"]
  entries <- do.call(rbind, lapply(char_lines, function(p) {
    v <- p$values
    length(v) <- n                     # pad if the line is short
    data.frame(sample = seq_len(n), entry = v, stringsAsFactors = FALSE)
  }))
  entries <- entries[!is.na(entries$entry) & nzchar(entries$entry), ]
  entries$field <- sub(":.*$", "", entries$entry)
  entries$value <- trimws(sub("^[^:]*:", "", entries$entry))

  for (fld in unique(entries$field)) {
    sub_df <- entries[entries$field == fld, ]
    col <- rep(NA_character_, n)
    col[sub_df$sample] <- sub_df$value
    out[[make.names(fld)]] <- col
  }

  out
}

meta <- do.call(rbind, lapply(path_data_raw(series_files), parse_series_matrix))
rownames(meta) <- NULL

## The library identifier in the sample title, e.g. "HC-39 Day 0 (P6.A04)", is
## what links a GEO sample to a column of the expression matrix.
meta$library_id <- sub("^.*\\(([^)]+)\\)$", "\\1", meta$title)
stopifnot(!anyDuplicated(meta$library_id))

## Technical controls come from a single healthy donor included with almost
## every RNA isolation batch. They are identified by the subject id, not by the
## title, so that a subject whose title happens to contain "control" is safe.
meta$is_technical_control <- is.na(meta$subject.id) |
  grepl("^Control", meta$subject.id)

meta$day <- suppressWarnings(as.numeric(meta$days.since.vaccination))
meta$subject_id <- meta$subject.id
meta$group <- meta$group
meta$resequenced <- meta$platform_id == "GPL18573"

## 3. Expression matrices ------------------------------------------------------

## Despite the .txt extension the supplementary matrices are comma-separated,
## with genes in rows and library identifiers in columns.
read_expression <- function(file) {
  m <- utils::read.csv(gzfile(file), header = TRUE, row.names = 1,
                       check.names = FALSE)
  as.matrix(m)
}

expr <- read_expression(path_data_raw(expr_file))

## Library size from the raw counts, used only to choose between duplicated
## libraries below. It is a sequencing quality measure, so it involves no
## expression contrast, no outcome and no held-out visit.
library_size <- colSums(read_expression(path_data_raw(count_file)))

## 4. Resolve duplicated libraries ---------------------------------------------

## A subject-visit pair can appear more than once for two reasons: eleven
## libraries were re-sequenced on a NextSeq 500 to replace initial NovaSeq
## libraries, and some visits were sequenced twice on the NovaSeq. Exactly one
## library is kept per subject-visit, by an explicit rule:
##
##   1. if one copy was re-sequenced, keep it, since the authors describe the
##      re-sequenced libraries as replacements for the initial ones;
##   2. otherwise keep the copy with the larger library size.
##
## Neither criterion uses expression contrasts, subject grouping or the visits
## that will later be held out.
bio <- meta[!meta$is_technical_control, ]
bio$visit_key <- paste(bio$subject_id, bio$day, sep = "_")
bio$library_size <- library_size[bio$library_id]

dup_keys <- unique(bio$visit_key[duplicated(bio$visit_key)])
duplicate_visits <- bio[bio$visit_key %in% dup_keys,
                        c("subject_id", "day", "library_id", "instrument",
                          "resequenced", "library_size")]
duplicate_visits <- duplicate_visits[order(duplicate_visits$subject_id,
                                           duplicate_visits$day,
                                           -duplicate_visits$library_size), ]

## Order so that the preferred copy of each visit comes first, then take it.
bio <- bio[order(bio$visit_key, -bio$resequenced, -bio$library_size), ]
bio_kept <- bio[!duplicated(bio$visit_key), ]
stopifnot(!anyDuplicated(bio_kept$visit_key))
stopifnot(nrow(bio_kept) == length(unique(bio$visit_key)))

duplicate_visits$kept <- duplicate_visits$library_id %in% bio_kept$library_id

## Row names are Entrez gene identifiers carrying a "gene" prefix.
gene_annotation <- data.frame(
  row_id = rownames(expr),
  entrez_id = sub("^gene", "", rownames(expr)),
  stringsAsFactors = FALSE
)
stopifnot(all(grepl("^[0-9]+$", gene_annotation$entrez_id)))
gene_annotation$symbol <- AnnotationDbi::mapIds(
  org.Hs.eg.db, keys = gene_annotation$entrez_id, keytype = "ENTREZID",
  column = "SYMBOL", multiVals = "first"
)

## Align the expression matrix to the retained biological libraries.
stopifnot(all(bio_kept$library_id %in% colnames(expr)))
expr_bio <- expr[, bio_kept$library_id, drop = FALSE]

## 5. Availability and design diagnostics --------------------------------------

availability <- table(bio_kept$subject_id, bio_kept$day)
n_visits_per_subject <- rowSums(availability > 0)

design_summary <- data.frame(
  item = c(
    "GEO accession",
    "Retrieval date",
    "Libraries in series matrices",
    "Technical control libraries",
    "Biological libraries",
    "Re-sequenced libraries",
    "Duplicated subject-visit pairs resolved",
    "Biological libraries retained",
    "Subjects",
    "Distinct RNA-seq days",
    "Genes in normalised matrix",
    "Genes mapping to a current symbol"
  ),
  value = c(
    GEO_ACCESSION,
    ## When the data were actually fetched, not when this script last ran. The
    ## downloads are cached, so Sys.Date() would move the recorded retrieval
    ## date every time the script is rerun for an unrelated reason.
    format(as.Date(file.info(path_data_raw(expr_file))$mtime)),
    nrow(meta),
    sum(meta$is_technical_control),
    nrow(bio),
    sum(meta$resequenced),
    length(dup_keys),
    nrow(bio_kept),
    length(unique(bio_kept$subject_id)),
    paste(sort(unique(bio_kept$day)), collapse = ", "),
    nrow(expr),
    sum(!is.na(gene_annotation$symbol))
  ),
  stringsAsFactors = FALSE
)

visits_per_subject_tab <- as.data.frame(table(n_visits_per_subject),
                                        stringsAsFactors = FALSE)
names(visits_per_subject_tab) <- c("n_visits", "n_subjects")

samples_per_day <- as.data.frame(table(bio_kept$day), stringsAsFactors = FALSE)
names(samples_per_day) <- c("day", "n_samples")

## The nominal visit labels and the actual days apart do not always agree: the
## day -7 and day 28 visits drifted by up to two days for a few subjects. The
## actual days are kept, since bayesSYNC models irregular observation times and
## does not require a shared grid. Rounding them to the nominal visit would
## discard real information about when the blood was drawn.
visit_vs_day <- as.data.frame(table(nominal = bio_kept$visit,
                                    actual_day = bio_kept$day),
                              stringsAsFactors = FALSE)
visit_vs_day <- visit_vs_day[visit_vs_day$Freq > 0, ]
visit_vs_day$actual_day <- as.numeric(visit_vs_day$actual_day)
visit_vs_day <- visit_vs_day[order(visit_vs_day$actual_day), ]
names(visit_vs_day)[3] <- "n_samples"

## Subjects eligible for the held-out evaluation: an internal post-vaccination
## visit to mask, and at least three remaining visits after masking.
has_internal <- vapply(split(bio_kept$day, bio_kept$subject_id),
                       function(d) any(d %in% INTERNAL_VISITS), logical(1))
eligible <- has_internal & (n_visits_per_subject[names(has_internal)] >= 4L)

design_summary <- rbind(design_summary, data.frame(
  item = c("Subjects with a day 1 visit",
           "Subjects with a day 7 visit",
           "Subjects eligible for held-out evaluation"),
  value = as.character(c(
    sum(vapply(split(bio_kept$day, bio_kept$subject_id),
               function(d) 1 %in% d, logical(1))),
    sum(vapply(split(bio_kept$day, bio_kept$subject_id),
               function(d) 7 %in% d, logical(1))),
    sum(eligible)
  )),
  stringsAsFactors = FALSE
))

## 6. Expression scale ---------------------------------------------------------

## The normalised matrix is checked rather than assumed: bayesSYNC has a
## Gaussian likelihood, so the values must be continuous and not strongly
## mean-variance dependent.
gene_mean <- rowMeans(expr_bio)
gene_sd <- apply(expr_bio, 1, stats::sd)

scale_summary <- data.frame(
  item = c("Minimum", "1st quartile", "Median", "3rd quartile", "Maximum",
           "Proportion negative", "Spearman cor(mean, sd)"),
  value = c(
    sprintf("%.2f", min(expr_bio)),
    sprintf("%.2f", stats::quantile(expr_bio, 0.25)),
    sprintf("%.2f", stats::median(expr_bio)),
    sprintf("%.2f", stats::quantile(expr_bio, 0.75)),
    sprintf("%.2f", max(expr_bio)),
    sprintf("%.3f", mean(expr_bio < 0)),
    sprintf("%.3f", stats::cor(gene_mean, gene_sd, method = "spearman"))
  ),
  stringsAsFactors = FALSE
)

## 7. Save ---------------------------------------------------------------------

saveRDS(list(expr = expr_bio, samples = bio_kept, genes = gene_annotation),
        path_data_processed("01_gse194378_longitudinal.rds"))

utils::write.csv(design_summary, path_metrics("01_design_summary.csv"),
                 row.names = FALSE)
utils::write.csv(visits_per_subject_tab,
                 path_metrics("01_visits_per_subject.csv"), row.names = FALSE)
utils::write.csv(samples_per_day, path_metrics("01_samples_per_day.csv"),
                 row.names = FALSE)
utils::write.csv(visit_vs_day, path_metrics("01_visit_vs_actual_day.csv"),
                 row.names = FALSE)
utils::write.csv(scale_summary, path_metrics("01_expression_scale.csv"),
                 row.names = FALSE)
utils::write.csv(duplicate_visits, path_metrics("01_duplicate_visits.csv"),
                 row.names = FALSE)
utils::write.csv(provenance(), path_metrics("00_provenance.csv"),
                 row.names = FALSE)

## 8. Figures ------------------------------------------------------------------

## Plotted on a true day axis rather than one column per distinct day, so that
## the gap between the day 7 and day 28 visits is not visually compressed.
save_progress_figure("01_subject_time_availability.png", {
  subj <- unique(bio_kept$subject_id[order(bio_kept$group, bio_kept$subject_id)])
  y <- match(bio_kept$subject_id, subj)
  is_covr <- bio_kept$group == "COVR"

  graphics::par(mar = c(4.5, 5.5, 3, 1), pty = "s")
  graphics::plot(bio_kept$day, y, type = "n",
                 xlab = "Day relative to vaccination", ylab = "",
                 yaxt = "n", main = "GSE194378: subject by visit availability")
  for (i in seq_along(subj)) {
    d <- bio_kept$day[bio_kept$subject_id == subj[i]]
    graphics::segments(min(d), i, max(d), i, col = "grey85")
  }
  graphics::points(bio_kept$day, y, pch = 16, cex = 0.55,
                   col = ifelse(is_covr, "#D95F02", "#2C7FB8"))
  graphics::axis(2, at = seq(1, length(subj), by = 5),
                 labels = subj[seq(1, length(subj), by = 5)],
                 las = 2, cex.axis = 0.6)
  graphics::legend("bottomright", pch = 16, bty = "n", cex = 0.8,
                   col = c("#2C7FB8", "#D95F02"),
                   legend = c("Healthy control", "COVID-19 recovered"))
}, width = 8, height = 9)

save_progress_figure("01_expression_scale.png", {
  graphics::par(mfrow = c(1, 2), mar = c(4.5, 4.5, 3, 1))
  graphics::hist(expr_bio[sample(length(expr_bio), 2e5)], breaks = 80,
                 col = "grey80", border = NA,
                 xlab = "Normalised expression",
                 main = "Value distribution")
  graphics::smoothScatter(gene_mean, gene_sd,
                          xlab = "Gene mean", ylab = "Gene SD",
                          main = "Mean-variance relationship")
})

print(design_summary, row.names = FALSE)
cat("\nVisits per subject:\n"); print(visits_per_subject_tab, row.names = FALSE)
cat("\nSamples per day:\n"); print(samples_per_day, row.names = FALSE)
cat("\nNominal visit against actual day:\n")
print(visit_vs_day, row.names = FALSE)
cat("\nExpression scale:\n"); print(scale_summary, row.names = FALSE)
if (nrow(duplicate_visits) > 0) {
  cat("\nDuplicated subject-visit pairs:\n")
  print(duplicate_visits, row.names = FALSE)
}
