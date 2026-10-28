# =============================================================================
# 3a-ml-rf.R - random forest: behaviour ~ coupling patterns + puberty
# -----------------------------------------------------------------------------
# Exploratory / predictive complement to the LMEs. For each Year 4 behaviour
# measure (one per SLURM array task, or all when run locally):
#
#   Features
#     brain    : latent scores of every significant dimension of BOTH PLSCs
#                (rs-FC side "fc" and RNI/RND side "str"), e.g. rni_d1_fc
#     puberty  : ml_puberty_features (pds_stage, pds_tempo)
#     covars   : ml_covariates (age, sex, income, parent education, motion, scanner)
#
#   Nested models, all with site-grouped cross-validation (whole sites held
#   out, so siblings and site effects never leak between train and test):
#     M0 covars            M1 covars + brain            M2 covars + brain + puberty
#     EN2 elastic net on M2 features + brain x pds_stage products (linear benchmark)
#
#   Tests
#     - out-of-sample R2 and r for each model
#     - permutation null for M2 (outcome shuffled within site)          -> does it predict at all?
#     - permutation null for puberty (puberty features shuffled within
#       site, M2 refit)                                                 -> does puberty add anything?
#     - Friedman H^2 interaction strength, brain x pds_stage, with
#       brain x age as a reference                                      -> moderation, no linearity assumed
#     - 2D partial dependence: predicted measure across each brain score,
#       one curve per pubertal stage                                    -> the interaction plot
#     - cross-stage transfer: train in early/mid puberty, test in late
#       (and reverse) vs within-stage CV                                -> does the mapping change?
#     - permutation variable importance from a full-data M2 forest
#
# Output: derivatives/ml/<measure>/  (summary.csv, cv_performance.csv,
#         permutation_null.csv, importance.csv, interaction_H.csv,
#         pdp_puberty.csv/.png, transfer.csv, cv_predictions.csv)
# Run 3c-ml-summary.R afterwards to combine all measures.
#
# Run:  Rscript 3a-ml-rf.R                       (all measures)
#       PLSC_ML_OUTCOME=nihtb_flanker Rscript 3a-ml-rf.R
#       HPC: hpc/3a-rf.sbatch (array, one measure per task)
# =============================================================================
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "config.R"))
suppressPackageStartupMessages({ library(ranger); library(glmnet); library(ggplot2) })

# ---- assemble one table --------------------------------------------------------
covar <- read.csv(file.path(deriv_dir, "covariate.csv"),    check.names = FALSE)
preds <- read.csv(file.path(deriv_dir, "lme-measures.csv"), check.names = FALSE)
pub   <- read.csv(file.path(deriv_dir, "puberty.csv"),      check.names = FALSE)
dat   <- Reduce(function(a, b) merge(a, b, by = id_col, all.x = TRUE, sort = FALSE), list(covar, preds, pub))

brain_feats <- character(0)
for (b in plsc_blocks) {
  pd <- file.path(deriv_dir, paste0("plsc-", b))
  if (!file.exists(file.path(pd, "rsfc_lx-scores.csv"))) { message("No PLSC results for ", b, " - skipped"); next }
  lx <- read.csv(file.path(pd, "rsfc_lx-scores.csv"), check.names = FALSE)
  ly <- read.csv(file.path(pd, sprintf("%s_ly-scores.csv", b)), check.names = FALSE)
  for (k in sig_dims(b)) {
    s <- data.frame(lx[[id_col]], lx[[paste0("lx_Dim", k)]], ly[[paste0("ly_Dim", k)]])
    nm <- paste0(b, "_d", k, c("_fc", "_str"))
    colnames(s) <- c(id_col, nm)
    dat <- merge(dat, s, by = id_col, all.x = TRUE, sort = FALSE)
    brain_feats <- c(brain_feats, nm)
  }
}
if (!length(brain_feats)) stop("No latent scores found - run 1b first")
for (v in intersect(ml_covariates, lme_categorical_covars)) dat[[v]] <- factor(dat[[v]])
message("Brain features: ", paste(brain_feats, collapse = ", "))

feats <- list(M0 = ml_covariates,
              M1 = c(ml_covariates, brain_feats),
              M2 = c(ml_covariates, brain_feats, ml_puberty_features))

# ---- which outcome(s) -----------------------------------------------------------
outcomes <- intersect(ml_outcomes, colnames(dat))
if (nzchar(Sys.getenv("PLSC_ML_OUTCOME"))) outcomes <- Sys.getenv("PLSC_ML_OUTCOME")
if (nzchar(Sys.getenv("PLSC_ML_INDEX"))) {
  i <- as.integer(Sys.getenv("PLSC_ML_INDEX")) + 1
  all_out <- intersect(ml_outcomes, colnames(dat))
  if (i > length(all_out)) { message("Array index beyond number of measures - nothing to do"); quit(save = "no") }
  outcomes <- all_out[i]
}

