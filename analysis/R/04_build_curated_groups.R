## Stage 4a: build curated gene groups from Reactome pathway membership.
##
## This is the comparator that asks whether a foundation model adds anything
## over established curated biology. It must therefore differ from the
## foundation-model groups in its source of similarity and in nothing else, so
## the graph construction, the community algorithm, the resolution rule and the
## seed are all the same as in 03_build_fm_groups.R.
##
## Pipeline:
##   Reactome membership -> gene-gene Jaccard -> k nearest neighbours
##                       -> Leiden communities -> one group per gene
##
## Two points of care, both from the analysis plan. Similarity is computed on
## the pathway sets of each gene, so genes sharing no pathway have similarity
## exactly zero, and no edge is created between them: a nearest-neighbour rule
## applied blindly would invent relationships where Reactome asserts none.
## Isolated genes are then inspected explicitly rather than assumed away.
##
## Runtime: seconds.
##
## Run with:
##   Rscript analysis/R/04_build_curated_groups.R

source(here::here("analysis", "R", "00_setup.R"))

suppressPackageStartupMessages({
  library(igraph)
  library(reactome.db)
})

## Matched to the foundation-model groups, so the comparison is about the
## information source and not about how the graph was built.
K_NEIGHBOURS <- 15L
RESOLUTION_GRID <- seq(0.2, 3.0, by = 0.1)
TARGET_N_GROUPS <- 20L

panel <- readRDS(path_data_processed("02_gene_panel.rds"))

## 1. Pathway membership -------------------------------------------------------

entrez_to_pathway <- as.list(reactomeEXTID2PATHID)
pathways <- lapply(panel$entrez_id, function(id) {
  p <- entrez_to_pathway[[id]]
  if (is.null(p)) character(0) else unique(p[grepl("^R-HSA-", p)])
})
names(pathways) <- panel$row_id

## The panel required Reactome annotation, so this should hold by construction.
stopifnot(all(lengths(pathways) > 0L))

## 2. Jaccard similarity between genes -----------------------------------------

## Computed through a gene-by-pathway incidence matrix: the intersection counts
## are one crossproduct, and the union follows from the row sums.
all_paths <- sort(unique(unlist(pathways)))
incidence <- matrix(0L, nrow = nrow(panel), ncol = length(all_paths),
                    dimnames = list(panel$row_id, all_paths))
for (i in seq_along(pathways)) {
  incidence[i, pathways[[i]]] <- 1L
}

intersection <- tcrossprod(incidence)
n_paths <- rowSums(incidence)
union_counts <- outer(n_paths, n_paths, "+") - intersection

S <- intersection / union_counts
diag(S) <- -Inf   # never a gene's own neighbour

## 3. Nearest-neighbour graph --------------------------------------------------

p <- nrow(S)
edges <- do.call(rbind, lapply(seq_len(p), function(i) {
  nb <- order(S[i, ], decreasing = TRUE)[seq_len(K_NEIGHBOURS)]
  cbind(i, nb, S[i, nb])
}))

## Genes sharing no pathway have Jaccard exactly zero. Keeping such an edge
## would assert a relationship Reactome does not support, so they are dropped
## even though that leaves some genes with fewer than k neighbours.
edges <- edges[edges[, 3] > 0, , drop = FALSE]

g <- igraph::graph_from_data_frame(
  data.frame(from = rownames(S)[edges[, 1]],
             to = rownames(S)[edges[, 2]],
             weight = edges[, 3], stringsAsFactors = FALSE),
  directed = FALSE,
  vertices = data.frame(name = rownames(S), stringsAsFactors = FALSE)
)
g <- igraph::simplify(g, edge.attr.comb = list(weight = "max"))

isolated <- names(which(igraph::degree(g) == 0))

graph_summary <- data.frame(
  item = c("Genes (nodes)", "Edges", "Median degree", "Isolated genes",
           "Connected components", "Largest component"),
  value = c(igraph::vcount(g), igraph::ecount(g),
            stats::median(igraph::degree(g)), length(isolated),
            igraph::components(g)$no, max(igraph::components(g)$csize)),
  stringsAsFactors = FALSE
)

## 4. Communities --------------------------------------------------------------

community_at <- function(resolution) {
  set.seed(SEEDS$community)
  igraph::cluster_leiden(g, objective_function = "modularity",
                         weights = igraph::E(g)$weight,
                         resolution_parameter = resolution, n_iterations = 10L)
}

resolution_scan <- data.frame(
  resolution = RESOLUTION_GRID,
  n_groups = vapply(RESOLUTION_GRID, function(r) {
    m <- igraph::membership(community_at(r))
    ## Count only groups that are not lone genes, so the target refers to
    ## usable groups rather than to a count inflated by singletons.
    sum(table(m) > 1L)
  }, integer(1)),
  stringsAsFactors = FALSE
)

