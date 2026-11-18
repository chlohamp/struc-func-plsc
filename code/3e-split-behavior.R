# =============================================================================
# 3e-split-behavior.R - do the brain-behavior LME results replicate across
#                       independent halves of the Year 4 sample?
# -----------------------------------------------------------------------------
# Companion to 3d-split.ipynb (which tests whether the PLSC saliences replicate).
# This script tests the behavior side: for each random split of the sample into
# two halves (family-aware, site-stratified; same scheme as 3d):
#
#   1. TRAIN half: residualize both blocks (same covariates as 1b), SS1-scale,
#      run the PLSC SVD -> saliences P (rs-FC) and Q (RNI/RND).
#      Each full-sample dimension is matched to the train-half dimension whose
#      saliences correlate best with it, and the sign is aligned to the full
#      sample, so "LD1" means the same pattern in every split.
#   2. TEST half: residualize + SS1-scale within the test half only, then
#      project onto the TRAIN saliences -> out-of-sample latent scores
#      (score_lx = rs-FC side, score_ly = RNI/RND side).
#   3. Re-run the same LME as 2b-plsc-reg-boot.R in the test half:
#        score ~ measure + covariates + (1 | site_id_l / rel_family_id)
#   4. Swap halves and repeat, so every split gives two independent tests.
#
# The scores are never fit to the people they are tested in, so a replicated
# effect cannot come from fitting the PLSC and the LME to the same people.
#
# Which effects are tested (PLSC_SPLIT_TEST):
#   "fdr" (default) - the effects with FDR q < .05 across all 360 models
#                     (the values shown in Fig 2), read from
#                     ohbm-figures/ohbm-fig2-values.csv
#   "all"           - all 360 models (slow)
#
# For each effect the summary reports:
#   beta_full          standardized beta in the full sample (as in Fig 2, unaligned sign)
#   beta_split_median  median standardized beta across test halves
#   pct_same_sign      % of test halves with the same sign as the full sample
#   pct_replicated     % of test halves with p < .05 AND the same sign
#   pct_both_halves    % of splits where BOTH halves replicate
#   expected_pct       % expected to replicate if the full-sample effect is the
#                      true effect (power at half the N: pnorm(|z_full|/sqrt(2) - 1.96))
#
# Usage (from the code folder):
#   Rscript 3e-split-behavior.R
#   PLSC_SPLIT_N=20 Rscript 3e-split-behavior.R      # quicker run
#   PLSC_SPLIT_TEST=all Rscript 3e-split-behavior.R  # every model
#
# Outputs (derivatives/<variant>/split-half/):
#   split-behavior-all-tests.csv   one row per split x test half x effect
#   split-behavior-summary.csv     one row per effect
#   split-behavior-replication.png full-sample vs split-half betas
# =============================================================================
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "config.R"))
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "lme-helpers.R"))

n_splits  <- as.integer(Sys.getenv("PLSC_SPLIT_N", unset = "50"))
test_set  <- Sys.getenv("PLSC_SPLIT_TEST", unset = "fdr")
seed      <- 2026
n_match   <- 8   # train-half dimensions searched when matching to the full-sample dimension
out_dir   <- file.path(deriv_dir, "split-half")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- Data (same files and row order as 1b / 2a) -------------------------------
covar <- read.csv(file.path(deriv_dir, "covariate.csv"), check.names = FALSE)
preds <- read.csv(file.path(deriv_dir, "lme-measures.csv"), check.names = FALSE)
read_block <- function(name) {
  d <- read.csv(file.path(deriv_dir, sprintf("clean-%s.csv", name)), check.names = FALSE)
  stopifnot(identical(d[[id_col]], covar[[id_col]]))
  as.matrix(d[, setdiff(colnames(d), id_col)])
}
X_all <- list(rsfc = read_block("rsfc"), rni = read_block("rni"), rnd = read_block("rnd"))
base  <- cbind(covar, preds[match(covar[[id_col]], preds[[id_col]]), setdiff(colnames(preds), id_col), drop = FALSE])

# Full-sample saliences (columns V1, V2, ... in the 1b output)
full_sal <- lapply(setNames(nm = plsc_blocks), function(b) {
  d <- plsc_dirs(b)$plsc
  P <- read.csv(file.path(d, "rsfc_P-components.csv"), row.names = 1, check.names = FALSE)
  Q <- read.csv(file.path(d, sprintf("%s_Q-components.csv", b)), row.names = 1, check.names = FALSE)
  list(P = as.matrix(P[, grepl("^V[0-9]+$", colnames(P))]),
       Q = as.matrix(Q[, grepl("^V[0-9]+$", colnames(Q))]))
})