# ---- helpers ----------------------------------------------------------------------
site_folds <- function(site, K) {             # balance fold sizes; whole sites per fold
  tab <- sort(table(site), decreasing = TRUE); K <- min(K, length(tab))
  load <- numeric(K); fold_of <- integer(length(tab)); names(fold_of) <- names(tab)
  for (s in names(tab)) { f <- which.min(load); fold_of[s] <- f; load[f] <- load[f] + tab[[s]] }
  unname(fold_of[as.character(site)])
}
r2 <- function(y, yhat) 1 - sum((y - yhat)^2) / sum((y - mean(y))^2)
fit_rf <- function(df, f, importance = "none")
  ranger(x = df[, f, drop = FALSE], y = df$.y, num.trees = ml_n_trees, min.node.size = 5,
         importance = importance, num.threads = ml_threads, seed = 1)
cv_rf <- function(df, f, folds) {
  yhat <- numeric(nrow(df))
  for (k in unique(folds)) {
    tr <- folds != k
    yhat[!tr] <- predict(fit_rf(df[tr, ], f), df[!tr, f, drop = FALSE], num.threads = ml_threads)$predictions
  }
  yhat
}
enet_matrix <- function(df) {
  X <- model.matrix(~ ., data = df[, feats$M2, drop = FALSE])[, -1, drop = FALSE]
  inter <- sapply(brain_feats, function(b) df[[b]] * df[[puberty_moderator]])
  colnames(inter) <- paste0(brain_feats, ":", puberty_moderator)
  cbind(X, inter)
}
cv_enet <- function(df, folds) {
  X <- enet_matrix(df); yhat <- numeric(nrow(df))
  for (k in unique(folds)) {
    tr <- folds != k
    cvf <- cv.glmnet(X[tr, ], df$.y[tr], alpha = 0.5, nfolds = 5)
    yhat[!tr] <- as.numeric(predict(cvf, X[!tr, ], s = "lambda.min"))
  }
  yhat
}
shuffle_within <- function(x, g) { for (s in unique(g)) { k <- which(g == s); x[k] <- x[k][sample.int(length(k))] }; x }

# Friedman H^2 for a pair of features, on a sample of rows S
H2 <- function(fit, S, a, b) {
  n <- nrow(S); idx <- rep(seq_len(n), each = n)
  pd <- function(vars) {
    big <- S[rep(seq_len(n), times = n), , drop = FALSE]
    for (v in vars) big[[v]] <- S[[v]][idx]
    p <- predict(fit, big, num.threads = ml_threads)$predictions
    m <- tapply(p, idx, mean); m - mean(m)
  }
  pab <- pd(c(a, b)); pa <- pd(a); pb <- pd(b)
  sum((pab - pa - pb)^2) / sum(pab^2)
}

