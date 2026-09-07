## Stage 3: build foundation-model gene groups from scGPT embeddings.
##
## The embeddings are the static gene-token representations learnt during scGPT
## pretraining, extracted once by analysis/python/01_extract_scgpt_gene_embeddings.R
## and cached. They are independent of GSE194378: no expression data pass through
## the network and nothing is fine-tuned. They are external information about
## which genes are related, and nothing more.
##
## Pipeline, following the published gene-embedding workflow:
##   embeddings -> L2 normalisation -> cosine k nearest neighbours
##             -> Leiden communities -> one group per gene
##
## The graph construction is deliberately kept simple and is fixed before any
## model is fitted. Group structure is never tuned against held-out performance;
## the resolution is chosen by a prespecified rule that only looks at how many
## communities come out, as the analysis plan requires.
##
## Runtime: seconds.
##
## Run with:
##   Rscript analysis/R/03_build_fm_groups.R

source(here::here("analysis", "R", "00_setup.R"))

suppressPackageStartupMessages(library(igraph))

K_NEIGHBOURS <- 15L

## The analysis plan asks for roughly 10 to 30 groups at this panel size. The
## resolution is picked from a fixed grid by taking the value whose community
## count is closest to the middle of that range, with ties broken towards the
## coarser (smaller) resolution. This is a rule about group counts, not about
## model performance.
RESOLUTION_GRID <- seq(0.2, 3.0, by = 0.1)
TARGET_N_GROUPS <- 20L

panel <- readRDS(path_data_processed("02_gene_panel.rds"))

## 1. Embeddings ---------------------------------------------------------------

emb_raw <- utils::read.csv(path_embeddings("03_scgpt_panel_embeddings.csv"),
                           stringsAsFactors = FALSE)

## The panel order is the reference order for everything downstream, so the
## embedding rows must line up with it exactly rather than approximately.
stopifnot(identical(emb_raw$row_id, panel$row_id))

E <- as.matrix(emb_raw[, setdiff(names(emb_raw), "row_id")])
rownames(E) <- panel$row_id
stopifnot(all(is.finite(E)))

## L2 normalisation, so that the inner product is the cosine similarity.
E_norm <- E / sqrt(rowSums(E^2))

## 2. Cosine nearest-neighbour graph -------------------------------------------

S <- tcrossprod(E_norm)
diag(S) <- -Inf   # never let a gene be its own neighbour

p <- nrow(S)

## Each gene proposes its K nearest neighbours; the graph is the union of those
## proposals, so a gene that is nobody else's neighbour still keeps its own
## edges and no gene can end up isolated.
edges <- do.call(rbind, lapply(seq_len(p), function(i) {
  nb <- order(S[i, ], decreasing = TRUE)[seq_len(K_NEIGHBOURS)]
  cbind(i, nb, S[i, nb])
}))

## Negative-similarity edges would assert that two genes belong together on the
## strength of pointing in opposite directions, so they are dropped. At this k
## none normally occur; the filter documents the intent.
edges <- edges[edges[, 3] > 0, , drop = FALSE]

g <- igraph::graph_from_data_frame(
  data.frame(from = rownames(S)[edges[, 1]],
             to = rownames(S)[edges[, 2]],
             weight = edges[, 3], stringsAsFactors = FALSE),
  directed = FALSE,
  vertices = data.frame(name = rownames(S), stringsAsFactors = FALSE)
)
g <- igraph::simplify(g, edge.attr.comb = list(weight = "max"))

graph_summary <- data.frame(
  item = c("Genes (nodes)", "Edges", "Median degree", "Isolated genes",
           "Connected components"),
  value = c(igraph::vcount(g), igraph::ecount(g),
            stats::median(igraph::degree(g)), sum(igraph::degree(g) == 0),
            igraph::components(g)$no),
  stringsAsFactors = FALSE
)

## 3. Leiden communities -------------------------------------------------------

## Leiden is randomised, so the seed is fixed and recorded.
community_at <- function(resolution) {
  set.seed(SEEDS$community)
  igraph::cluster_leiden(g, objective_function = "modularity",
                         weights = igraph::E(g)$weight,
                         resolution_parameter = resolution, n_iterations = 10L)
}

resolution_scan <- data.frame(
  resolution = RESOLUTION_GRID,
  n_groups = vapply(RESOLUTION_GRID,
                    function(r) length(unique(igraph::membership(community_at(r)))),
                    integer(1)),
  stringsAsFactors = FALSE
)

## Closest to the target count; ties go to the coarser resolution.
best <- which.min(abs(resolution_scan$n_groups - TARGET_N_GROUPS))
chosen_resolution <- resolution_scan$resolution[best]
comm <- community_at(chosen_resolution)

membership <- igraph::membership(comm)
stopifnot(identical(names(membership), panel$row_id))

## Groups are relabelled by decreasing size, so that group 1 is the largest and
## the labels do not depend on Leiden's internal ordering.
sizes <- sort(table(membership), decreasing = TRUE)
relabel <- stats::setNames(seq_along(sizes), names(sizes))
group_id <- unname(relabel[as.character(membership)])

