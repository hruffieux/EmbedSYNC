## Stage 4b: matched random partitions, the negative control.
##
## Grouping genes at all changes the prior, quite apart from whether the
## grouping is biologically meaningful: pooling inclusion indicators shrinks
## them towards a common rate within each group. A random partition with the
## same group sizes isolates that generic effect, so the comparison against it
## asks whether the *content* of a grouping matters, not merely its shape.
##
## Each informed grouping therefore gets its own null family, built by permuting
## which genes carry which labels while leaving the group-size distribution
## exactly as it was.
##
## The partitions are generated here and saved. They are never regenerated
## inside a fitting function, so every model sees the same partitions and the
## comparison cannot drift between runs.
##
## Runtime: seconds.
##
## Run with:
##   Rscript analysis/R/05_build_random_groups.R

source(here::here("analysis", "R", "00_setup.R"))

N_REPLICATES <- 5L

panel <- readRDS(path_data_processed("02_gene_panel.rds"))
fm <- readRDS(path_groups("03_fm_groups.rds"))
curated <- readRDS(path_groups("04_curated_groups.rds"))

## Everything downstream indexes genes by panel position, so alignment is
## checked here rather than assumed.
stopifnot(identical(fm$row_id, panel$row_id),
          identical(curated$row_id, panel$row_id))

## Permuting the label vector preserves the multiset of labels, so the group
## sizes are preserved exactly rather than in distribution.
permute_labels <- function(labels, seed) {
  set.seed(seed)
  factor(sample(as.character(labels)), levels = levels(labels))
}

informed <- list(fm = fm$group, curated = curated$group)

random_groups <- do.call(rbind, lapply(names(informed), function(family) {
  do.call(rbind, lapply(seq_len(N_REPLICATES), function(r) {
    ## Seeds are a deterministic function of family and replicate, so a
    ## partition can be reproduced without reading the saved file.
    seed <- SEEDS$random_groups + 1000L * match(family, names(informed)) + r
    data.frame(
      family = family,
      replicate = r,
      seed = seed,
      position = panel$position,
      row_id = panel$row_id,
      symbol = panel$symbol,
      group = permute_labels(informed[[family]], seed),
      stringsAsFactors = FALSE
    )
  }))
}))

## Checks -----------------------------------------------------------------------

## Combining the two families with rbind unions their factor levels, so a
## partition's labels must be compared against its own family's levels rather
## than against the combined set.
partition_labels <- function(d) {
  ref <- informed[[d$family[1]]]
  factor(as.character(d$group), levels = levels(ref))
}

## 1. Group sizes match the informed grouping they are matched to, exactly.
size_match <- vapply(split(random_groups, list(random_groups$family,
                                               random_groups$replicate)),
                     function(d) {
                       ref <- informed[[d$family[1]]]
                       identical(as.vector(table(partition_labels(d))),
                                 as.vector(table(ref)))
                     }, logical(1))

## 2. No permutation accidentally reproduces the informed grouping, which would
##    make that replicate a copy of the thing it is supposed to be a null for.
identical_to_informed <- vapply(split(random_groups, list(random_groups$family,
                                                          random_groups$replicate)),
                                function(d) {
                                  identical(as.character(partition_labels(d)),
                                            as.character(informed[[d$family[1]]]))
                                }, logical(1))

## 3. Agreement with the informed grouping, as a sanity check that the
##    permutations really do scramble the biology.
agreement <- vapply(split(random_groups, list(random_groups$family,
                                              random_groups$replicate)),
                    function(d) {
                      mean(as.character(partition_labels(d)) ==
                             as.character(informed[[d$family[1]]]))
                    }, numeric(1))

stopifnot(all(size_match), !any(identical_to_informed))

check_summary <- data.frame(
  item = c("Families", "Replicates per family", "Partitions",
           "Group sizes match the informed grouping",
           "Any partition identical to its informed grouping",
           "Mean gene-level agreement with informed grouping",
           "Expected agreement if labels were independent"),
  value = c(length(informed), N_REPLICATES, nrow(random_groups) / nrow(panel),
            all(size_match), any(identical_to_informed),
            sprintf("%.3f", mean(agreement)),
            sprintf("%.3f", mean(vapply(informed, function(gr) {
              sum((table(gr) / length(gr))^2)
            }, numeric(1))))),
  stringsAsFactors = FALSE
)

saveRDS(random_groups, path_groups("05_random_groups.rds"))
utils::write.csv(random_groups, path_groups("05_random_groups.csv"), row.names = FALSE)
utils::write.csv(check_summary, path_metrics("05_random_group_checks.csv"),
                 row.names = FALSE)