# Full-sample LME results (FDR / Bonferroni across all 360 models, from make-ohbm-figures.py)
full_res_f <- file.path(deriv_dir, "ohbm-figures", "ohbm-fig2-values.csv")
if (!file.exists(full_res_f)) stop("Not found: ", full_res_f, " - run make-ohbm-figures.py first")
full_res <- read.csv(full_res_f)
full_res$k <- as.integer(sub("dim", "", full_res$dimension))
tests <- if (test_set == "all") full_res else full_res[full_res$q_all < 0.05, ]
tests <- tests[order(tests$plsc, tests$k, tests$outcome, tests$predictor), ]
message(sprintf("Testing %d effects (%s) across %d splits x 2 test halves = %d LMEs",
                nrow(tests), test_set, n_splits, nrow(tests) * n_splits * 2))

# ---- PLSC pieces (as in 3d-split.ipynb / tepPLS with SS1 scaling) ------------
design_mat <- function(idx) {
  d <- covar[idx, ]
  f <- paste("~", paste(c(numerical_covars, sprintf("factor(%s)", c(categorical_covars, "site_id_l"))), collapse = " + "))
  model.matrix(as.formula(f), data = d)
}
ss1 <- function(Y) { Y <- sweep(Y, 2, colMeans(Y)); sweep(Y, 2, sqrt(colSums(Y^2)), "/") }
prep <- function(idx, block) {
  qrC <- qr(design_mat(idx))
  list(X = ss1(qr.resid(qrC, X_all$rsfc[idx, ])), Y = ss1(qr.resid(qrC, X_all[[block]][idx, ])))
}
plsc_svd <- function(X, Y, k) { s <- svd(crossprod(X, Y), nu = k, nv = k); list(P = s$u, Q = s$v) }

# Match each full-sample dimension to the train-half dimension with the most
# similar saliences (greedy, no reuse) and align its sign to the full sample.
match_dims <- function(tr, full, dims) {
  used <- integer(0); out <- list()
  for (k in dims) {
    ref <- c(full$P[, k], full$Q[, k])
    r <- sapply(seq_len(ncol(tr$P)), function(j) cor(ref, c(tr$P[, j], tr$Q[, j])))
    r[used] <- 0
    j <- which.max(abs(r)); used <- c(used, j)
    out[[as.character(k)]] <- list(j = j, sign = sign(r[j]), r = abs(r[j]))
  }
  out
}

# ---- Family-aware, site-stratified split (same scheme as 3d-split.ipynb) ----
fam_site <- tapply(covar$site_id_l, covar$rel_family_id, function(s) as.numeric(names(which.max(table(s)))))
fam_size <- table(covar$rel_family_id)
split_half <- function() {
  half <- setNames(integer(length(fam_site)), names(fam_site))
  for (s in unique(fam_site)) {
    fams <- names(fam_site)[fam_site == s]
    fams <- fams[sample.int(length(fams))]
    n <- c(0, 0)
    for (f in fams) {
      h <- if (n[1] == n[2]) sample(1:2, 1) else which.min(n)
      half[f] <- h; n[h] <- n[h] + fam_size[[f]]
    }
  }
  lab <- half[as.character(covar$rel_family_id)]
  list(which(lab == 1), which(lab == 2))
}

# ---- Run ---------------------------------------------------------------------
set.seed(seed)
all_f <- file.path(out_dir, "split-behavior-all-tests.csv")
rows <- list(); t0 <- Sys.time()
dims_needed <- lapply(setNames(nm = plsc_blocks), function(b) sort(unique(tests$k[tests$plsc == b])))

for (s in seq_len(n_splits)) {
  halves <- split_half()
  for (h in 1:2) {
    tr_idx <- halves[[3 - h]]; te_idx <- halves[[h]]
    for (block in plsc_blocks) {
      tb <- tests[tests$plsc == block, ]
      if (nrow(tb) == 0) next
      tr <- prep(tr_idx, block); te <- prep(te_idx, block)
      sal <- plsc_svd(tr$X, tr$Y, n_match)
      mt <- match_dims(sal, full_sal[[block]], dims_needed[[block]])
      for (k in dims_needed[[block]]) {
        m <- mt[[as.character(k)]]
        d <- base[te_idx, ]
        d$score_lx <- as.numeric(te$X %*% sal$P[, m$j]) * m$sign
        d$score_ly <- as.numeric(te$Y %*% sal$Q[, m$j]) * m$sign
        tk <- tb[tb$k == k, ]
        for (i in seq_len(nrow(tk))) {
          sc <- tk$outcome[i]; pv <- tk$predictor[i]
          r <- suppressWarnings(suppressMessages(fit_one_lme(d, sc, pv)))
          rows[[length(rows) + 1]] <- data.frame(
            split = s, test_half = h, plsc = block, dimension = paste0("dim", k), outcome = sc, predictor = pv,
            matched_train_dim = m$j, salience_match_r = m$r, N = r$N,
            beta_std = r$estimate / sd(d[[sc]]), p_value = r$p_value, random_effects = r$random_effects)
        }
      }
    }
  }
  if (s %% 5 == 0 || s == n_splits) {
    write.csv(do.call(rbind, rows), all_f, row.names = FALSE)   # checkpoint
    el <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
    message(sprintf("  split %d/%d done (%.1f min elapsed, ~%.1f min left)", s, n_splits, el, el / s * (n_splits - s)))
  }
}
res <- do.call(rbind, rows)
write.csv(res, all_f, row.names = FALSE)

