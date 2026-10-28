# =============================================================================
# lme-helpers.R - shared model code for the 2b-* scripts
# outcome ~ predictor + covariates + (1 | site / family)
# =============================================================================
suppressPackageStartupMessages(library(lmerTest))

# Sum-to-zero contrasts so Type III ANOVA p-values are meaningful for factors
options(contrasts = c("contr.sum", "contr.poly"))

fit_one_lme <- function(data, outcome, predictor, save_table = NULL) {
  pred_is_cat <- predictor %in% lme_predictor_cats
  all_columns <- unique(c(outcome, predictor, lme_categorical_covars, lme_numerical_covars, "site_id_l", "rel_family_id"))
  sub_data <- data[, all_columns]
  sub_data <- sub_data[complete.cases(sub_data), ]

  for (var in lme_categorical_covars) sub_data[[var]] <- factor(sub_data[[var]])
  for (var in lme_numerical_covars)   sub_data[[var]] <- as.numeric(scale(sub_data[[var]]))
  if (pred_is_cat) {
    sub_data[[predictor]] <- factor(sub_data[[predictor]])
  } else {
    sub_data[[predictor]] <- as.numeric(scale(sub_data[[predictor]]))
  }

  # Drop factor covariates that have only one level in this subset (lmer would error)
  cats_ok <- lme_categorical_covars[vapply(lme_categorical_covars, function(v) nlevels(sub_data[[v]]) > 1, logical(1))]
  fixed_effects <- paste(c(lme_numerical_covars, cats_ok), collapse = " + ")
  re_full <- "(1|site_id_l/rel_family_id)"
  re_site <- "(1|site_id_l)"
  make_eq <- function(re) paste(outcome, "~", predictor, "+", fixed_effects, "+", re)

  row <- data.frame(outcome = outcome, predictor = predictor,
                    domain = lme_predictor_map[[predictor]]$domain %||% NA_character_,
                    var_type = ifelse(pred_is_cat, "categorical", "continuous"),
                    N = nrow(sub_data), estimate = NA_real_, std_error = NA_real_,
                    ci_lower = NA_real_, ci_upper = NA_real_, p_value = NA_real_,
                    singular = NA, random_effects = re_full, stringsAsFactors = FALSE)

  fit <- function(re) tryCatch(lmer(as.formula(make_eq(re)), data = sub_data),
                               error = function(e) { message(sprintf("    Model failed (%s ~ %s, %s): %s", outcome, predictor, re, e$message)); NULL })
  model <- fit(re_full)
  # If almost every family is a singleton in this subset, lmer refuses the
  # nested term. Fall back to site only and record it in `random_effects`.
  if (is.null(model)) {
    model <- fit(re_site)
    row$random_effects <- re_site
  }
  if (is.null(model)) { row$random_effects <- "failed"; return(row) }

  row$N <- nobs(model)
  row$singular <- isSingular(model)
  model_table <- as.data.frame(coef(summary(model)))
  if (!is.null(save_table)) write.csv(model_table, save_table, row.names = TRUE)

  # Type III ANOVA p-value (overall effect for factors)
  an_tab <- tryCatch(anova(model, type = 3), error = function(e) NULL)
  if (!is.null(an_tab) && predictor %in% rownames(an_tab) && "Pr(>F)" %in% colnames(an_tab)) {
    row$p_value <- as.numeric(an_tab[predictor, "Pr(>F)"])
  } else if (predictor %in% rownames(model_table)) {
    row$p_value <- as.numeric(model_table[predictor, "Pr(>|t|)"])
  }

  # Estimate, SE, 95% Wald CI with Satterthwaite df.
  # Binary factors (contr.sum) get one coefficient named "<var>1".
  coef_row <- if (predictor %in% rownames(model_table)) predictor else paste0(predictor, "1")
  if (coef_row %in% rownames(model_table)) {
    row$estimate  <- model_table[coef_row, "Estimate"]
    row$std_error <- model_table[coef_row, "Std. Error"]
    t_crit <- qt(0.975, df = model_table[coef_row, "df"])
    row$ci_lower <- row$estimate - t_crit * row$std_error
    row$ci_upper <- row$estimate + t_crit * row$std_error
  }
  row
}

