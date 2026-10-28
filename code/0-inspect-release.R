# =============================================================================
# 0-inspect-release.R - find the real ABCD 7.0 table / column names
# -----------------------------------------------------------------------------
# Reads only the header line of every .tsv in the release (fast, no arrow
# needed), writes a full table -> column index, and prints columns matching
# a few search terms so you can fill in the  # VERIFY  entries in config.R.
#
# Run on the HPC (login node is fine, it only reads headers):
#   cd /home/data/nbc/misc-projects/struc-func-plsc/code
#   singularity exec --cleanenv -B /home/data/nbc $SIF Rscript 0-inspect-release.R
#   # optional extra search terms:
#   ... Rscript 0-inspect-release.R bisbas erq flnkr
# =============================================================================
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "config.R"))

tsvs <- list.files(release_dir, pattern = "\\.tsv$", full.names = TRUE, recursive = TRUE)
if (length(tsvs) == 0) stop("No .tsv files found in ", release_dir)
tsv_dirs <- unique(dirname(tsvs))
if (!identical(normalizePath(tsv_dirs), normalizePath(release_dir))) {
  cat("\nNOTE: tables live in sub-folder(s):\n", paste(" ", tsv_dirs, collapse = "\n"),
      "\nSet HPC_RELEASE_DIR in config.R to the folder holding the tables.\n")
}

index <- do.call(rbind, lapply(tsvs, function(f) {
  hdr <- strsplit(readLines(f, n = 1, warn = FALSE), "\t", fixed = TRUE)[[1]]
  data.frame(table = sub("\\.tsv$", "", basename(f)), column = hdr, stringsAsFactors = FALSE)
}))
out_file <- file.path(deriv_dir, "release_column_index.csv")
write.csv(index, out_file, row.names = FALSE)
cat(sprintf("\n%d tables, %d columns indexed -> %s\n", length(tsvs), nrow(index), out_file))

terms <- c("rsfmri__corr", "rsi__rni", "rsi__rnd", "rsi", "upps", "ders", "visit_age", "site", "fam", "sex", "manufact",
           "fd_mean", "meanmotion", "incl", "income", "bisbas", "erq", "nihtb", "flnkr",
           commandArgs(trailingOnly = TRUE))

for (t in unique(terms)) {
  hits <- index[grepl(t, index$column, ignore.case = TRUE), ]
  cat(sprintf("\n=== '%s' : %d matching columns ===\n", t, nrow(hits)))
  if (nrow(hits)) {
    # show at most 5 columns per table so prefixes are easy to spot
    for (tb in unique(hits$table)) {
      cols <- hits$column[hits$table == tb]
      cat(sprintf("  %-40s %s%s\n", tb, paste(head(cols, 5), collapse = ", "),
                  if (length(cols) > 5) sprintf(" ... (+%d more)", length(cols) - 5) else ""))
    }
  }
}

# Check every table/column named in config.R: does it exist, and how many
# participants have a non-missing value at the session config.R will use?
cat("\n=== Checking names currently in config.R ===\n")
cat(sprintf("  %-6s %-26s %-40s %-10s %s\n", "", "table", "column", "session", "N non-missing"))
check_var <- function(tb, col, sessions) {
  exists_col <- any(index$table == tb & index$column == col)
  n <- NA
  if (exists_col) {
    df <- read_abcd_table(tb, cols = c(id_col, session_col, col))
    v  <- recode <- df[[col]]
    if (is.numeric(v)) v[v %in% missing_codes] <- NA
    keep <- if (is.null(sessions) || !session_col %in% colnames(df)) rep(TRUE, nrow(df)) else df[[session_col]] %in% sessions
    n <- length(unique(df[[id_col]][keep & !is.na(v)]))
  }
  ses_lab <- if (is.null(sessions)) "static" else if (length(sessions) > 1) "latest<=Y4" else sessions
  cat(sprintf("  [%s] %-26s %-40s %-10s %s\n", if (exists_col) " ok " else "MISS", tb, col, ses_lab,
              ifelse(is.na(n), "-", n)))
}
suppressMessages({
  for (v in names(covariate_map)) check_var(covariate_map[[v]][[1]], covariate_map[[v]][[2]], covariate_map[[v]][[3]])
  for (v in names(lme_predictor_map)) check_var(lme_predictor_map[[v]]$table, lme_predictor_map[[v]]$col, session_lme)
  for (f in qc_flags) check_var(qc_table, f, session_brain)
})

cat("\n=== Brain blocks (expected counts after prefix/exclude) ===\n")
for (b in c(list(rsfc = rsfc_block), struct_blocks)) {
  cols <- index$column[index$table == b$table & startsWith(index$column, b$prefix)]
  kept <- cols[!grepl(b$exclude, cols)]
  cat(sprintf("  [%s] %-28s %-30s %3d kept (expected %d), %d excluded\n",
              if (length(kept) == b$n_expected) " ok " else "MISS", b$table, b$prefix,
              length(kept), b$n_expected, length(cols) - length(kept)))
}
