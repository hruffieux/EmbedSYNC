#' bayesSYNCfm: group-informed high-dimensional functional factor analysis of shared latent dynamics
#'
#' High-dimensional factor model based on functional principal component
#' analysis (FPCA) using variational inference.
#'
#' bayesSYNCfm is a derivative of the bayesSYNC package, developed for the
#' EmbedSYNC project. It extends the spike-and-slab prior on the loading
#' inclusion indicators so that variables assigned to the same externally
#' defined group share a group- and factor-specific inclusion probability.
#' The likelihood, temporal basis, FPCA representation and slab distribution
#' are unchanged. With no external grouping supplied, the model reduces to the
#' original factor-specific prior.
#'
#' The package is installed under its own name so that it can coexist with
#' bayesSYNC; the exported function names are shared, so call them as
#' \code{bayesSYNCfm::bayesSYNC()} when both packages are loaded.
#'
#' @name bayesSYNCfm-package
#' @aliases bayesSYNCfm
#' @importFrom ellipse ellipse
#' @import lattice
# #' @importFrom lattice bwplot, panel.abline, panel.bwplot, strip.default, xyplot
#' @importFrom graphics legend lines par abline axis points
#' @importFrom gtools permutations
#' @importFrom magic adiag
#' @importFrom MASS mvrnorm
#' @importFrom matrixcalc duplication.matrix
#' @importFrom matrixStats colProds colSds
#' @importFrom pracma blkdiag
#' @importFrom splines spline.des
#' @importFrom stats var cov cor dnorm median pnorm qnorm quantile rbinom rnorm runif setNames
#' @importFrom utils read.table
NULL
