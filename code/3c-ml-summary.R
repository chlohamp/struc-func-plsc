# =============================================================================
# 3c-ml-summary.R - combine the per-measure random forest results (3a)
# -----------------------------------------------------------------------------
# Output (derivatives/ml/):
#   ml-summary.csv          one row per measure: R2 for M0/M1/M2/EN2, gain from
#                           brain and from puberty, permutation p (+ FDR across
#                           measures), strongest brain x puberty interaction,
#                           cross-stage transfer drop
#   ml-cv-performance.csv   long format, all models x measures
#   ml-interaction-H.csv    H^2 (brain x puberty, brain x age) for all measures
#   ml-r2-by-model.png      out-of-sample R2 per measure and model
# =============================================================================
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "config.R"))
suppressPackageStartupMessages(library(ggplot2))

od <- ml_dir()
read_all <- function(f) {
  fs <- Sys.glob(file.path(od, "*", f))
  if (!length(fs)) return(NULL)
  do.call(rbind, lapply(fs, function(x) cbind(measure = basename(dirname(x)), read.csv(x))))
}
summ <- read_all("summary.csv")
if (is.null(summ)) stop("No 3a results in ", od)
summ$p_model_fdr   <- p.adjust(summ$p_model, "fdr")
summ$p_puberty_fdr <- p.adjust(summ$p_puberty, "fdr")
summ <- summ[order(summ$domain, -summ$r2_M2), ]
write.csv(summ, file.path(od, "ml-summary.csv"), row.names = FALSE)

perf <- read_all("cv_performance.csv")
write.csv(perf, file.path(od, "ml-cv-performance.csv"), row.names = FALSE)
H <- read_all("interaction_H.csv")
if (!is.null(H)) write.csv(H, file.path(od, "ml-interaction-H.csv"), row.names = FALSE)

perf$model <- factor(perf$model, levels = c("M0", "M1", "M2", "EN2"),
                     labels = c("M0 covariates", "M1 + brain", "M2 + brain + puberty", "EN2 elastic net"))
p <- ggplot(perf, aes(measure, r2, fill = model)) + geom_col(position = position_dodge(0.8), width = 0.75) +
  geom_hline(yintercept = 0, linewidth = 0.3) + coord_flip() + theme_minimal(base_size = 9) +
  labs(x = NULL, y = "Out-of-sample R2 (site-grouped CV)", fill = NULL,
       title = "Predicting Year 4 behaviour from microstructure-function coupling patterns")
ggsave(file.path(od, "ml-r2-by-model.png"), p, width = 8, height = 6, dpi = 150)

print(summ[, c("measure", "domain", "N", "r2_M0", "r2_M1", "r2_M2", "r2_EN2", "p_model_fdr", "p_puberty_fdr")], digits = 2)
message("Wrote ", od)
