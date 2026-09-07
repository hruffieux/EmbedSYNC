## Stage 7g: what the learnt programmes look like, and whether they track anything.
##
## Everything else compares conditions against each other. This asks a different
## question: do the dynamic factors bayesSYNC recovers correspond to anything
## about the subjects, and what do the fitted trajectories look like?
##
## Both the vanilla and the foundation-model fits are examined, from Stage 6,
## which retain the reconstructed trajectories and their credible bands. Stage
## 7d showed their posteriors to be nearly identical, so agreement between them
## here is a check rather than a surprise; a disagreement would have meant
## something was wrong with that conclusion.
##
## GSE194378 compares 33 individuals recovered from mild COVID-19 with 40 age-
## and sex-matched healthy controls, and the published analysis reports a
## sex-dimorphic imprint of prior infection on the vaccination response. Cohort,
## sex and their interaction are therefore covariates the design nominates, not
## ones chosen after looking. Age is included as the other matching variable.
##
## These are exploratory associations. The scores are posterior means treated as
## if observed, which ignores their estimation uncertainty; the p-values are
## unadjusted; and factor signs are arbitrary, so the direction of an
## association carries no meaning on its own. The amplitude of a subject's
## trajectory is reported alongside the signed score because it does not depend
## on the sign.
##
## Runtime: four or five minutes, almost all of it reading two 755 MB fits.
##
## Run with:
##   Rscript analysis/R/07g_interpret_programmes.R

source(here::here("analysis", "R", "00_setup.R"))

MODELS <- c(vanilla = "06_vanilla.rds", fm = "06_fm.rds")

## Two colour pairs, kept apart on purpose. Cohort is a property of the
## subjects; model is a property of the fit. Using one pair for both, as an
## earlier version did, invited the reader to compare across the wrong axis.
COHORT_COLOUR <- c(COVR = "#7B3294", HC = "#008837")     # purple / green
MODEL_COLOUR <- c(vanilla = "#D95F02", fm = "#2C7FB8")   # orange / blue, as elsewhere

dat <- readRDS(path_data_processed("01_gse194378_longitudinal.rds"))
panel <- readRDS(path_data_processed("02_gene_panel.rds"))
expr <- dat$expr
samples <- dat$samples

subject_meta <- unique(samples[, c("subject_id", "group", "Sex",
                                   "age.at.sample.drawn")])
subject_meta <- subject_meta[!duplicated(subject_meta$subject_id), ]
subject_meta$age <- as.numeric(subject_meta$age.at.sample.drawn)
rownames(subject_meta) <- subject_meta$subject_id

## 1. Extract what is needed from each fit ---------------------------------------

## Factor labels and signs are arbitrary, so the foundation-model fit is aligned
## to the vanilla one before anything is compared. With three active factors
## there are six permutations and the best is found exhaustively.
permutations <- function(n) {
  if (n == 1L) return(matrix(1L))
  sub <- permutations(n - 1L)
  do.call(rbind, lapply(seq_len(n), function(i) {
    cbind(i, matrix(ifelse(sub >= i, sub + 1L, sub), nrow = nrow(sub)))
  }))
}

align_to <- function(B_ref, B_new, active_ref, active_new) {
  cross <- stats::cor(B_ref[, active_ref, drop = FALSE],
                      B_new[, active_new, drop = FALSE])
  perms <- permutations(length(active_ref))
  best <- perms[which.max(apply(perms, 1, function(pm) {
    sum(abs(cross[cbind(seq_along(active_ref), pm)]))
  })), ]
  list(cols = active_new[best],
       signs = sign(cross[cbind(seq_along(active_ref), best)]))
}

reference <- NULL   # set from the vanilla fit, then used to align the other