# ---- Summary -----------------------------------------------------------------
key <- function(d) paste(d$plsc, d$dimension, d$outcome, d$predictor)
res$key <- key(res); tests$key <- key(tests)
res$beta_full <- tests$beta_std[match(res$key, tests$key)]
res$rep <- !is.na(res$p_value) & res$p_value < 0.05 & sign(res$beta_std) == sign(res$beta_full)

both <- aggregate(rep ~ key + split, data = res, FUN = all)
summ <- do.call(rbind, lapply(split(res, res$key), function(d) {
  t <- tests[tests$key == d$key[1], ]
  z_full <- abs(t$estimate / t$std_error)
  data.frame(plsc = t$plsc, dimension = t$dimension, outcome = t$outcome, predictor = t$predictor,
             domain = t$domain,
             beta_full = t$beta_std, p_full = t$p_value, q_full = t$q_all, bonf_full = t$bonf,
             beta_split_median = median(d$beta_std, na.rm = TRUE),
             beta_split_lo = quantile(d$beta_std, 0.025, na.rm = TRUE, names = FALSE),
             beta_split_hi = quantile(d$beta_std, 0.975, na.rm = TRUE, names = FALSE),
             pct_same_sign = 100 * mean(sign(d$beta_std) == sign(t$beta_std), na.rm = TRUE),
             pct_replicated = 100 * mean(d$rep),
             pct_both_halves = 100 * mean(both$rep[both$key == d$key[1]]),
             expected_pct = 100 * pnorm(z_full / sqrt(2) - qnorm(0.975)),
             salience_match_r_median = median(d$salience_match_r),
             n_tests = nrow(d))
}))
summ <- summ[order(summ$plsc, summ$dimension, -summ$pct_replicated), ]
summ$ratio_obs_expected <- summ$pct_replicated / summ$expected_pct
num <- vapply(summ, is.numeric, logical(1))
summ[num] <- lapply(summ[num], function(x) round(x, 4))
write.csv(summ, file.path(out_dir, "split-behavior-summary.csv"), row.names = FALSE)

# ---- Figure: full-sample vs split-half betas ---------------------------------
png(file.path(out_dir, "split-behavior-replication.png"), width = 1800, height = 900, res = 150)
par(mfrow = c(1, 2), mar = c(4.5, 4.5, 3, 1))
lim <- range(c(summ$beta_full, summ$beta_split_lo, summ$beta_split_hi), na.rm = TRUE)
col <- ifelse(summ$plsc == "rni", "#E45756", "#4C78A8")
plot(summ$beta_full, summ$beta_split_median, xlim = lim, ylim = lim, pch = ifelse(summ$bonf_full, 19, 1), col = col,
     xlab = "Standardized beta, full sample", ylab = "Median beta in held-out halves (95% range)",
     main = "Effect sizes in held-out halves")
segments(summ$beta_full, summ$beta_split_lo, summ$beta_full, summ$beta_split_hi, col = adjustcolor(col, 0.35))
abline(0, 1, lty = 2, col = "grey40"); abline(h = 0, v = 0, col = "grey80")
legend("topleft", c("RNI", "RND", "Bonferroni (full)", "FDR only (full)"), col = c("#E45756", "#4C78A8", "grey30", "grey30"),
       pch = c(19, 19, 19, 1), bty = "n", cex = 0.85)
plot(summ$expected_pct, summ$pct_replicated, xlim = c(0, 100), ylim = c(0, 100), pch = ifelse(summ$bonf_full, 19, 1), col = col,
     xlab = "% expected to replicate (power at half N)", ylab = "% of held-out halves replicated (p < .05, same sign)",
     main = "Observed vs expected replication")
abline(0, 1, lty = 2, col = "grey40")
dev.off()

# ---- Console summary ---------------------------------------------------------
message(sprintf("\nDone: %d effects x %d test halves in %.1f min", nrow(summ), n_splits * 2,
                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
message(sprintf("Median replication: %.0f%% observed vs %.0f%% expected; same sign in %.0f%% of halves",
                median(summ$pct_replicated), median(summ$expected_pct), median(summ$pct_same_sign)))
message("Wrote ", file.path(out_dir, "split-behavior-summary.csv"))
