## Stage 3b: a picture of the foundation-model gene graph.
##
## 03_build_fm_groups.R decides the groups; this script only draws them, and
## writes no grouping of its own. It rebuilds the same nearest-neighbour graph
## from the cached embeddings, lays it out in two dimensions, and colours genes
## by the communities already saved.
##
## The layout is for reading, not for inference. Communities are found in the
## 512-dimensional embedding space through the graph, so two genes drawn close
## together are not necessarily neighbours, and the grouping does not depend on
## anything here.
##
## The layout uses uwot, which is a dependency of this script alone and of
## nothing that produces a result. A force-directed layout of the same graph
## does not separate the communities legibly, and UMAP with a cosine metric on
## the normalised embeddings is the layout the published gene-embedding workflow
## uses, so it is the fair picture of the representation being grouped.
##
## Marker genes are labelled to show whether the neighbourhood structure is
## biologically coherent. This is a check on the tensor, the LayerNorm and the
## vocabulary mapping: if the erythroid genes did not sit together, something in
## the extraction would be wrong.
##
## Runtime: under a minute.
##
## Run with:
##   Rscript analysis/R/03b_plot_fm_groups.R

source(here::here("analysis", "R", "00_setup.R"))

K_NEIGHBOURS <- 15L   # as in 03_build_fm_groups.R

## Marker sets chosen for being unambiguous, not for being well grouped: each is
## a textbook whole-blood programme whose members ought to be near one another
## in any sensible gene representation.
MARKERS <- list(
  Erythroid = c("ALAS2", "SLC4A1", "FECH", "BPGM", "SPTA1"),
  Interferon = c("IFIT1", "IFIT3", "IFIT2", "MX1", "OAS2"),
  `Plasma cell` = c("JCHAIN", "DERL3", "CD79A", "CD27"),
  Glucocorticoid = c("FKBP5", "ZBTB16", "PDK4"),
  Myeloid = c("LYZ", "S100A8", "S100A9", "FCN1")
)

panel <- readRDS(path_data_processed("02_gene_panel.rds"))
fm <- readRDS(path_groups("03_fm_groups.rds"))
stopifnot(identical(fm$row_id, panel$row_id))

emb_raw <- utils::read.csv(path_embeddings("03_scgpt_panel_embeddings.csv"),
                           stringsAsFactors = FALSE)
stopifnot(identical(emb_raw$row_id, panel$row_id))

E <- as.matrix(emb_raw[, setdiff(names(emb_raw), "row_id")])
rownames(E) <- panel$row_id
E_norm <- E / sqrt(rowSums(E^2))

## Two dimensions from the same representation and the same neighbourhood size
## the communities were found with.
set.seed(SEEDS$community)
layout_xy <- uwot::umap(E_norm, n_neighbors = K_NEIGHBOURS, metric = "cosine",
                        min_dist = 0.3, n_components = 2L, verbose = FALSE)
rownames(layout_xy) <- panel$row_id

## Cached so that anything else wanting this picture reuses the same layout
## rather than recomputing a different one.
saveRDS(layout_xy, path_embeddings("03b_umap_layout.rds"))

## Within-group and between-group cosine similarity, for the second panel.
group_id <- as.integer(fm$group)
same_group <- outer(group_id, group_id, "==")
S_plain <- tcrossprod(E_norm)
upper <- upper.tri(S_plain)
within <- S_plain[upper & same_group]
between <- S_plain[upper & !same_group]

marker_table <- do.call(rbind, lapply(names(MARKERS), function(set) {
  members <- MARKERS[[set]]
  rows <- fm[match(members, fm$symbol), ]
  data.frame(
    programme = set,
    genes = paste(members, collapse = ", "),
    groups = paste(sort(unique(as.character(rows$group))), collapse = ", "),
    same_group = length(unique(as.character(rows$group))) == 1L,
    stringsAsFactors = FALSE
  )
}))
utils::write.csv(marker_table, path_metrics("03b_marker_coherence.csv"), row.names = FALSE)

palette <- grDevices::hcl.colors(nlevels(fm$group), "Dark 3")

save_progress_figure("03b_fm_gene_graph.png", {
  graphics::layout(matrix(c(1, 1, 2), nrow = 1))
  ## Square region as well as equal data units, so distances read the same in
  ## both directions.
  graphics::par(mar = c(1, 1, 3, 1), pty = "s")

  graphics::plot(layout_xy, pch = 16, cex = 0.55, asp = 1,
                 col = grDevices::adjustcolor(palette[group_id], 0.75),
                 axes = FALSE, xlab = "", ylab = "",
                 main = sprintf("scGPT gene embeddings: %d genes, %d Leiden communities",
                                nrow(panel), nlevels(fm$group)))

  marker_symbols <- unlist(MARKERS, use.names = FALSE)
  idx <- match(marker_symbols, panel$symbol)
  graphics::points(layout_xy[idx, , drop = FALSE], pch = 21, cex = 1.1,
                   bg = palette[group_id[idx]], col = "grey20", lwd = 0.8)
  graphics::text(layout_xy[idx, 1], layout_xy[idx, 2], labels = marker_symbols,
                 cex = 0.62, pos = 3, offset = 0.28, col = "grey15")

  graphics::legend("topleft", bty = "n", cex = 0.75, pch = 21, pt.cex = 1.1,
                   pt.bg = "grey80", col = "grey20",
                   legend = "labelled: marker genes for five blood programmes")

  ## Communities are only useful if they correspond to genuinely higher
  ## similarity than the graph at large.
  graphics::par(mar = c(4.5, 4.5, 3, 1), pty = "m")
  d_within <- stats::density(within)
  d_between <- stats::density(between)
  graphics::plot(d_between, col = "grey50", lwd = 2,
                 xlim = range(c(d_within$x, d_between$x)),
                 ylim = c(0, max(d_within$y, d_between$y)),
                 xlab = "Cosine similarity", ylab = "Density",
                 main = "Similarity within\nand between groups")
  graphics::lines(d_within, col = "#2C7FB8", lwd = 2)
  graphics::legend("topright", bty = "n", cex = 0.8, lwd = 2,
                   col = c("#2C7FB8", "grey50"),
                   legend = c("same group", "different group"))
}, width = 13, height = 6.5)

cat("\nMarker coherence:\n"); print(marker_table, row.names = FALSE)
cat("\nMean cosine similarity, within groups:", round(mean(within), 4),
    " between groups:", round(mean(between), 4), "\n")