#' Pull the latent trajectories, subject summaries and a few gene fits.
extract_model <- function(file, gene_rows, show_subjects) {
  fit <- readRDS(path_fits(file))
  active <- which(fit$factor_ppi > 0.5)
  subjects <- names(fit$Y)
  days <- time_to_day(fit$time_g)

  if (is.null(reference)) {
    cols <- active
    signs <- rep(1, length(active))
  } else {
    al <- align_to(reference$B, fit$B_hat, reference$active, active)
    cols <- al$cols
    signs <- al$signs
  }

  latent <- lapply(seq_along(cols), function(qi) {
    signs[qi] * vapply(seq_along(subjects),
                       function(i) fit$list_h_hat[[i]][[cols[qi]]],
                       numeric(length(days)))
  })

  ## Reconstructions for a handful of genes and subjects, with their bands, on
  ## the original scale.
  gene_fits <- lapply(gene_rows, function(gene) {
    j <- match(gene, panel$row_id)
    unscale <- function(v) v * fit$sd_mean_across_subjects[j] +
      fit$mean_mean_across_subjects[j]
    lapply(show_subjects, function(s) {
      i <- match(s, subjects)
      list(hat = unscale(fit$list_Y_hat[[i]][[j]]),
           low = unscale(fit$list_Y_low[[i]][[j]]),
           upp = unscale(fit$list_Y_upp[[i]][[j]]))
    })
  })
  names(gene_fits) <- gene_rows

  out <- list(active = active, cols = cols, signs = signs, days = days,
              subjects = subjects, latent = latent, gene_fits = gene_fits,
              B = fit$B_hat, ppi = fit$ppi,
              pve = vapply(fit$list_cumulated_pve[cols], function(x) x[1], numeric(1)))
  rm(fit)
  gc(verbose = FALSE)
  out
}

## The genes shown are those loading most strongly on each of vanilla's active
## factors, and the same genes are used for both models so the two fits can be
## drawn on one pair of axes.
van_head <- readRDS(path_fits(MODELS[["vanilla"]]))
active_v <- which(van_head$factor_ppi > 0.5)
top_genes <- vapply(active_v, function(q) panel$row_id[which.max(abs(van_head$B_hat[, q]))],
                    character(1))
subjects <- names(van_head$Y)
meta <- subject_meta[subjects, ]
show_subjects <- c(subjects[meta$group == "COVR"][1:2], subjects[meta$group == "HC"][1:2])
reference <- list(B = van_head$B_hat, active = active_v)
rm(van_head); gc(verbose = FALSE)

fits <- lapply(names(MODELS), function(m) {
  message(sprintf("[%s] reading", m))
  extract_model(MODELS[[m]], top_genes, show_subjects)
})
names(fits) <- names(MODELS)

## 2. Subject summaries and associations ------------------------------------------

subject_summary <- function(H, days) {
  data.frame(
    score = H[which.min(abs(days - 1)), ],   # value at the day 1 visit
    amplitude = apply(H, 2, function(h) diff(range(h))),
    stringsAsFactors = FALSE
  )
}

scores <- do.call(rbind, lapply(names(fits), function(m) {
  f <- fits[[m]]
  do.call(rbind, lapply(seq_along(f$latent), function(qi) {
    s <- subject_summary(f$latent[[qi]], f$days)
    data.frame(model = m, factor = sprintf("factor_%d", qi),
               subject_id = f$subjects,
               meta[, c("group", "Sex", "age")], s,
               stringsAsFactors = FALSE)
  }))
}))
rownames(scores) <- NULL

test_association <- function(values, covariate, name) {
  ok <- !is.na(values) & !is.na(covariate)
  values <- values[ok]; covariate <- covariate[ok]
  if (length(unique(covariate)) < 2 || length(values) < 10) return(NULL)
  if (is.numeric(covariate)) {
    ct <- stats::cor.test(values, covariate, method = "spearman", exact = FALSE)
    data.frame(covariate = name, test = "Spearman",
               statistic = round(unname(ct$estimate), 3),
               p_value = signif(ct$p.value, 3), n = length(values),
               stringsAsFactors = FALSE)
  } else {
    wt <- stats::wilcox.test(values ~ factor(covariate))
    data.frame(covariate = name, test = "Wilcoxon",
               statistic = round(2 * unname(wt$statistic) /
                                   prod(table(covariate)) - 1, 3),
               p_value = signif(wt$p.value, 3), n = length(values),
               stringsAsFactors = FALSE)
  }
}

associations <- do.call(rbind, lapply(unique(scores$model), function(m) {
  do.call(rbind, lapply(unique(scores$factor), function(f) {
    d <- scores[scores$model == m & scores$factor == f, ]
    covariates <- list(cohort = d$group, sex = d$Sex, age = d$age)
    do.call(rbind, lapply(c("score", "amplitude"), function(summary_name) {
      out <- do.call(rbind, lapply(names(covariates), function(nm) {
        test_association(d[[summary_name]], covariates[[nm]], nm)
      }))
      if (is.null(out)) return(NULL)
      cbind(model = m, factor = f, summary = summary_name, out)
    }))
  }))
}))
rownames(associations) <- NULL
associations <- associations[order(associations$p_value), ]

