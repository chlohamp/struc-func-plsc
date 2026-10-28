# =============================================================================
# 2b-plsc-reg-corr.R - LMEs on the individual significant brain features
# -----------------------------------------------------------------------------
# For each PLSC (rni, rnd) and dimension, takes the rs-FC connections and
# RNI/RND regions with |bootstrap ratio| > br_threshold (listed by 2a) and
# models each one on each Year 4 reward / ER / EF measure:
#
#   feature ~ measure + covariates + (1 | site_id_l / rel_family_id)
#
# Output (in plsc-<block>/regression/):
#   dim<k>/feat_<feature>_<measure>_table.csv
#   plsc-reg-corr-dim<k>-results.csv
#   plsc-reg-corr-results-all.csv
# These are exploratory follow-ups; FDR is applied across features per measure.
# =============================================================================
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "config.R"))
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "lme-helpers.R"))

for (block in blocks_to_run()) {
  reg_dir <- plsc_dirs(block)$reg
  dims <- sort(list.files(reg_dir, pattern = "^dim[0-9]+$"))
  message(sprintf("\n=== PLSC rs-FC x %s: %d dimension(s) ===", toupper(block), length(dims)))
  if (length(dims) == 0) { message("  nothing in ", reg_dir, " - run 2a-build-reg-data.R first"); next }

  # Short label for file names (ABCD names are long)
  short <- function(x) sub(paste0("^(", rsfc_block$prefix, "|", struct_blocks[[block]]$prefix, ")"), "", x)

  all_results <- NULL
  for (dim in dims) {
    flist_path <- file.path(reg_dir, dim, sprintf("features_%s_list.csv", dim))
    data_path  <- file.path(reg_dir, dim, sprintf("features_%s_data.csv", dim))
    if (!file.exists(flist_path)) { message("  not found: ", flist_path); next }
    flist <- read.csv(flist_path, check.names = FALSE)
    if (nrow(flist) == 0) { message(sprintf("  %s: no features above |BR| > %.1f - skipping", dim, br_threshold)); next }
    data <- read.csv(data_path, check.names = FALSE)
    predictors <- usable_predictors(data)
    message(sprintf("  %s: %d features x %d measures", dim, nrow(flist), length(predictors)))

    dim_results <- NULL
    for (i in seq_len(nrow(flist))) {
      feature <- flist$feature[i]
      data$.feature <- data[[feature]]   # syntactic name for the lmer formula
      for (pv in predictors) {
        tbl <- file.path(reg_dir, dim, sprintf("feat_%s_%s_table.csv", short(feature), pv))
        r <- fit_one_lme(data, ".feature", pv, save_table = tbl)
        r$outcome <- feature
        dim_results <- rbind(dim_results, cbind(plsc = block, dimension = dim, block = flist$block[i],
                                                bootstrap_ratio = flist$bootstrap_ratio[i], r))
      }
    }
    dim_results <- add_flags(dim_results, fdr_by = "predictor")
    out <- file.path(reg_dir, sprintf("plsc-reg-corr-%s-results.csv", dim))
    write.csv(dim_results, out, row.names = FALSE)
    message("Wrote ", out)
    all_results <- rbind(all_results, dim_results)
  }
  if (!is.null(all_results)) {
    out <- file.path(reg_dir, "plsc-reg-corr-results-all.csv")
    write.csv(all_results, out, row.names = FALSE)
    message("Wrote ", out)
  }
}