# Measures present in the data with at least min_n_lme non-missing values
usable_predictors <- function(data) {
  present <- intersect(lme_predictors, colnames(data))
  n_ok <- vapply(present, function(p) sum(!is.na(data[[p]])), integer(1))
  keep <- present[n_ok >= min_n_lme]
  skipped <- c(setdiff(lme_predictors, present), present[n_ok < min_n_lme])
  if (length(skipped)) message("  Skipping measures (missing or N < ", min_n_lme, "): ", paste(skipped, collapse = ", "))
  keep
}

add_flags <- function(results, fdr_by = "outcome") {
  results$p_fdr <- ave(results$p_value, results[[fdr_by]], FUN = function(p) p.adjust(p, method = "fdr"))
  results$significant_p05 <- !is.na(results$p_value) & results$p_value < 0.05
  results$significant_p01 <- !is.na(results$p_value) & results$p_value < 0.01
  results$significant_fdr05 <- !is.na(results$p_fdr) & results$p_fdr < 0.05
  results
}

# -----------------------------------------------------------------------------
# General version used by the puberty models (2c):
#   outcome ~ <terms> + covariates + (1 | site / family)
# `terms` can include interactions ("x:pds_stage"); `scale_vars` are
# z-scored first (continuous predictors and moderators); `focal` are the
# terms reported. One row per focal term.
# -----------------------------------------------------------------------------
fit_lme_terms <- function(data, outcome, terms, focal, scale_vars = character(0),
                          drop_covars = character(0), save_table = NULL) {
  vars <- unique(unlist(strsplit(terms, ":", fixed = TRUE)))
  num_cov <- setdiff(lme_numerical_covars, drop_covars)
  cat_cov <- setdiff(lme_categorical_covars, drop_covars)
  cols <- unique(c(outcome, vars, cat_cov, num_cov, "site_id_l", "rel_family_id"))
  d <- data[, cols]
  d <- d[complete.cases(d), ]
  for (v in intersect(c(cat_cov, vars), lme_categorical_covars)) d[[v]] <- factor(d[[v]])
  for (v in unique(c(num_cov, scale_vars))) d[[v]] <- as.numeric(scale(d[[v]]))
  cat_ok <- cat_cov[vapply(cat_cov, function(v) nlevels(d[[v]]) > 1, logical(1))]
  standalone <- terms[!grepl(":", terms, fixed = TRUE)]   # covariates in an interaction keep their main effect
  fixed <- paste(c(terms, setdiff(c(num_cov, cat_ok), standalone)), collapse = " + ")
  eqs <- c(full = paste(outcome, "~", fixed, "+ (1|site_id_l/rel_family_id)"),
           site = paste(outcome, "~", fixed, "+ (1|site_id_l)"))
  model <- NULL; re_used <- "failed"
  for (k in names(eqs)) {
    model <- tryCatch(lmer(as.formula(eqs[[k]]), data = d), error = function(e) NULL)
    if (!is.null(model)) { re_used <- k; break }
  }
  base <- data.frame(outcome = outcome, term = focal, N = nrow(d), estimate = NA_real_,
                     std_error = NA_real_, ci_lower = NA_real_, ci_upper = NA_real_,
                     p_value = NA_real_, random_effects = re_used, stringsAsFactors = FALSE)
  if (is.null(model)) return(base)
  base$N <- nobs(model)
  ct <- as.data.frame(coef(summary(model)))
  if (!is.null(save_table)) write.csv(ct, save_table, row.names = TRUE)
  an <- tryCatch(anova(model, type = 3), error = function(e) NULL)
  for (i in seq_along(focal)) {
    f <- focal[i]
    # coefficient name: as written, or with "1" after a sum-coded 2-level factor
    cand <- c(f, gsub("(demo_sex_v2)", "\\11", f), paste0(f, "1"))
    r <- cand[cand %in% rownames(ct)][1]
    if (!is.na(r)) {
      base$estimate[i]  <- ct[r, "Estimate"]
      base$std_error[i] <- ct[r, "Std. Error"]
      tc <- qt(0.975, ct[r, "df"])
      base$ci_lower[i] <- base$estimate[i] - tc * base$std_error[i]
      base$ci_upper[i] <- base$estimate[i] + tc * base$std_error[i]
      base$p_value[i]  <- ct[r, "Pr(>|t|)"]
    }
    if (!is.null(an) && f %in% rownames(an)) base$p_value[i] <- an[f, "Pr(>F)"]
  }
  base
}
