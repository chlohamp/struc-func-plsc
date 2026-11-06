# =============================================================================
# config.R - single source of truth for paths, tables, and variable lists
# -----------------------------------------------------------------------------
# Every script in code/ sources this file. It figures out whether it is running
# on the FIU HPC or on your laptop and points to the right data:
#
#   HPC   -> real ABCD 7.0 tables in /home/data/nbc/Laird_ABCD/7_0_data/...
#   local -> fake ABCD-style tables in dset/
#
# Inputs (raw ABCD tables, real or fake) are only ever read. Everything the
# pipeline makes - cleaned/merged tables, PLSC results, figures, LME results -
# is written to derivatives/.
#
# Design (Year 4):
#   Two separate PLSCs, each with the same rs-FC block:
#     PLSC "rni":  rs-FC (78) x cellular density, RNI (68 Desikan GM ROIs)
#     PLSC "rnd":  rs-FC (78) x neurite density,  RND (68 Desikan GM ROIs)
#   then LMEs of the latent scores on reward / ER / EF measures (Year 4).
#
# Override from the shell if needed, e.g.
#   PLSC_ENV=local PLSC_BLOCK=rnd Rscript 2a-build-reg-data.R
#
# Anything marked  # VERIFY  is a best guess at the ABCD 7.0 table/column name.
# Run 0-inspect-release.R on the HPC to look up the real names and edit here.
# =============================================================================

# ---- 1. Where am I running? --------------------------------------------------
HPC_PROJECT_DIR <- "/home/data/nbc/misc-projects/struc-func-plsc"
HPC_RELEASE_DIR <- "/home/data/nbc/Laird_ABCD/7_0_data/tabulated/release_abcd"

PLSC_ENV <- Sys.getenv("PLSC_ENV", unset = if (dir.exists("/home/data/nbc")) "hpc" else "local")

project_dir <- Sys.getenv("PLSC_PROJECT_DIR", unset = NA)
if (is.na(project_dir) || project_dir == "") {
  project_dir <- if (PLSC_ENV == "hpc") HPC_PROJECT_DIR else path.expand("~/Desktop/struc-func-plsc")
}

release_dir <- if (PLSC_ENV == "hpc") HPC_RELEASE_DIR else file.path(project_dir, "dset")

# All outputs. Shared extraction files go here directly; each PLSC gets its own
# sub-folder, derivatives/plsc-rni/ and derivatives/plsc-rnd/ (see plsc_dirs()).
# deriv_dir <- file.path(project_dir, "derivatives")                        # main analysis
# deriv_dir <- file.path(project_dir, "derivatives", "katie-baseline-vars")  # Bottenhorn et al. covariates, baseline
deriv_dir <- file.path(project_dir, "derivatives", "katie-y4-vars")          # Bottenhorn et al. covariates, Year 4
# deriv_dir <- file.path(project_dir, "derivatives", "katie-Y2-vars")        # Bottenhorn et al. covariates, Year 2
dir.create(deriv_dir, showWarnings = FALSE, recursive = TRUE)

# Headless HPC nodes have no X11 display; cairo lets png() work without one.
options(bitmapType = "cairo")

# ---- 2. Iterations -----------------------------------------------------------
# Full 10,000 on the HPC; a small number locally so the test run takes seconds.
n_iter_perm <- as.integer(Sys.getenv("PLSC_NITER", unset = if (PLSC_ENV == "hpc") 10000 else 100))
n_iter_boot <- n_iter_perm
set.seed(as.integer(Sys.getenv("PLSC_SEED", unset = 42)))

# ---- 3. File format ----------------------------------------------------------
# ABCD ships every table as both <table>.parquet and <table>.tsv. Parquet needs
# the R 'arrow' package; without it (or if the file is missing) we read the TSV.
data_format <- Sys.getenv("PLSC_DATA_FORMAT", unset = "parquet")   # "parquet" or "tsv"

# ---- 4. Identifiers & sessions -----------------------------------------------
id_col      <- "participant_id"
session_col <- "session_id"

ses_y4       <- "ses-04A"                                                   # checked vs 7.0
ses_baseline <- "ses-00A"                                                   # checked vs 7.0
# "Most recent available, up to Year 4": tried in this order, first non-missing wins
ses_latest   <- c("ses-04A", "ses-03A", "ses-02A", "ses-01A", "ses-00A")   # checked vs 7.0

