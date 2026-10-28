# =============================================================================
# 2c-plsc-puberty.R - puberty and the PLSC latent scores
# -----------------------------------------------------------------------------
# For each PLSC (rni, rnd) and significant dimension, using the data built by
# 2a (latent scores + covariates + Year 4 measures + puberty):
#
#  (A) Does puberty predict how strongly a youth expresses a coupling pattern?
#        score ~ puberty_var + puberty_var:sex + covariates (incl. age, sex)
#        for puberty_var in pds_stage, pds_tempo, pds_timing
#      Hypothesis: effects in the RNI PLSC, little or none in the RND PLSC.
#
#  (B) Does puberty moderate the brain-behaviour links?
#        score ~ measure * pds_stage + covariates
#      run in everyone, and (if puberty_by_sex) separately in girls and boys.
#
# Latent scores come from age-residualized brain data and age is also a
# covariate here, so puberty effects are net of age.
#
# Output (plsc-<block>/regression/):
#   plsc-puberty-main-dim<k>-results.csv        (A)
#   plsc-puberty-moderation-dim<k>-results.csv  (B)
# =============================================================================
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "config.R"))
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "lme-helpers.R"))

score_vars <- c("score_lx", "score_ly")

for (block in blocks_to_run()) {
  reg_dir <- plsc_dirs(block)$reg
  dims <- sort(list.files(reg_dir, pattern = "^dim[0-9]+$"))
  message(sprintf("\n=== Puberty models, PLSC rs-FC x %s: %d dimension(s) ===", toupper(block), length(dims)))
  if (length(dims) == 0) { message("  nothing in ", reg_dir, " - run 2a-build-reg-data.R first"); next }

  for (dim in dims) {
    data <- read.csv(file.path(reg_dir, dim, sprintf("lme_%s_data.csv", dim)), check.names = FALSE)
    if (!puberty_moderator %in% colnames(data)) { message("  no puberty columns - was puberty.csv made by 1a?"); next }

    # (A) puberty -> latent scores
    resA <- NULL
    for (score in score_vars) for (pv in intersect(puberty_vars, colnames(data))) {
      r <- fit_lme_terms(data, score, terms = c(pv, paste0(pv, ":demo_sex_v2")),
                         focal = c(pv, paste0(pv, ":demo_sex_v2")), scale_vars = pv)
      resA <- rbind(resA, cbind(plsc = block, dimension = dim, puberty_var = pv, r))
    }
    resA$p_fdr <- ave(resA$p_value, resA$term, FUN = function(p) p.adjust(p, "fdr"))
    outA <- file.path(reg_dir, sprintf("plsc-puberty-main-%s-results.csv", dim))
    write.csv(resA, outA, row.names = FALSE); message("Wrote ", outA)

    # (B) measure x puberty moderation (all, then by sex)
    groups <- list(all = rep(TRUE, nrow(data)))
    if (puberty_by_sex) for (s in sort(unique(na.omit(data$demo_sex_v2))))
      groups[[paste0("sex_", s)]] <- !is.na(data$demo_sex_v2) & data$demo_sex_v2 == s
    resB <- NULL
    for (g in names(groups)) {
      dsub <- data[groups[[g]], ]
      for (score in score_vars) for (pv in usable_predictors(dsub)) {
        r <- fit_lme_terms(dsub, score,
                           terms = c(pv, puberty_moderator, paste0(pv, ":", puberty_moderator)),
                           focal = c(pv, puberty_moderator, paste0(pv, ":", puberty_moderator)),
                           scale_vars = c(pv, puberty_moderator),
                           drop_covars = if (g == "all") character(0) else "demo_sex_v2")
        r$domain <- lme_predictor_map[[pv]]$domain
        resB <- rbind(resB, cbind(plsc = block, dimension = dim, group = g, measure = pv, r))
      }
    }
    # FDR across measures, separately for each group x score x term
    key <- paste(resB$group, resB$outcome, resB$term)
    resB$p_fdr <- ave(resB$p_value, key, FUN = function(p) p.adjust(p, "fdr"))
    resB$is_interaction <- grepl(":", resB$term)
    outB <- file.path(reg_dir, sprintf("plsc-puberty-moderation-%s-results.csv", dim))
    write.csv(resB, outB, row.names = FALSE); message("Wrote ", outB)
  }
}
