#!/bin/bash
# Run the PLSC pipeline locally with the Bottenhorn et al. covariates
# (config.R currently points deriv_dir to derivatives/katie-baseline-vars).
# Steps: 1a extract -> 1b PLSC (rni, rnd; 10,000 perm/boot, p < .01) -> 1d circular plots.
# No regressions. Usage, from the project folder:  bash code/run-katie-baseline-local.sh
set -u
cd "$(dirname "$0")"
OUT=../derivatives/katie-baseline-vars
mkdir -p "$OUT"
LOG="$OUT/run.log"
command -v Rscript >/dev/null || { echo "Rscript not found - install R first" | tee "$LOG"; exit 1; }
export PLSC_NITER=10000 PLSC_SIG_ALPHA=0.01
{
  echo "=== start $(date)"
  echo "=== 1a extract"
  Rscript 1a-extract-abcd.R || exit 1
  for b in rni rnd; do
    echo "=== 1b PLSC $b  $(date)"
    Rscript -e "rmarkdown::render('1b-plsc-clean.Rmd', params = list(block = '$b'), output_dir = '$OUT/plsc-$b', knit_root_dir = getwd())" || exit 1
  done
  echo "=== 1d circular plots"
  Rscript 1d-plsc-circular-plots.R
  echo "=== done $(date)"
} 2>&1 | tee "$LOG"