session_brain <- ses_y4        # imaging (rs-FC, RNI, RND, motion, QC, scanner) - Year 4 (katie-y4-vars)
# session_brain <- ses_baseline  # baseline (katie-baseline-vars), as in Bottenhorn et al.
# session_brain <- "ses-02A"      # Year 2 (katie-Y2-vars)
# sessions up to and including session_brain, most recent first (baseline -> ses-00A only)
ses_upto_brain <- ses_latest[match(session_brain, ses_latest):length(ses_latest)]
# Sites dropped from the sample (ab_g_dyn__design_site codes). 15 = UPMC, excluded at
# baseline by Bottenhorn et al. for hardware issues. Leave empty (c()) for Year 4.
# exclude_sites <- c(15)   # baseline
exclude_sites <- c()        # Year 2 / Year 4: site 15 kept (its exclusion was for baseline hardware issues)
session_lme   <- ses_y4     # reward / ER / EF measures

# Codes that mean "missing" in ABCD questionnaires. Applied to covariates and
# LME predictors only (never to the imaging values).
missing_codes <- c(777, 999, 555, 888, -777, -999)

# ---- 5. Brain blocks ---------------------------------------------------------
# Function block (shared by both PLSCs): Gordon network-network correlations.
# 12 networks (none excluded) -> 66 between + 12 within = 78 variables.
rsfc_block <- list(
  table   = "mr_y_rsfmri__corr__gpnet",            # checked vs 7.0
  prefix  = "mr_y_rsfmri__corr__gpnet__",          # checked vs 7.0
  exclude = "(__non__|__non_mean$)",               # drop the "none" network
  upper_triangle = TRUE,                           # ABCD 7.0 ships the full symmetric 13x13 matrix (a__b == b__a): keep each pair once
  n_expected = 78,
  label   = "rs-FC (Gordon networks)"
)

# Structure blocks: one PLSC each. 34 lh + 34 rh Desikan cortical GM ROIs = 68.
struct_blocks <- list(
  rni = list(
    table   = "mr_y_rsi__rni__gm__dsk",            # checked against 7.0 release (restricted normalized isotropic, GM)
    prefix  = "mr_y_rsi__rni__gm__dsk__",
    exclude = "dsk__(lh|rh)_mean$",                # drop hemisphere averages
    n_expected = 68,
    label   = "Cellular density (RNI)"
  ),
  rnd = list(
    table   = "mr_y_rsi__rnd__gm__dsk",            # checked against 7.0 release (restricted normalized directional, GM)
    prefix  = "mr_y_rsi__rnd__gm__dsk__",
    exclude = "dsk__(lh|rh)_mean$",                # drop hemisphere averages
    n_expected = 68,
    label   = "Neurite density (RND)"
  )
)
plsc_blocks <- names(struct_blocks)

# QC inclusion flags at session_brain (1 = include). NULL to skip.
qc_table <- "mr_y_qc__incl"                                    # checked vs 7.0
qc_flags <- c(
  "mr_y_qc__incl__rsfmri_indicator",                           # checked vs 7.0
  "mr_y_qc__incl__dmri_indicator"                              # checked vs 7.0
)

# ---- 6. Covariates -----------------------------------------------------------
# name used in models = list(table, column, sessions)
#   sessions = NULL      -> static table (one row per participant)
#   sessions = ses_y4    -> that wave only
#   sessions = ses_latest-> most recent non-missing value up to Year 4
# The session each value came from is saved in covariate-sessions.csv.
covariate_map <- list(
  # names checked against the ABCD 7.0 release (0-inspect-release.R, Nov 2026)
  interview_age          = list("ab_g_dyn",     "ab_g_dyn__visit_age",                 session_brain),
  demo_sex_v2            = list("ab_g_stc",     "ab_g_stc__cohort_sex",                NULL),
  # demo_prnt_age_v2     = list("ab_p_demo",    "ab_p_demo__age__slf_001",             ses_latest),
  # demo_prnt_ed_v2_2yr_l = list("ab_p_demo",    "ab_p_demo__edu__slf_001__v02",        ses_latest), # v02 = item version used from ses-02A on
  # demo_prtnr_ed_v2_2yr_l = list("ab_p_demo",    "ab_p_demo__edu__prtnr_001__v01",      ses_latest), # v01 = version used from ses-02A on
  # demo_comb_income_v2  = list("ab_p_demo",    "ab_p_demo__income__hhold_001__v01",   ses_latest), # v01 = version used from ses-01A on
  # demo_origin_v2       = list("ab_p_demo",    "ab_p_demo__country_001",              ses_baseline), # youth's birth country (baseline only); recoded below to US vs not
  handedness             = list("nc_y_ehis",    "nc_y_ehis_score",                     ses_upto_brain), # Edinburgh: 1 right, 2 left, 3 mixed (Bottenhorn et al.)
  mri_info_manufacturer  = list("ab_g_dyn",     "ab_g_dyn__design_mr__manufact",       session_brain),
  rsfmri_meanmotion      = list("mr_y_qc__mot", "mr_y_qc__mot__rsfmri__mot_mean",      session_brain),     # mean FD, rs-fMRI
  dmri_meanmotion        = list("mr_y_qc__mot", "mr_y_qc__mot__dmri__mot_mean",        session_brain),     # mean FD, dMRI
  site_id_l              = list("ab_g_dyn",     "ab_g_dyn__design_site",               session_brain),
  rel_family_id          = list("ab_g_stc",     "ab_g_stc__design_id__fam",            NULL)
  # parent gender identity: no such column in the 7.0 ab_p_demo table - dropped
)