## A difference between two stratified tests is not a test of a difference, so
## the sex-dimorphic question is asked directly, as the interaction between
## cohort and sex in a model that also adjusts for the other matching variable.
interaction_tests <- do.call(rbind, lapply(unique(scores$model), function(m) {
  do.call(rbind, lapply(unique(scores$factor), function(f) {
    do.call(rbind, lapply(c("score", "amplitude"), function(summary_name) {
      d <- scores[scores$model == m & scores$factor == f, ]
      d$y <- d[[summary_name]]
      mod <- stats::lm(y ~ group * Sex + age, data = d)
      co <- summary(mod)$coefficients
      term <- grep(":", rownames(co), value = TRUE)[1]
      data.frame(model = m, factor = f, summary = summary_name,
                 estimate = round(co[term, "Estimate"], 4),
                 p_value = signif(co[term, "Pr(>|t|)"], 3),
                 stringsAsFactors = FALSE)
    }))
  }))
}))

## A factor separating the sexes might simply be carrying sex-chromosome genes,
## which would make the association a fact about the panel.
SEX_GENES <- c("XIST", "TSIX", "RPS4Y1", "DDX3Y", "KDM5D", "UTY", "USP9Y",
               "EIF1AY", "NLGN4Y", "ZFY", "TXLNGY")
sex_gene_check <- data.frame(
  item = "Sex-chromosome marker genes in the 1,000-gene panel",
  value = sum(SEX_GENES %in% panel$symbol),
  stringsAsFactors = FALSE
)

## How closely the two models agree on the same subjects.
agreement <- do.call(rbind, lapply(unique(scores$factor), function(f) {
  a <- scores[scores$model == "vanilla" & scores$factor == f, ]
  b <- scores[scores$model == "fm" & scores$factor == f, ]
  b <- b[match(a$subject_id, b$subject_id), ]
  data.frame(factor = f,
             score_correlation = round(stats::cor(a$score, b$score), 4),
             amplitude_correlation = round(stats::cor(a$amplitude, b$amplitude), 4),
             stringsAsFactors = FALSE)
}))

pve <- data.frame(
  model = rep(names(fits), each = length(fits[[1]]$pve)),
  factor = rep(sprintf("factor_%d", seq_along(fits[[1]]$pve)), length(fits)),
  pve_component_1 = round(unlist(lapply(fits, function(f) unname(f$pve))), 1),
  stringsAsFactors = FALSE
)

utils::write.csv(scores, path_metrics("07g_subject_scores.csv"), row.names = FALSE)
utils::write.csv(associations, path_metrics("07g_score_associations.csv"), row.names = FALSE)
utils::write.csv(interaction_tests, path_metrics("07g_interaction_tests.csv"), row.names = FALSE)
utils::write.csv(sex_gene_check, path_metrics("07g_sex_gene_check.csv"), row.names = FALSE)
utils::write.csv(agreement, path_metrics("07g_model_agreement.csv"), row.names = FALSE)
utils::write.csv(pve, path_metrics("07g_factor_pve.csv"), row.names = FALSE)
utils::write.csv(provenance(), path_metrics("00_provenance.csv"), row.names = FALSE)

## 3. Figures ----------------------------------------------------------------------

n_factors <- length(fits[[1]]$latent)

save_progress_figure("07g_latent_trajectories.png", {
  graphics::par(mfrow = c(length(fits), n_factors), mar = c(4.3, 4.5, 3.2, 1))
  for (m in names(fits)) {
    f <- fits[[m]]
    for (qi in seq_len(n_factors)) {
      H <- f$latent[[qi]]
      graphics::matplot(f$days, H, type = "l", lty = 1, lwd = 0.6,
                        col = grDevices::adjustcolor(COHORT_COLOUR[meta$group], 0.3),
                        xlab = "Day relative to vaccination",
                        ylab = "Latent factor value",
                        main = sprintf("%s model, factor %d", m, qi))
      for (grp in names(COHORT_COLOUR)) {
        graphics::lines(f$days, rowMeans(H[, meta$group == grp, drop = FALSE]),
                        col = COHORT_COLOUR[grp], lwd = 3)
      }
      graphics::abline(v = c(0, 1, 7), lty = 3, col = "grey50")
      if (qi == 1) {
        graphics::legend("topleft", bty = "n", cex = 0.8, lwd = 3,
                         col = COHORT_COLOUR, legend = names(COHORT_COLOUR))
      }
    }
  }
}, width = 12, height = 8)