# ---- main loop ----------------------------------------------------------------------
for (outcome in outcomes) {
  set.seed(as.integer(Sys.getenv("PLSC_SEED", 42)))
  od <- file.path(ml_dir(), outcome); dir.create(od, showWarnings = FALSE)
  df <- dat[, unique(c(id_col, "site_id_l", outcome, feats$M2))]
  df <- df[complete.cases(df), ]
  df$.y <- df[[outcome]]
  if (nrow(df) < min_n_lme) { message(outcome, ": N = ", nrow(df), " < ", min_n_lme, " - skipped"); next }
  folds <- site_folds(df$site_id_l, ml_n_folds)
  message(sprintf("\n=== %s: N = %d, %d site-grouped folds ===", outcome, nrow(df), length(unique(folds))))

  # nested models
  P <- data.frame(participant_id = df[[id_col]], site = df$site_id_l, fold = folds, y = df$.y)
  for (m in names(feats)) P[[m]] <- cv_rf(df, feats[[m]], folds)
  P$EN2 <- cv_enet(df, folds)
  perf <- data.frame(model = c("M0", "M1", "M2", "EN2"),
                     features = c("covariates", "+ brain", "+ brain + puberty", "elastic net: M2 + brain x stage"),
                     r2 = sapply(c("M0", "M1", "M2", "EN2"), function(m) r2(P$y, P[[m]])),
                     r  = sapply(c("M0", "M1", "M2", "EN2"), function(m) cor(P$y, P[[m]])))
  write.csv(P, file.path(od, "cv_predictions.csv"), row.names = FALSE)

  # permutation nulls
  null <- data.frame(perm = seq_len(ml_n_perm), r2_outcome_shuffled = NA_real_, r2_puberty_shuffled = NA_real_)
  for (i in seq_len(ml_n_perm)) {
    d1 <- df; d1$.y <- shuffle_within(df$.y, df$site_id_l)
    null$r2_outcome_shuffled[i] <- r2(d1$.y, cv_rf(d1, feats$M2, folds))
    d2 <- df; for (v in ml_puberty_features) d2[[v]] <- shuffle_within(df[[v]], df$site_id_l)
    null$r2_puberty_shuffled[i] <- r2(df$.y, cv_rf(d2, feats$M2, folds))
  }
  write.csv(null, file.path(od, "permutation_null.csv"), row.names = FALSE)
  r2_m2 <- perf$r2[perf$model == "M2"]
  p_model   <- (1 + sum(null$r2_outcome_shuffled >= r2_m2)) / (1 + ml_n_perm)
  p_puberty <- (1 + sum(null$r2_puberty_shuffled >= r2_m2)) / (1 + ml_n_perm)
  perf$p_perm <- c(NA, NA, p_model, NA)
  write.csv(perf, file.path(od, "cv_performance.csv"), row.names = FALSE)
  print(perf, digits = 3)

  # full-data forest: importance, H^2, partial dependence
  full <- fit_rf(df, feats$M2, importance = "permutation")
  imp <- data.frame(feature = names(full$variable.importance), importance = full$variable.importance)
  imp$group <- ifelse(imp$feature %in% brain_feats, "brain", ifelse(imp$feature %in% ml_puberty_features, "puberty", "covariate"))
  write.csv(imp[order(-imp$importance), ], file.path(od, "importance.csv"), row.names = FALSE)

  S <- df[sample.int(nrow(df), min(ml_h_n, nrow(df))), feats$M2]
  Hs <- do.call(rbind, lapply(brain_feats, function(b) data.frame(
    brain_feature = b,
    H2_x_puberty = H2(full, S, b, puberty_moderator),
    H2_x_age     = H2(full, S, b, "interview_age"))))
  write.csv(Hs, file.path(od, "interaction_H.csv"), row.names = FALSE)

  stages <- sort(unique(df[[puberty_moderator]]))
  pdp <- do.call(rbind, lapply(brain_feats, function(b) {
    grid <- quantile(df[[b]], seq(0.05, 0.95, length.out = 15))
    do.call(rbind, lapply(stages, function(st) data.frame(
      brain_feature = b, brain_value = grid, stage = st,
      predicted = sapply(grid, function(g) { S2 <- S; S2[[b]] <- g; S2[[puberty_moderator]] <- st
                                             mean(predict(full, S2, num.threads = ml_threads)$predictions) }))))
  }))
  write.csv(pdp, file.path(od, "pdp_puberty.csv"), row.names = FALSE)
  gp <- ggplot(pdp, aes(brain_value, predicted, colour = factor(stage))) + geom_line(linewidth = 0.8) +
    facet_wrap(~ brain_feature, scales = "free_x") + theme_minimal(base_size = 9) +
    labs(x = "Latent score", y = paste("Predicted", outcome), colour = "PDS stage",
         title = paste0(outcome, ": partial dependence on each coupling pattern, by pubertal stage"))
  ggsave(file.path(od, "pdp_puberty.png"), gp, width = 9, height = 5, dpi = 150)

  # cross-stage transfer (brain + covariates, no puberty features)
  grp <- ifelse(df[[puberty_moderator]] >= ml_late_stage, "late", "early_mid")
  transfer <- NULL
  if (all(table(factor(grp, c("early_mid", "late"))) >= ml_min_group_n)) {
    for (g in c("early_mid", "late")) {
      dg <- df[grp == g, ]; other <- df[grp != g, ]
      within <- r2(dg$.y, cv_rf(dg, feats$M1, site_folds(dg$site_id_l, ml_n_folds)))
      across <- r2(other$.y, predict(fit_rf(dg, feats$M1), other[, feats$M1], num.threads = ml_threads)$predictions)
      transfer <- rbind(transfer, data.frame(train_group = g, test_group = setdiff(c("early_mid", "late"), g),
                                             n_train = nrow(dg), n_test = nrow(other),
                                             r2_within_cv = within, r2_transfer = across, drop = within - across))
    }
  } else message("  transfer test skipped: a puberty group has < ", ml_min_group_n, " participants")
  if (!is.null(transfer)) write.csv(transfer, file.path(od, "transfer.csv"), row.names = FALSE)

  summ <- data.frame(outcome = outcome, domain = lme_predictor_map[[outcome]]$domain, N = nrow(df),
                     n_folds = length(unique(folds)), n_perm = ml_n_perm,
                     r2_M0 = perf$r2[1], r2_M1 = perf$r2[2], r2_M2 = perf$r2[3], r2_EN2 = perf$r2[4],
                     delta_r2_brain = perf$r2[2] - perf$r2[1], delta_r2_puberty = perf$r2[3] - perf$r2[2],
                     p_model = p_model, p_puberty = p_puberty,
                     max_H2_x_puberty = max(Hs$H2_x_puberty), top_H2_feature = Hs$brain_feature[which.max(Hs$H2_x_puberty)],
                     mean_transfer_drop = if (is.null(transfer)) NA else mean(transfer$drop))
  write.csv(summ, file.path(od, "summary.csv"), row.names = FALSE)
  message("Wrote ", od)
}