## Stage 4 gate: every grouping vector is aligned to the same gene order -------

all_groupings <- c(
  list(fm = fm[, c("row_id", "group")],
       curated = curated[, c("row_id", "group")]),
  lapply(split(random_groups, list(random_groups$family, random_groups$replicate)),
         function(d) d[, c("row_id", "group")])
)

alignment <- vapply(all_groupings, function(d) {
  identical(d$row_id, panel$row_id) && !anyNA(d$group) && nrow(d) == nrow(panel)
}, logical(1))
stopifnot(all(alignment))

alignment_summary <- data.frame(
  item = c("Grouping vectors checked", "All aligned to the panel order",
           "All complete (no missing group)"),
  value = c(length(all_groupings), all(alignment), all(alignment)),
  stringsAsFactors = FALSE
)
utils::write.csv(alignment_summary, path_metrics("05_grouping_alignment.csv"),
                 row.names = FALSE)
utils::write.csv(provenance(), path_metrics("00_provenance.csv"), row.names = FALSE)


## Comparing the two informed groupings ----------------------------------------

## If scGPT and Reactome partitioned the panel the same way, the foundation
## model would be adding nothing over curated biology and the comparison would
## be uninteresting. The adjusted Rand index measures agreement between the two
## partitions, corrected for the agreement expected by chance.
adjusted_rand <- function(a, b) {
  tab <- table(a, b)
  choose2 <- function(x) x * (x - 1) / 2
  sum_ij <- sum(choose2(tab))
  sum_i <- sum(choose2(rowSums(tab)))
  sum_j <- sum(choose2(colSums(tab)))
  expected <- sum_i * sum_j / choose2(sum(tab))
  (sum_ij - expected) / ((sum_i + sum_j) / 2 - expected)
}

ari <- adjusted_rand(fm$group, curated$group)

informed_comparison <- data.frame(
  item = c("Foundation-model groups", "Curated groups",
           "Adjusted Rand index between them",
           "Mean adjusted Rand index, random against its informed grouping"),
  value = c(nlevels(fm$group), nlevels(curated$group),
            sprintf("%.3f", ari),
            sprintf("%.3f", mean(vapply(
              split(random_groups, list(random_groups$family,
                                        random_groups$replicate)),
              function(d) adjusted_rand(partition_labels(d),
                                        informed[[d$family[1]]]),
              numeric(1))))),
  stringsAsFactors = FALSE
)
utils::write.csv(informed_comparison, path_metrics("05_informed_comparison.csv"),
                 row.names = FALSE)

save_progress_figure("05_grouping_comparison.png", {
  graphics::layout(matrix(c(1, 2, 3, 3), nrow = 2, byrow = TRUE))
  graphics::par(mar = c(4.5, 4.5, 3, 1))

  graphics::barplot(sort(table(fm$group), decreasing = TRUE), col = "#2C7FB8",
                    border = NA, names.arg = NA, xlab = "Group", ylab = "Genes",
                    main = "Foundation-model group sizes")
  graphics::barplot(sort(table(curated$group), decreasing = TRUE), col = "#7FBC41",
                    border = NA, names.arg = NA, xlab = "Group", ylab = "Genes",
                    main = "Curated group sizes")

  tab <- table(fm$group, curated$group)
  graphics::par(mar = c(5, 5, 3, 1))
  graphics::image(seq_len(nrow(tab)), seq_len(ncol(tab)), tab,
                  col = grDevices::hcl.colors(24, "Blues", rev = TRUE),
                  xlab = "Foundation-model group", ylab = "Curated group",
                  main = sprintf("Overlap between the two informed groupings (adjusted Rand %.2f)", ari),
                  axes = FALSE)
  graphics::axis(1, at = seq_len(nrow(tab)), labels = seq_len(nrow(tab)), cex.axis = 0.7)
  graphics::axis(2, at = seq_len(ncol(tab)), labels = colnames(tab), las = 2, cex.axis = 0.55)
  graphics::box()
}, width = 10, height = 8)

cat("\n"); print(informed_comparison, row.names = FALSE)

print(check_summary, row.names = FALSE)
cat("\n"); print(alignment_summary, row.names = FALSE)
cat("\nGroup-size check, first partitions:\n")
print(utils::head(data.frame(partition = names(agreement),
                             agreement = round(agreement, 3),
                             sizes_match = size_match), 4), row.names = FALSE)