# Optional recodes applied in 1a after missing codes are removed (name = function)
covariate_recode <- list(
  # demo_origin_v2 = function(x) ifelse(is.na(x), NA, ifelse(x == 189, "US", "non-US"))  # 189 = USA incl. territories
)

# Bottenhorn et al. covariates: age, sex, handedness, site, scanner manufacturer
categorical_covars <- c("demo_sex_v2", "handedness", "mri_info_manufacturer")
numerical_covars   <- c("interview_age")
# Original (extra SES/demographic covariates) - uncomment to go back:
# categorical_covars <- c("demo_sex_v2", "demo_origin_v2", "mri_info_manufacturer")
# numerical_covars   <- c("interview_age", "demo_prnt_age_v2", "demo_prnt_ed_v2_2yr_l",
#                         "demo_prtnr_ed_v2_2yr_l", "demo_comb_income_v2")

# Head motion is an inclusion/exclusion criterion, NOT a covariate: 1a drops
# anyone above these mean-FD cutoffs (applied to the one shared sample, so the
# RNI, RND and rs-FC analyses keep the same participants). The motion values
# are still saved in covariate.csv for describing the sample.
motion_max_rsfmri <- 0.2   # rs-fMRI mean framewise displacement, mm
motion_max_dmri   <- 2.0   # dMRI mean framewise displacement, mm (dMRI FD runs ~1 mm, so not on the fMRI scale)

# Regressed out of each block before PLSC (site enters as a factor).
resid_covars_rsfc   <- c(numerical_covars, categorical_covars, "site_id_l")
resid_covars_struct <- c(numerical_covars, categorical_covars, "site_id_l")

# Fixed-effect covariates in the LMEs (site/family are the random effects).
lme_numerical_covars   <- c(numerical_covars, "rsfmri_meanmotion", "dmri_meanmotion")
lme_categorical_covars <- categorical_covars

