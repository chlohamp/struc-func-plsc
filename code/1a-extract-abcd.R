# =============================================================================
# 1a-extract-abcd.R - pull the PLSC blocks, covariates and LME measures
# -----------------------------------------------------------------------------
# Reads the ABCD tables named in config.R (.parquet if arrow is available,
# otherwise .tsv). Imaging comes from session_brain (Year 4); covariates come
# from whichever wave config.R says (static, Year 4, or most recent available);
# LME measures come from session_lme (Year 4).
#
# Keeps participants who pass QC and are complete on rs-FC, RNI, RND and all
# covariates, so BOTH PLSCs use the same people. Writes row-aligned CSVs:
#
#   clean-rsfc.csv  clean-rni.csv  clean-rnd.csv   participant_id + features
#   covariate.csv            participant_id + covariates (+ site, family)
#   covariate-sessions.csv   which wave each covariate value came from
#   lme-measures.csv         participant_id + reward / ER / EF (Year 4; may have NAs)
#   extraction-log.csv       N remaining after each step
#
# Run:  Rscript 1a-extract-abcd.R   (from code/; HPC: hpc/1a-extract.sbatch)
# =============================================================================
code_dir <- Sys.getenv("PLSC_CODE_DIR", unset = "")
if (!nzchar(code_dir)) {
  script_path <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (is.null(script_path)) {
    script_arg <- grep("^--file=", commandArgs(), value = TRUE)
    if (length(script_arg)) script_path <- sub("^--file=", "", script_arg[[1]])
  }
  code_dir <- if (is.null(script_path)) "." else dirname(normalizePath(script_path))
}
source(file.path(code_dir, "config.R"))
suppressPackageStartupMessages(library(dplyr))

log_n <- data.frame(step = character(), n = integer())
note  <- function(step, n) {
  log_n <<- rbind(log_n, data.frame(step = step, n = n))
  message(sprintf("  %-48s N = %d", step, n))
}
recode_missing <- function(x) { if (is.numeric(x)) x[x %in% missing_codes] <- NA; x }
at_session <- function(df, ses) {
  df[[session_col]] <- as.character(df[[session_col]])
  df <- df[df[[session_col]] == ses, setdiff(colnames(df), session_col), drop = FALSE]
  df[!duplicated(df[[id_col]]), , drop = FALSE]
}

# ---- brain blocks -------------------------------------------------------------
message("Reading imaging (", session_brain, ") ...")
pick_features <- function(b) {
  df   <- at_session(read_abcd_table(b$table), session_brain)
  feat <- grep(paste0("^", b$prefix), colnames(df), value = TRUE)
  if (!is.null(b$exclude) && nzchar(b$exclude)) feat <- feat[!grepl(b$exclude, feat)]
  if (isTRUE(b$upper_triangle)) {                      # <prefix><a>__<b>_mean: keep a <= b only
    ab   <- regmatches(sub(b$prefix, "", feat, fixed = TRUE),
                       regexec("^([a-z]+)__([a-z]+)_mean$", sub(b$prefix, "", feat, fixed = TRUE)))
    keep <- vapply(ab, function(m) length(m) == 3 && m[2] <= m[3], logical(1))
    feat <- feat[keep]
  }
  if (length(feat) == 0) stop("No columns in ", b$table, " start with ", b$prefix, " - check config.R")
  msg <- sprintf("    %s: %d features kept from %s", b$label, length(feat), b$table)
  if (!is.null(b$n_expected) && length(feat) != b$n_expected) {
    warning(sprintf("%s: expected %d features but found %d - check prefix/exclude in config.R",
                    b$label, b$n_expected, length(feat)))
    msg <- paste(msg, sprintf("(EXPECTED %d!)", b$n_expected))
  }
  message(msg)
  df[, c(id_col, feat)]
}
blocks <- c(list(rsfc = rsfc_block), struct_blocks)
brain  <- lapply(blocks, pick_features)