best <- which.min(abs(resolution_scan$n_groups - TARGET_N_GROUPS))
chosen_resolution <- resolution_scan$resolution[best]
comm <- community_at(chosen_resolution)
membership <- igraph::membership(comm)
stopifnot(identical(names(membership), panel$row_id))

## 5. Documented handling of genes Reactome cannot place -----------------------

## Genes with no positive-similarity neighbour, and genes left in communities of
## fewer than MIN_GROUP_SIZE, are collected into a single `unassigned` group
## rather than left as singletons. A group of one gene carries no pooling: its
## inclusion probability would be informed by a single Bernoulli draw, which is
## both useless and numerically awkward. Keeping them in one explicit group
## preserves the panel, and the analysis plan allows this rule.
MIN_GROUP_SIZE <- 5L

sizes_raw <- table(membership)
too_small <- names(sizes_raw)[sizes_raw < MIN_GROUP_SIZE]
unassigned <- unique(c(isolated, panel$row_id[as.character(membership) %in% too_small]))

keep <- !(panel$row_id %in% unassigned)
sizes <- sort(table(membership[keep]), decreasing = TRUE)
relabel <- stats::setNames(seq_along(sizes), names(sizes))

group_label <- rep(NA_character_, nrow(panel))
group_label[keep] <- sprintf("CUR_%02d", relabel[as.character(membership[keep])])
group_label[!keep] <- "CUR_unassigned"

group_levels <- c(sprintf("CUR_%02d", seq_along(sizes)),
                  if (any(!keep)) "CUR_unassigned")

curated_groups <- data.frame(
  position = panel$position,
  row_id = panel$row_id,
  entrez_id = panel$entrez_id,
  symbol = panel$symbol,
  group = factor(group_label, levels = group_levels),
  source = sprintf("Reactome (reactome.db %s)",
                   as.character(utils::packageVersion("reactome.db"))),
  stringsAsFactors = FALSE
)

stopifnot(nrow(curated_groups) == nrow(panel),
          !anyNA(curated_groups$group),
          identical(curated_groups$row_id, panel$row_id))

saveRDS(curated_groups, path_groups("04_curated_groups.rds"))
utils::write.csv(curated_groups, path_groups("04_curated_groups.csv"), row.names = FALSE)

## 6. Diagnostics --------------------------------------------------------------

group_sizes <- as.data.frame(table(curated_groups$group), stringsAsFactors = FALSE)
names(group_sizes) <- c("group", "n_genes")

group_id <- as.integer(curated_groups$group)
within <- outer(group_id, group_id, "==")
diag(within) <- NA
S_plain <- intersection / union_counts
diag(S_plain) <- NA
similarity_check <- data.frame(
  item = c("Mean Jaccard similarity, same group",
           "Mean Jaccard similarity, different group",
           "Gene pairs with zero Jaccard"),
  value = c(round(mean(S_plain[which(within)], na.rm = TRUE), 4),
            round(mean(S_plain[which(!within)], na.rm = TRUE), 4),
            round(mean(S_plain == 0, na.rm = TRUE), 3)),
  stringsAsFactors = FALSE
)

group_examples <- do.call(rbind, lapply(levels(curated_groups$group), function(grp) {
  members <- curated_groups$symbol[curated_groups$group == grp]
  data.frame(group = grp, n_genes = length(members),
             examples = paste(utils::head(members, 8), collapse = ", "),
             stringsAsFactors = FALSE)
}))

parameters <- data.frame(
  item = c("Source", "Pathways used", "Neighbours per gene (k)",
           "Zero-similarity edges", "Minimum group size",
           "Chosen resolution", "Groups", "Unassigned genes", "Leiden seed"),
  value = c(sprintf("Reactome via reactome.db %s",
                    as.character(utils::packageVersion("reactome.db"))),
            length(all_paths), K_NEIGHBOURS, "dropped", MIN_GROUP_SIZE,
            chosen_resolution, nlevels(curated_groups$group),
            sum(curated_groups$group == "CUR_unassigned"), SEEDS$community),
  stringsAsFactors = FALSE
)

utils::write.csv(parameters, path_metrics("04_curated_parameters.csv"), row.names = FALSE)
utils::write.csv(group_sizes, path_metrics("04_curated_group_sizes.csv"), row.names = FALSE)
utils::write.csv(graph_summary, path_metrics("04_curated_graph_summary.csv"), row.names = FALSE)
utils::write.csv(similarity_check, path_metrics("04_curated_similarity_check.csv"), row.names = FALSE)
utils::write.csv(group_examples, path_tables("04_curated_group_examples.csv"), row.names = FALSE)
utils::write.csv(provenance(), path_metrics("00_provenance.csv"), row.names = FALSE)

print(parameters, row.names = FALSE)
cat("\n"); print(graph_summary, row.names = FALSE)
cat("\n"); print(similarity_check, row.names = FALSE)
cat("\nGroups:\n"); print(group_examples, row.names = FALSE)
