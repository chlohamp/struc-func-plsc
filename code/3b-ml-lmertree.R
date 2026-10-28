# =============================================================================
# 3b-ml-lmertree.R - linear mixed-model trees (glmertree)
# -----------------------------------------------------------------------------
# Bridge between the LMEs and the random forest. For each PLSC (rni, rnd),
# significant dimension, latent score and Year 4 measure, fits
#
#   score ~ measure  |  (1 | site / family)  |  pds_stage + sex + age
#           ^ node model  ^ random effects       ^ partitioning variables
#
# The tree splits the sample only where the score~measure relationship
# (intercept and slope) differs significantly between subgroups, e.g.
# "slope is larger when pds_stage > 3". No split = no moderation. This keeps
# the site/family random effects of the LMEs while letting the data choose the
# moderator and its cut-point.
#
# Scores are first residualized on the covariates that are NOT partitioning
# variables (SES, motion, scanner), so the tree only sees puberty/sex/age.
# By default (tree_test = "slope") the trees only split when the SLOPE
# differs; differences in the level of the score by puberty are tested
# directly in 2c. Per-node intercepts/slopes (with SE and p) come from
# refitting the mixed model with node as a factor.
#
# Output (plsc-<block>/regression/):
#   lmertree-dim<k>-results.csv   one row per terminal node (rule, n, slope)
#   lmertree-dim<k>-summary.csv   one row per model (n nodes, split variables)
#   trees/<...>.png               plot for every model that split
# =============================================================================
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "config.R"))
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "lme-helpers.R"))
suppressPackageStartupMessages(library(glmertree))

score_vars <- c("score_lx", "score_ly")
resid_on <- setdiff(c(lme_numerical_covars, lme_categorical_covars), tree_partition_vars)

for (block in blocks_to_run()) {
  reg_dir <- plsc_dirs(block)$reg
  tree_dir <- file.path(reg_dir, "trees"); dir.create(tree_dir, showWarnings = FALSE)
  dims <- sort(list.files(reg_dir, pattern = "^dim[0-9]+$"))
  message(sprintf("\n=== Mixed-model trees, PLSC rs-FC x %s ===", toupper(block)))
  for (dim in dims) {
    data <- read.csv(file.path(reg_dir, dim, sprintf("lme_%s_data.csv", dim)), check.names = FALSE)
    if (!all(tree_partition_vars %in% colnames(data))) { message("  missing partitioning variables - skipped"); next }
    nodes <- NULL; summ <- NULL
    for (score in score_vars) for (pv in usable_predictors(data)) {
      cols <- unique(c(score, pv, tree_partition_vars, resid_on, "site_id_l", "rel_family_id"))
      d <- data[complete.cases(data[, cols]), cols]
      for (v in intersect(cols, lme_categorical_covars)) d[[v]] <- factor(d[[v]])
      d$y <- residuals(lm(reformulate(resid_on, score), data = d))
      d$x <- as.numeric(scale(d[[pv]]))
      minsize <- max(50, floor(tree_minsize_frac * nrow(d)))
      part <- paste(tree_partition_vars, collapse = " + ")
      fit <- NULL; re_used <- NA
      for (re in c("(1 | site_id_l/rel_family_id)", "(1 | site_id_l)")) {
        fit <- tryCatch(suppressWarnings(lmertree(as.formula(paste("y ~ x |", re, "|", part)), data = d,
                                                  alpha = tree_alpha, minsize = minsize, bonferroni = TRUE,
                                                  parm = if (tree_test == "slope") 2 else NULL)),
                        error = function(e) NULL)
        if (!is.null(fit)) { re_used <- re; break }
      }
      tag <- sprintf("%s_%s_%s", dim, score, pv)
      if (is.null(fit)) { summ <- rbind(summ, data.frame(plsc = block, dimension = dim, score = score, measure = pv,
                                                          N = nrow(d), n_terminal = NA, split_vars = "failed",
                                                          root_instability_p = NA, random_effects = NA)); next }
      tr <- fit$tree
      n_term <- partykit::width(tr)
      rules <- tryCatch(partykit:::.list.rules.party(tr), error = function(e) NULL)
      node_id <- predict(tr, newdata = d, type = "node")
      term_ids <- as.character(sort(unique(node_id)))
      # node-wise intercept and slope, same random effects as the tree
      d$.node <- factor(node_id, levels = as.integer(term_ids))
      nf <- if (n_term == 1) "y ~ x" else "y ~ 0 + .node + .node:x"
      m <- tryCatch(lmer(as.formula(paste(nf, "+", re_used)), data = d), error = function(e) NULL)
      ct <- if (is.null(m)) NULL else as.data.frame(coef(summary(m)))
      get <- function(rows, col) if (is.null(ct)) rep(NA_real_, length(rows)) else ct[rows, col]
      r_int <- if (n_term == 1) "(Intercept)" else paste0(".node", term_ids)
      r_slp <- if (n_term == 1) "x" else paste0(".node", term_ids, ":x")
      split_vars <- if (n_term == 1) "" else paste(tree_partition_vars[vapply(tree_partition_vars,
                         function(v) any(grepl(v, rules, fixed = TRUE)), logical(1))], collapse = ";")
      nodes <- rbind(nodes, data.frame(
        plsc = block, dimension = dim, score = score, measure = pv, node = term_ids,
        rule = if (n_term == 1 || is.null(rules)) "all participants" else unname(rules[term_ids]),
        n = as.integer(table(factor(node_id, levels = as.integer(term_ids)))),
        intercept = get(r_int, "Estimate"), slope = get(r_slp, "Estimate"),
        slope_se = get(r_slp, "Std. Error"), slope_p = get(r_slp, "Pr(>|t|)"), stringsAsFactors = FALSE))
      root_p <- tryCatch(partykit::info_node(partykit::node_party(tr))$p.value, error = function(e) NA_real_)
      summ <- rbind(summ, data.frame(plsc = block, dimension = dim, score = score, measure = pv, N = nrow(d),
                                     n_terminal = n_term, split_vars = split_vars,
                                     root_instability_p = if (length(root_p)) as.numeric(root_p)[1] else NA_real_,
                                     random_effects = re_used))
      if (n_term > 1) {
        png(file.path(tree_dir, paste0(tag, ".png")), width = 1600, height = 900, res = 130)
        plot(fit, which = "tree", main = paste(toupper(block), tag)); invisible(dev.off())
        message(sprintf("  %s: %d subgroups (split on %s)", tag, n_term, split_vars))
      }
    }
    write.csv(nodes, file.path(reg_dir, sprintf("lmertree-%s-results.csv", dim)), row.names = FALSE)
    # FDR across all trees of this dimension; only FDR-surviving splits should be interpreted
    summ$root_instability_p_fdr <- p.adjust(summ$root_instability_p, "fdr")
    summ$split_survives_fdr <- summ$n_terminal > 1 & summ$root_instability_p_fdr < 0.05
    write.csv(summ,  file.path(reg_dir, sprintf("lmertree-%s-summary.csv", dim)), row.names = FALSE)
    message(sprintf("  %s: %d models, %d split, %d splits survive FDR", dim, nrow(summ),
                    sum(summ$n_terminal > 1, na.rm = TRUE), sum(summ$split_survives_fdr, na.rm = TRUE)))
  }
}