# ---- covariates (session per variable) -------------------------------------------
message("Reading covariates ...")
get_var <- function(spec) {
  tb <- spec[[1]]; col <- spec[[2]]; sessions <- spec[[3]]
  df <- read_abcd_table(tb, cols = c(id_col, session_col, col))
  if (!col %in% colnames(df)) stop("Column ", col, " not found in ", tb)
  # ABCD 7.0 parquet stores coded answers as text ("1", "777"): make them numeric
  if (is.factor(df[[col]])) df[[col]] <- as.character(df[[col]])
  if (is.character(df[[col]]) && all(grepl("^-?[0-9.]+$", na.omit(df[[col]]))))
    df[[col]] <- as.numeric(df[[col]])
  df[[col]] <- recode_missing(df[[col]])
  if (is.null(sessions) || !session_col %in% colnames(df)) {              # static
    df <- df[!duplicated(df[[id_col]]), ]
    return(data.frame(id = df[[id_col]], value = df[[col]], ses = "static", stringsAsFactors = FALSE))
  }
  df <- df[df[[session_col]] %in% sessions & !is.na(df[[col]]), ]
  df$rank <- match(df[[session_col]], sessions)                           # priority order
  df <- df[order(df[[id_col]], df$rank), ]
  df <- df[!duplicated(df[[id_col]]), ]
  data.frame(id = df[[id_col]], value = df[[col]], ses = df[[session_col]], stringsAsFactors = FALSE)
}
cov_list <- lapply(covariate_map, get_var)
all_ids  <- unique(unlist(lapply(cov_list, `[[`, "id")))
covar    <- data.frame(all_ids, stringsAsFactors = FALSE); colnames(covar) <- id_col
cov_ses  <- covar
for (v in names(cov_list)) {
  m <- match(covar[[id_col]], cov_list[[v]]$id)
  covar[[v]]   <- cov_list[[v]]$value[m]
  cov_ses[[v]] <- cov_list[[v]]$ses[m]
}

if (exists("covariate_recode")) for (v in intersect(names(covariate_recode), colnames(covar)))
  covar[[v]] <- covariate_recode[[v]](covar[[v]])

# ---- LME predictors (session_lme) --------------------------------------------------
message("Reading LME measures (", session_lme, ") ...")
preds <- NULL
for (tb in unique(vapply(lme_predictor_map, `[[`, "", "table"))) {
  vars <- lme_predictor_map[vapply(lme_predictor_map, `[[`, "", "table") == tb]
  src  <- vapply(vars, `[[`, "", "col")
  df   <- tryCatch(read_abcd_table(tb, cols = c(id_col, session_col, src)),
                   error = function(e) { warning(conditionMessage(e)); NULL })
  if (is.null(df)) next
  df   <- at_session(df, session_lme)
  have <- intersect(src, colnames(df))
  if (length(have) < length(src)) warning("Not found in ", tb, ": ", paste(setdiff(src, have), collapse = ", "))
  df <- df[, c(id_col, have), drop = FALSE]
  colnames(df) <- c(id_col, names(src)[match(have, src)])
  df[, -1] <- lapply(df[, -1, drop = FALSE], recode_missing)
  preds <- if (is.null(preds)) df else full_join(preds, df, by = id_col)
}

# ---- puberty (caregiver PDS) ----------------------------------------------------------
# Stage at Year 4, tempo since baseline, and timing relative to same-sex,
# same-age peers. Missing puberty does NOT drop anyone from the PLSC sample;
# puberty models simply use the participants who have it.
message("Reading puberty (caregiver PDS) ...")
puberty <- tryCatch({
  pds <- read_abcd_table(puberty_table, cols = c(id_col, session_col, pds_female_col, pds_male_col))
  sex <- covar[match(pds[[id_col]], covar[[id_col]]), "demo_sex_v2"]
  pds$stage <- ifelse(sex == sex_female_value, pds[[pds_female_col]], pds[[pds_male_col]])
  pds$stage <- recode_missing(pds$stage)
  ages <- read_abcd_table(covariate_map$interview_age[[1]],
                          cols = c(id_col, session_col, covariate_map$interview_age[[2]]))
  get_wave <- function(df, col, ses) df[[col]][match(paste(all_ids, ses), paste(df[[id_col]], df[[session_col]]))]
  out <- data.frame(all_ids, stringsAsFactors = FALSE); colnames(out) <- id_col
  out$pds_stage   <- get_wave(pds, "stage", session_brain)
  stage_base      <- get_wave(pds, "stage", ses_baseline)
  age_y4          <- get_wave(ages, covariate_map$interview_age[[2]], session_brain)
  age_base        <- get_wave(ages, covariate_map$interview_age[[2]], ses_baseline)
  out$pds_tempo   <- (out$pds_stage - stage_base) / (age_y4 - age_base)
  # timing: residual of stage on age, fitted separately within each sex
  out$pds_timing  <- NA_real_
  sx <- covar$demo_sex_v2[match(out[[id_col]], covar[[id_col]])]
  for (s in unique(na.omit(sx))) {
    k <- which(sx == s & !is.na(out$pds_stage) & !is.na(age_y4))
    if (length(k) > 10) out$pds_timing[k] <- residuals(lm(out$pds_stage[k] ~ age_y4[k]))
  }
  out
}, error = function(e) { warning("Puberty not extracted: ", conditionMessage(e)); NULL })

