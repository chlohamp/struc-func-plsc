#!/bin/bash
#SBATCH --job-name=sfp-submit-all
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
# submit-all.sh - submit the whole pipeline as a chain of SLURM jobs.
# Each step only starts if the steps it needs finished without error.
#
#   cd /home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc/code
#   sbatch submit-all.sh            # run everything
#   sbatch submit-all.sh 1b         # start from the PLSCs (extraction already done)
#   sbatch submit-all.sh 2          # LMEs + ML only (PLSCs already done)
#   sbatch submit-all.sh 3          # ML only
#
# Runs the variant in PLSC_VARIANT (default katie-y4-vars), e.g. Year 4 LMEs only:
#   PLSC_VARIANT=katie-y4-vars sbatch submit-all.sh 2
# For PLSC-only runs of baseline / Y2 / Y4 use submit-katie.sh instead.
#
# Dependency graph:
#   1a extract -> 1b PLSC [rni, rnd] -> 2 LMEs [rni, rnd] -> 3b mixed-model trees [rni, rnd]
#                                    -> 1d circular BR plots [rni, rnd]
#                                    -> 3a random forest [one task per measure] -> 3c ML summary
#
# Check on jobs:   squeue -u $USER
# Logs:            /home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc/code/log/
# =============================================================================
HPC_DIR=/home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc/code
mkdir -p /home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc/code/log   # SLURM won't create the log dir itself
export PLSC_VARIANT=${PLSC_VARIANT:-katie-y4-vars}
echo "Variant: ${PLSC_VARIANT}"

START=${1:-1a}
after() { [ -n "$1" ] && echo "--dependency=afterok:$1"; }
j1a=""; j1b=""; j2=""

if [ "$START" = "1a" ]; then
  j1a=$(sbatch --parsable ${HPC_DIR}/1a-extract.sbatch) || exit 1
  echo "1a extract          -> job ${j1a}"
fi
if [ "$START" = "1a" ] || [ "$START" = "1b" ]; then
  j1b=$(sbatch --parsable $(after "$j1a") ${HPC_DIR}/1b-plsc.sbatch) || exit 1
  echo "1b PLSC (rni, rnd)  -> job ${j1b}"
  j1d=$(sbatch --parsable $(after "$j1b") ${HPC_DIR}/1d-circular.sbatch) || exit 1
  echo "1d circular plots   -> job ${j1d}"
fi
if [ "$START" != "3" ]; then
  j2=$(sbatch --parsable $(after "$j1b") ${HPC_DIR}/2-lme.sbatch) || exit 1
  echo "2  LMEs (rni, rnd)  -> job ${j2}"
fi
j3a=$(sbatch --parsable $(after "$j1b") ${HPC_DIR}/3a-rf.sbatch) || exit 1
echo "3a random forest    -> job ${j3a}"
j3b=$(sbatch --parsable $(after "$j2") ${HPC_DIR}/3b-lmertree.sbatch) || exit 1
echo "3b mixed trees      -> job ${j3b}"
j3c=$(sbatch --parsable --dependency=afterany:${j3a} ${HPC_DIR}/3c-ml-summary.sbatch) || exit 1
echo "3c ML summary       -> job ${j3c}"