# ---- 7. LME predictors (Year 4) ----------------------------------------------
# name = list(table, column, domain, type). Predictors that don't exist at
# session_lme are skipped with a message (e.g. some NIH Toolbox tasks are not
# given at every wave - check with 0-inspect-release.R).
lme_predictor_map <- list(
  # REWARD - BIS/BAS
  bis_sum            = list("mh_y_bisbas", "mh_y_bisbas__bis_sum__v01",     "reward", "continuous"),             # checked vs 7.0
  bas_reward_resp    = list("mh_y_bisbas", "mh_y_bisbas__bas__rr_sum__v01", "reward", "continuous"),             # checked vs 7.0
  bas_drive          = list("mh_y_bisbas", "mh_y_bisbas__bas__dr_sum",      "reward", "continuous"),             # checked vs 7.0
  bas_fun_seeking    = list("mh_y_bisbas", "mh_y_bisbas__bas__fs_sum",      "reward", "continuous"),             # checked vs 7.0
  # REWARD - UPPS-P
  upps_neg_urgency   = list("mh_y_upps",   "mh_y_upps__nurg_sum",           "reward", "continuous"),             # checked vs 7.0
  upps_pos_urgency   = list("mh_y_upps",   "mh_y_upps__purg_sum",           "reward", "continuous"),             # checked vs 7.0
  upps_lack_premed   = list("mh_y_upps",   "mh_y_upps__plan_sum",           "reward", "continuous"),             # checked vs 7.0 (lack of planning/premeditation)
  upps_lack_persev   = list("mh_y_upps",   "mh_y_upps__pers_sum",           "reward", "continuous"),             # checked vs 7.0 (lack of perseverance)
  upps_sens_seeking  = list("mh_y_upps",   "mh_y_upps__sens_sum",           "reward", "continuous"),             # checked vs 7.0
  # EMOTION REGULATION - ERQ
  erq_reappraisal    = list("mh_y_erq",    "mh_y_erq__reapp_mean",          "emotion_regulation", "continuous"), # checked vs 7.0
  erq_suppression    = list("mh_y_erq",    "mh_y_erq__suppr_mean",          "emotion_regulation", "continuous"), # checked vs 7.0
  # EMOTION REGULATION - Difficulties in Emotion Regulation (ABCD: parent-report DERS-P)
  # 7.0 has no DERS total, only these four subscale means
  ders_attuned       = list("mh_p_ders",   "mh_p_ders__attun_mean",         "emotion_regulation", "continuous"), # checked vs 7.0
  ders_catastrophize = list("mh_p_ders",   "mh_p_ders__catast_mean",        "emotion_regulation", "continuous"), # checked vs 7.0
  ders_distracted    = list("mh_p_ders",   "mh_p_ders__distract_mean",      "emotion_regulation", "continuous"), # checked vs 7.0
  ders_neg_secondary = list("mh_p_ders",   "mh_p_ders__negscnd_mean",       "emotion_regulation", "continuous"), # checked vs 7.0
  # EXECUTIVE FUNCTION - NIH Toolbox (fully corrected T-scores) + flanker task accuracy
  nihtb_flanker      = list("nc_y_nihtb",  "nc_y_nihtb__flnkr__fullcor_tscore",  "executive_function", "continuous"), # checked vs 7.0 (fully corrected T)
  flanker_incongr_acc = list("nc_y_flnkr", "nc_y_flnkr__incongr_acc",           "executive_function", "continuous"), # checked vs 7.0; ~1,456 at Y4
  nihtb_cardsort     = list("nc_y_nihtb",  "nc_y_nihtb__crdst__fullcorr_tscore", "executive_function", "continuous"), # checked vs 7.0 (fully corrected T); only ~19 at Y4, so skipped by min_n_lme
  nihtb_pattern      = list("nc_y_nihtb",  "nc_y_nihtb__pttcp__fullcor_tscore",  "executive_function", "continuous")  # checked vs 7.0 (fully corrected T)
)
lme_predictor_map <- lapply(lme_predictor_map, function(x)
  list(table = x[[1]], col = x[[2]], domain = x[[3]], type = x[[4]]))
lme_predictors     <- names(lme_predictor_map)
lme_predictor_cats <- lme_predictors[vapply(lme_predictor_map, function(x) x$type == "categorical", logical(1))]

# ---- 7b. Puberty (caregiver-report Pubertal Development Scale) ---------------
# Same approach as Bottenhorn et al. (2025, J Neurosci): caregiver PDS, summed
# items mapped to sex-specific categories 1 = pre, 2 = early, 3 = mid,
# 4 = late, 5 = post-pubertal. ABCD stores the female and male category in
# separate columns; 1a picks the right one for each participant's sex.
puberty_table     <- "ph_p_pds"                   # VERIFY - table not pulled from the HPC yet
pds_female_col    <- "ph_p_pds__f_categ"          # VERIFY
pds_male_col      <- "ph_p_pds__m_categ"          # VERIFY
sex_female_value  <- 2                            # checked vs 7.0 (ab_g_stc__cohort_sex: 1 = male, 2 = female)
# Derived in 1a-extract-abcd.R -> derivatives/puberty.csv
#   pds_stage  : PDS category at Year 4 (1-5)                              [primary moderator]
#   pds_tempo  : (stage at Y4 - stage at baseline) / years between visits
#   pds_timing : stage at Y4 relative to same-sex peers of the same age
#                (residual of stage ~ age, within sex); positive = earlier maturing
puberty_vars      <- c("pds_stage", "pds_tempo", "pds_timing")
puberty_moderator <- "pds_stage"
puberty_by_sex    <- TRUE    # also run the moderation LMEs separately in girls and boys

# ---- 7c. Machine learning (step 3) -------------------------------------------
# 3a: random forest predicting each Year 4 behaviour measure from the PLSC
#     latent scores (+ puberty), with site-grouped cross-validation.
# 3b: linear mixed-model trees (glmertree) - does the score~measure slope
#     differ across puberty / sex / age subgroups?
ml_outcomes      <- lme_predictors                       # behaviour measures to predict
ml_covariates    <- c("interview_age", "demo_sex_v2", "demo_comb_income_v2", "demo_prnt_ed_v2_2yr_l",
                      "rsfmri_meanmotion", "dmri_meanmotion", "mri_info_manufacturer")
