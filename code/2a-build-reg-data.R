# =============================================================================
# 2a-build-reg-data.R - assemble per-dimension data for the LMEs
# -----------------------------------------------------------------------------
# Runs for each PLSC (rni, rnd; or just PLSC_BLOCK=rni). For each significant
# dimension (significant_dimensions.csv, or PLSC_DIMS=1,3) writes to
# plsc-<block>/regression/dim<k>/:
#
#   lme_dim<k>_data.csv        latent scores (score_lx = rs-FC side,
#                              score_ly = RNI/RND side) + covariates + Year 4
#                              reward / ER / EF measures
#   features_dim<k>_data.csv   raw values of every feature with |BR| > threshold
#   features_dim<k>_list.csv   which features those are, their block and BR
# =============================================================================
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "config.R"))

covar <- read.csv(file.path(deriv_dir, "covariate.csv"),    check.names = FALSE)
preds <- read.csv(file.path(deriv_dir, "lme-measures.csv"), check.names = FALSE)
rsfc  <- read.csv(file.path(deriv_dir, "clean-rsfc.csv"),   check.names = FALSE)
base  <- merge(covar, preds, by = id_col, all.x = TRUE, sort = FALSE)
pub_f <- file.path(deriv_dir, "puberty.csv")
if (file.exists(pub_f)) base <- merge(base, read.csv(pub_f, check.names = FALSE), by = id_col, all.x = TRUE, sort = FALSE)

for (block in blocks_to_run()) {
  d <- plsc_dirs(block)
  message(sprintf("\n=== PLSC rs-FC x %s ===", toupper(block)))
  if (!file.exists(file.path(d$plsc, "plsc_results.rds"))) {
    message("  no PLSC results in ", d$plsc, " - run 1b for this block first"); next
  }
  struct <- read.csv(file.path(deriv_dir, sprintf("clean-%s.csv", block)), check.names = FALSE)
  lx <- read.csv(file.path(d$plsc, "rsfc_lx-scores.csv"), check.names = FALSE)
  ly <- read.csv(file.path(d$plsc, sprintf("%s_ly-scores.csv", block)), check.names = FALSE)
  P  <- read.csv(file.path(d$plsc, "rsfc_P-components.csv"), row.names = 1, check.names = FALSE)
  Q  <- read.csv(file.path(d$plsc, sprintf("%s_Q-components.csv", block)), row.names = 1, check.names = FALSE)

  dims_env <- Sys.getenv("PLSC_DIMS", unset = "")
  if (nzchar(dims_env)) {
    dims <- as.integer(strsplit(dims_env, ",")[[1]])
  } else {
    dims <- read.csv(file.path(d$plsc, "significant_dimensions.csv"))$dimension
    if (length(dims) == 0) {
      message("  No significant dimensions - building data for Dim1 only so the pipeline can be tested.")
      dims <- 1L
    }
  }
  dims <- dims[dims <= sum(grepl("^BR_Dim", colnames(P)))]
  message("  dimensions: ", paste(dims, collapse = ", "))

  for (k in dims) {
    out <- file.path(d$reg, paste0("dim", k))
    dir.create(out, showWarnings = FALSE, recursive = TRUE)

    sc <- data.frame(lx[[id_col]], lx[[paste0("lx_Dim", k)]], ly[[paste0("ly_Dim", k)]])
    colnames(sc) <- c(id_col, "score_lx", "score_ly")
    sc_data <- merge(sc, base, by = id_col, sort = FALSE)
    write.csv(sc_data, file.path(out, sprintf("lme_dim%d_data.csv", k)), row.names = FALSE)

    br_col <- paste0("BR_Dim", k)
    f_rsfc <- rownames(P)[abs(P[[br_col]]) > br_threshold]
    f_str  <- rownames(Q)[abs(Q[[br_col]]) > br_threshold]
    flist <- rbind(
      data.frame(feature = f_rsfc, block = rep("rsfc", length(f_rsfc)), bootstrap_ratio = P[f_rsfc, br_col]),
      data.frame(feature = f_str,  block = rep(block,  length(f_str)),  bootstrap_ratio = Q[f_str,  br_col])
    )
    write.csv(flist, file.path(out, sprintf("features_dim%d_list.csv", k)), row.names = FALSE)

    feat <- merge(rsfc[, c(id_col, f_rsfc), drop = FALSE], struct[, c(id_col, f_str), drop = FALSE],
                  by = id_col, sort = FALSE)
    feat <- merge(feat, base, by = id_col, sort = FALSE)
    write.csv(feat, file.path(out, sprintf("features_dim%d_data.csv", k)), row.names = FALSE)

    message(sprintf("  dim%d: N = %d | features |BR| > %.1f: %d rs-FC, %d %s",
                    k, nrow(sc_data), br_threshold, length(f_rsfc), length(f_str), toupper(block)))
  }
}