fm_groups <- data.frame(
  position = panel$position,
  row_id = panel$row_id,
  entrez_id = panel$entrez_id,
  symbol = panel$symbol,
  group = factor(sprintf("FM_%02d", group_id),
                 levels = sprintf("FM_%02d", seq_along(sizes))),
  source = "scGPT",
  stringsAsFactors = FALSE
)

## The gate for this stage: every panel gene carries a valid group.
stopifnot(nrow(fm_groups) == nrow(panel),
          !anyNA(fm_groups$group),
          identical(fm_groups$row_id, panel$row_id))

saveRDS(fm_groups, path_groups("03_fm_groups.rds"))
utils::write.csv(fm_groups, path_groups("03_fm_groups.csv"), row.names = FALSE)

## 4. Diagnostics --------------------------------------------------------------

group_sizes <- as.data.frame(table(fm_groups$group), stringsAsFactors = FALSE)
names(group_sizes) <- c("group", "n_genes")

## Whether the communities actually correspond to higher similarity than the
## graph at large. If they did not, the grouping would carry no information.
within <- outer(group_id, group_id, "==")
diag(within) <- NA
S_plain <- tcrossprod(E_norm)
diag(S_plain) <- NA
similarity_check <- data.frame(
  item = c("Mean cosine similarity, same group",
           "Mean cosine similarity, different group"),
  value = round(c(mean(S_plain[which(within)], na.rm = TRUE),
                  mean(S_plain[which(!within)], na.rm = TRUE)), 4),
  stringsAsFactors = FALSE
)

## A few genes per group, as a readable handle on what each group contains.
group_examples <- do.call(rbind, lapply(levels(fm_groups$group), function(grp) {
  members <- fm_groups$symbol[fm_groups$group == grp]
  data.frame(group = grp, n_genes = length(members),
             examples = paste(utils::head(members, 8), collapse = ", "),
             stringsAsFactors = FALSE)
}))

parameters <- data.frame(
  item = c("Checkpoint", "Embedding dimension", "Neighbours per gene (k)",
           "Resolution grid", "Target group count", "Chosen resolution",
           "Groups", "Smallest group", "Largest group", "Leiden seed"),
  value = c("wanglab/scGPT-human (whole-human, CellxGene census May 2023)",
            ncol(E), K_NEIGHBOURS,
            sprintf("%.1f to %.1f by %.1f", min(RESOLUTION_GRID),
                    max(RESOLUTION_GRID), diff(RESOLUTION_GRID)[1]),
            TARGET_N_GROUPS, chosen_resolution,
            nlevels(fm_groups$group), min(group_sizes$n_genes),
            max(group_sizes$n_genes), SEEDS$community),
  stringsAsFactors = FALSE
)

utils::write.csv(parameters, path_metrics("03_fm_group_parameters.csv"), row.names = FALSE)
utils::write.csv(group_sizes, path_metrics("03_fm_group_sizes.csv"), row.names = FALSE)
utils::write.csv(group_examples, path_tables("03_fm_group_examples.csv"), row.names = FALSE)
utils::write.csv(graph_summary, path_metrics("03_fm_graph_summary.csv"), row.names = FALSE)
utils::write.csv(similarity_check, path_metrics("03_fm_similarity_check.csv"), row.names = FALSE)
utils::write.csv(resolution_scan, path_metrics("03_fm_resolution_scan.csv"), row.names = FALSE)
utils::write.csv(provenance(), path_metrics("00_provenance.csv"), row.names = FALSE)

save_progress_figure("03_fm_groups.png", {
  graphics::par(mfrow = c(1, 3), mar = c(4.5, 4.5, 3, 1))

  graphics::barplot(group_sizes$n_genes, names.arg = seq_len(nrow(group_sizes)),
                    col = "#2C7FB8", border = NA, las = 1,
                    xlab = "Group", ylab = "Genes",
                    main = "Group sizes")
  graphics::abline(h = 20, lty = 2, col = "grey40")

  graphics::par(pty = "s")
  graphics::plot(resolution_scan$resolution, resolution_scan$n_groups,
                 type = "o", pch = 16, cex = 0.6, col = "grey30",
                 xlab = "Leiden resolution", ylab = "Communities",
                 main = "Resolution and group count")
  graphics::abline(h = c(10, 30), lty = 3, col = "grey60")
  graphics::points(chosen_resolution, nlevels(fm_groups$group),
                   pch = 16, cex = 1.4, col = "#D95F02")
  graphics::par(pty = "m")

  graphics::hist(S_plain[which(!within)], breaks = 60, freq = FALSE,
                 col = grDevices::adjustcolor("grey60", 0.6), border = NA,
                 xlab = "Cosine similarity", main = "Within and between groups")
  graphics::hist(S_plain[which(within)], breaks = 60, freq = FALSE, add = TRUE,
                 col = grDevices::adjustcolor("#D95F02", 0.6), border = NA)
  graphics::legend("topright", fill = c("grey60", "#D95F02"), border = NA,
                   bty = "n", cex = 0.85,
                   legend = c("different group", "same group"))
}, width = 12, height = 4)

print(parameters, row.names = FALSE)
cat("\n"); print(graph_summary, row.names = FALSE)
cat("\n"); print(similarity_check, row.names = FALSE)
cat("\nGroups:\n"); print(group_examples, row.names = FALSE)
