# =============================================================================
# 2b-plsc-reg-boot.R - LMEs on the PLSC latent scores
# -----------------------------------------------------------------------------
# For each PLSC (rni, rnd) and each dimension folder made by 2a, models each
# latent score (score_lx = rs-FC side, score_ly = RNI/RND side) on each Year 4
# reward / emotion regulation / executive function measure:
#
#   score ~ measure + covariates + (1 | site_id_l / rel_family_id)
#
# Output (in plsc-<block>/regression/):
#   dim<k>/lme_dim<k>_<score>_<measure>_table.csv   full coefficient table
#   plsc-reg-boot-dim<k>-results.csv                 one row per model
# These are the primary (confirmatory) tests. FDR is applied across measures
# within each score.
# =============================================================================
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "config.R"))
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "lme-helpers.R"))

score_vars <- c("score_lx", "score_ly")

for (block in blocks_to_run()) {
  reg_dir <- plsc_dirs(block)$reg
  dims <- sort(list.files(reg_dir, pattern = "^dim[0-9]+$"))
  message(sprintf("\n=== PLSC rs-FC x %s: %d dimension(s) ===", toupper(block), length(dims)))
  if (length(dims) == 0) { message("  nothing in ", reg_dir, " - run 2a-build-reg-data.R first"); next }

  for (dim in dims) {
    data_path <- file.path(reg_dir, dim, sprintf("lme_%s_data.csv", dim))
    if (!file.exists(data_path)) { message("  not found: ", data_path); next }
    data <- read.csv(data_path, check.names = FALSE)
    predictors <- usable_predictors(data)

    results <- NULL
    for (score in score_vars) for (pv in predictors) {
      message(sprintf("  %s %s ~ %s", dim, score, pv))
      tbl <- file.path(reg_dir, dim, sprintf("lme_%s_%s_%s_table.csv", dim, score, pv))
      results <- rbind(results, cbind(plsc = block, dimension = dim,
                                      fit_one_lme(data, score, pv, save_table = tbl)))
    }
    if (!is.null(results) && nrow(results) > 0) {
      results <- add_flags(results, fdr_by = "outcome")
      out <- file.path(reg_dir, sprintf("plsc-reg-boot-%s-results.csv", dim))
      write.csv(results, out, row.names = FALSE)
      message("Wrote ", out)
    }
  }
}
