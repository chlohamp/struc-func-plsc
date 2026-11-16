#!/bin/bash
#SBATCH --job-name=sfp-submit-katie
#SBATCH --time=00:10:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --account=acc_nbc
#SBATCH --qos=highmem1
#SBATCH --partition=highmem1-sapphirerapids
#SBATCH --output=/home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc/code/log/%x_%j.out
#SBATCH --error=/home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc/code/log/%x_%j.err
# =============================================================================
# submit-katie.sh - PLSC only (no regressions) with the Bottenhorn et al.
# (bioRxiv 2026) covariates: age, sex, handedness, site, scanner manufacturer.
# Motion is exclusion-only, same cutoffs as the main analysis (config.R).
#
#   cd /home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc/code
#   sbatch submit-katie.sh y4          # Year 4     -> derivatives/katie-y4-vars/
#   sbatch submit-katie.sh y2          # Year 2     -> derivatives/katie-Y2-vars/
#   sbatch submit-katie.sh baseline    # baseline   -> derivatives/katie-baseline-vars/ (site 15 dropped)
#   sbatch submit-katie.sh all         # all three, in parallel
#
# Each wave writes to its own folder, so they can run at the same time.
# Chain per wave: 1a extract -> 1b PLSC [rni, rnd] -> 1d circular plots [rni, rnd]
#
# Year 4 regressions (LMEs) afterwards, on the Year 4 PLSC results:
#   PLSC_VARIANT=katie-y4-vars sbatch submit-all.sh 2
# Quick trial run first (100 permutations, finishes in minutes):
#   PLSC_NITER=100 sbatch submit-katie.sh y4
# =============================================================================
PROJECT_DIR=/home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc
HPC_DIR=${PROJECT_DIR}/code
mkdir -p ${PROJECT_DIR}/code/log      # SLURM won't create the log dir itself

case "${1:-}" in
  baseline) WAVES="katie-baseline-vars" ;;
  y2|Y2)    WAVES="katie-Y2-vars" ;;
  y4|Y4)    WAVES="katie-y4-vars" ;;
  all)      WAVES="katie-baseline-vars katie-Y2-vars katie-y4-vars" ;;
  *) echo "Usage: sbatch submit-katie.sh baseline|y2|y4|all" >&2; exit 1 ;;
esac

for V in ${WAVES}; do
  export PLSC_VARIANT=${V}       # sbatch passes the environment into each job
  tag=${V%-vars}; tag=${tag#katie-}   # baseline / Y2 / y4, for job names
  echo "=== ${V}"
  j1a=$(sbatch --parsable --job-name=k${tag}-1a-extract  ${HPC_DIR}/1a-extract.sbatch) || exit 1
  echo "1a extract          -> job ${j1a}"
  j1b=$(sbatch --parsable --job-name=k${tag}-1b-plsc     --dependency=afterok:${j1a} ${HPC_DIR}/1b-plsc.sbatch) || exit 1
  echo "1b PLSC (rni, rnd)  -> job ${j1b}"
  j1d=$(sbatch --parsable --job-name=k${tag}-1d-circular --dependency=afterok:${j1b} ${HPC_DIR}/1d-circular.sbatch) || exit 1
  echo "1d circular plots   -> job ${j1d}"
  echo "Outputs: ${PROJECT_DIR}/derivatives/${V}/"
done
echo "Check on jobs: squeue -u \$USER    Logs: ${PROJECT_DIR}/code/log/"