ml_puberty_features <- c("pds_stage", "pds_tempo")      # added in model M2 (timing = stage given age+sex, which RF can learn)
ml_n_trees       <- if (PLSC_ENV == "hpc") 1000 else 200
ml_n_folds       <- 10        # site-grouped folds (siblings share a site, so families stay together)
ml_n_perm        <- as.integer(Sys.getenv("PLSC_ML_NPERM", unset = if (PLSC_ENV == "hpc") 200 else 5))
ml_h_n           <- if (PLSC_ENV == "hpc") 400 else 150   # rows sampled for interaction (H) statistics
ml_late_stage    <- 4         # pds_stage >= this = "late"; below = "early/mid" (cross-stage transfer)
ml_min_group_n   <- 150       # skip the transfer test if either puberty group is smaller
ml_threads       <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = 1))
tree_partition_vars <- c("pds_stage", "demo_sex_v2", "interview_age")   # 3b splitting variables
tree_alpha       <- 0.05
tree_test        <- "slope"   # "slope": split only on differences in the measure slope (moderation); "both": slope or level
tree_minsize_frac <- 0.05     # smallest allowed subgroup = 5% of the sample
min_n_lme <- 100   # skip a model if fewer participants than this have the predictor

# ---- 8. PLSC settings --------------------------------------------------------
# Permutation-p threshold for a significant dimension. With only 100 local
# permutations the smallest possible p is 0.01, so the local test uses 0.05.
sig_alpha        <- as.numeric(Sys.getenv("PLSC_SIG_ALPHA", unset = if (PLSC_ENV == "hpc") 0.01 else 0.05))
nf2keep          <- 5      # dimensions carried into the bootstrap
br_threshold     <- 2.5    # |bootstrap ratio| for a feature to be "significant"
max_dims_to_plot <- 4

# ---- 9. Helpers --------------------------------------------------------------
`%||%` <- function(a, b) if (is.null(a)) b else a

# Output folders for one PLSC ("rni" or "rnd")
plsc_dirs <- function(block) {
  stopifnot(block %in% plsc_blocks)
  d <- list(plsc = file.path(deriv_dir, paste0("plsc-", block)))
  d$fig <- file.path(d$plsc, "figures")
  d$reg <- file.path(d$plsc, "regression")
  for (x in d) dir.create(x, showWarnings = FALSE, recursive = TRUE)
  d
}

ml_dir <- function() { d <- file.path(deriv_dir, "ml"); dir.create(d, showWarnings = FALSE, recursive = TRUE); d }

# Significant dimensions of one PLSC (falls back to Dim1 so pipelines can be tested)
sig_dims <- function(block) {
  f <- file.path(deriv_dir, paste0("plsc-", block), "significant_dimensions.csv")
  d <- if (file.exists(f)) read.csv(f)$dimension else integer(0)
  env <- Sys.getenv("PLSC_DIMS", unset = "")
  if (nzchar(env)) d <- as.integer(strsplit(env, ",")[[1]])
  if (length(d) == 0) d <- 1L
  d[d <= nf2keep]
}

# Which PLSC(s) a script should run: PLSC_BLOCK=rni / rnd, or both if unset
blocks_to_run <- function() {
  b <- Sys.getenv("PLSC_BLOCK", unset = "")
  if (nzchar(b)) strsplit(b, ",")[[1]] else plsc_blocks
}

read_abcd_table <- function(table, cols = NULL, dir = release_dir, format = data_format) {
  pq  <- file.path(dir, paste0(table, ".parquet"))
  tsv <- file.path(dir, paste0(table, ".tsv"))
  use_parquet <- format == "parquet" && file.exists(pq) && requireNamespace("arrow", quietly = TRUE)
  if (use_parquet) {
    # newer arrow reads zero columns if col_select = NULL is passed explicitly
    df <- if (is.null(cols)) as.data.frame(arrow::read_parquet(pq))
          else as.data.frame(arrow::read_parquet(pq, col_select = tidyselect::any_of(cols)))
    src <- pq
  } else if (file.exists(tsv)) {
    df <- utils::read.delim(tsv, sep = "\t", header = TRUE, stringsAsFactors = FALSE,
                            na.strings = c("", "NA", "n/a"), check.names = FALSE)
    if (!is.null(cols)) df <- df[, intersect(cols, colnames(df)), drop = FALSE]
    src <- tsv
  } else {
    stop(sprintf("Table '%s' not found as .parquet or .tsv in %s", table, dir))
  }
  message(sprintf("  read %-28s %6d rows x %4d cols  (%s)", table, nrow(df), ncol(df), basename(src)))
  df
}

message(sprintf("[config] env=%s | release=%s | out=%s | brain=%s | nIter=%d",
                PLSC_ENV, release_dir, deriv_dir, session_brain, n_iter_perm))