# ---- QC + complete cases ------------------------------------------------------------
message("Filtering ...")
ids <- Reduce(intersect, lapply(brain, `[[`, id_col))
note(sprintf("have rs-FC + RNI + RND rows at %s", session_brain), length(ids))

if (length(qc_flags)) {
  qc   <- at_session(read_abcd_table(qc_table, cols = c(id_col, session_col, qc_flags)), session_brain)
  pass <- qc[[id_col]][rowSums(qc[, qc_flags, drop = FALSE] == 1, na.rm = TRUE) == length(qc_flags)]
  ids  <- intersect(ids, pass)
  note("pass QC inclusion flags", length(ids))
}

# Head-motion exclusion (cutoffs in config.R). Missing motion = excluded.
mot_ok <- covar[[id_col]][!is.na(covar$rsfmri_meanmotion) & covar$rsfmri_meanmotion <= motion_max_rsfmri &
                          !is.na(covar$dmri_meanmotion)   & covar$dmri_meanmotion   <= motion_max_dmri]
ids <- intersect(ids, mot_ok)
note(sprintf("rs-fMRI mean FD <= %.2f mm and dMRI mean FD <= %.2f mm", motion_max_rsfmri, motion_max_dmri), length(ids))

if (exists("exclude_sites") && length(exclude_sites)) {
  site_ok <- covar[[id_col]][!is.na(covar$site_id_l) & !(covar$site_id_l %in% exclude_sites)]
  ids <- intersect(ids, site_ok)
  note(sprintf("not at excluded site(s) %s", paste(exclude_sites, collapse = ", ")), length(ids))
}

for (k in names(brain)) {
  b <- brain[[k]]
  ids <- intersect(ids, b[[id_col]][complete.cases(b)])
}
note("complete on all brain features (all 3 blocks)", length(ids))

ok  <- covar[[id_col]][complete.cases(covar[, names(covariate_map)])]
ids <- sort(intersect(ids, ok))
note("complete on all covariates", length(ids))

# ---- align & write -------------------------------------------------------------------
align <- function(df) { out <- df[match(ids, df[[id_col]]), , drop = FALSE]; out[[id_col]] <- ids; out }
for (k in names(brain)) write.csv(align(brain[[k]]), file.path(deriv_dir, sprintf("clean-%s.csv", k)), row.names = FALSE)
write.csv(align(covar),   file.path(deriv_dir, "covariate.csv"),          row.names = FALSE)
write.csv(align(cov_ses), file.path(deriv_dir, "covariate-sessions.csv"), row.names = FALSE)
preds_out <- if (is.null(preds)) data.frame(ids) else align(preds)
colnames(preds_out)[1] <- id_col
write.csv(preds_out, file.path(deriv_dir, "lme-measures.csv"), row.names = FALSE)
write.csv(log_n, file.path(deriv_dir, "extraction-log.csv"), row.names = FALSE)
if (!is.null(puberty)) {
  pub_out <- align(puberty)
  write.csv(pub_out, file.path(deriv_dir, "puberty.csv"), row.names = FALSE)
  sx <- align(covar)$demo_sex_v2
  message("\nPubertal stage at ", session_brain, " (rows = sex, cols = PDS category 1 pre .. 5 post):")
  print(table(sex = sx, stage = pub_out$pds_stage, useNA = "ifany"))
}

# Summaries worth eyeballing
message("\nWhere covariate values came from (counts by wave):")
ses_tab <- lapply(names(covariate_map), function(v) table(align(cov_ses)[[v]]))
for (i in seq_along(ses_tab)) message(sprintf("  %-24s %s", names(covariate_map)[i],
                                              paste(names(ses_tab[[i]]), ses_tab[[i]], sep = "=", collapse = "  ")))
message("\nNon-missing N for each LME measure at ", session_lme, ":")
for (p in setdiff(colnames(preds_out), id_col)) message(sprintf("  %-20s %d", p, sum(!is.na(preds_out[[p]]))))
for (p in setdiff(lme_predictors, colnames(preds_out))) message(sprintf("  %-20s NOT FOUND", p))

message(sprintf("\nDone. N = %d | rs-FC = %d | RNI = %d | RND = %d features\nWrote to %s",
                length(ids), ncol(brain$rsfc) - 1, ncol(brain$rni) - 1, ncol(brain$rnd) - 1, deriv_dir))