save_progress_figure("07g_scores_by_cohort.png", {
  graphics::par(mfrow = c(length(fits), n_factors), mar = c(5.2, 4.5, 3.2, 1))
  for (m in names(fits)) {
    for (qi in seq_len(n_factors)) {
      f <- sprintf("factor_%d", qi)
      d <- scores[scores$model == m & scores$factor == f, ]
      d$key <- paste(d$group, d$Sex, sep = "\n")
      p_int <- interaction_tests$p_value[interaction_tests$model == m &
                                           interaction_tests$factor == f &
                                           interaction_tests$summary == "score"]
      graphics::boxplot(score ~ key, data = d, las = 1, xlab = "",
                        ylab = "Factor value at day 1", outline = FALSE,
                        border = "grey30",
                        col = COHORT_COLOUR[sub("\n.*", "", sort(unique(d$key)))],
                        main = sprintf("%s model, factor %d\ncohort x sex p = %s",
                                       m, qi, format(p_int, digits = 2)),
                        cex.main = 0.95)
      graphics::stripchart(score ~ key, data = d, vertical = TRUE, add = TRUE,
                           method = "jitter", jitter = 0.15, pch = 16, cex = 0.6,
                           col = grDevices::adjustcolor("grey20", 0.6))
    }
  }
}, width = 12, height = 8)

## Do the two models place the same subjects in the same places?
save_progress_figure("07g_model_agreement.png", {
  graphics::par(mfrow = c(1, n_factors), mar = c(4.5, 4.5, 3.2, 1), pty = "s")
  for (qi in seq_len(n_factors)) {
    f <- sprintf("factor_%d", qi)
    a <- scores[scores$model == "vanilla" & scores$factor == f, ]
    b <- scores[scores$model == "fm" & scores$factor == f, ]
    b <- b[match(a$subject_id, b$subject_id), ]
    lim <- range(c(a$score, b$score))
    graphics::plot(a$score, b$score, pch = 16, cex = 0.9,
                   col = grDevices::adjustcolor(COHORT_COLOUR[a$group], 0.75),
                   xlim = lim, ylim = lim,
                   xlab = "Vanilla model", ylab = "Foundation-model grouping",
                   main = sprintf("Factor %d subject scores\nr = %.4f", qi,
                                  stats::cor(a$score, b$score)))
    graphics::abline(0, 1, lty = 2, col = "grey40")
  }
}, width = 12, height = 4.6)

## Gene-level reconstructions, both models on one pair of axes.
save_progress_figure("07g_gene_trajectories.png", {
  graphics::par(mfcol = c(length(top_genes), length(show_subjects)),
                mar = c(4, 4.2, 2.8, 0.8))
  for (s in show_subjects) {
    rows <- samples[samples$subject_id == s, ]
    rows <- rows[order(rows$day), ]
    si <- match(s, show_subjects)

    for (gi in seq_along(top_genes)) {
      gene <- top_genes[gi]
      j <- match(gene, panel$row_id)
      obs <- as.numeric(expr[gene, rows$library_id])

      curves <- lapply(names(fits), function(m) fits[[m]]$gene_fits[[gene]][[si]])
      names(curves) <- names(fits)
      yl <- range(c(unlist(curves), obs))

      graphics::plot(fits[[1]]$days, curves[[1]]$hat, type = "n", ylim = yl,
                     xlab = "Day", ylab = "Expression",
                     main = sprintf("%s, %s (%s)", panel$symbol[j], s,
                                    meta$group[match(s, subjects)]),
                     cex.main = 0.9)
      for (m in names(curves)) {
        graphics::polygon(c(fits[[m]]$days, rev(fits[[m]]$days)),
                          c(curves[[m]]$low, rev(curves[[m]]$upp)), border = NA,
                          col = grDevices::adjustcolor(MODEL_COLOUR[m], 0.18))
      }
      for (m in names(curves)) {
        graphics::lines(fits[[m]]$days, curves[[m]]$hat,
                        col = MODEL_COLOUR[m], lwd = 2)
      }
      graphics::points(rows$day, obs, pch = 16, cex = 0.9, col = "grey10")
      if (gi == 1 && si == 1) {
        graphics::legend("topright", bty = "n", cex = 0.75, lwd = 2,
                         col = MODEL_COLOUR, legend = names(MODEL_COLOUR))
      }
    }
  }
}, width = 11, height = 8)

cat("\nVariance explained by the first spline component:\n")
print(pve, row.names = FALSE)
cat("\nCohort by sex interaction:\n"); print(interaction_tests, row.names = FALSE)
cat("\nAgreement between the two models:\n"); print(agreement, row.names = FALSE)
cat("\nSex-chromosome genes:\n"); print(sex_gene_check, row.names = FALSE)
cat("\nStrongest associations (unadjusted, exploratory):\n")
print(utils::head(associations, 8), row.names = FALSE)
cat("\nGenes shown:", panel$symbol[match(top_genes, panel$row_id)], "\n")
