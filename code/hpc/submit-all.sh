#!/bin/bash
# =============================================================================
# submit-all.sh - submit the whole pipeline as a chain of SLURM jobs.
# Each step only starts if the steps it needs finished without error.
#
#   cd /home/data/nbc/misc-projects/struc-func-plsc/code
#   bash hpc/submit-all.sh            # run everything
#   bash hpc/submit-all.sh 1b         # start from the PLSCs (extraction already done)
#   bash hpc/submit-all.sh 2          # LMEs + ML only (PLSCs already done)
#   bash hpc/submit-all.sh 3          # ML only
#
# Dependency graph:
#   1a extract -> 1b PLSC [rni, rnd] -> 2 LMEs [rni, rnd] -> 3b mixed-model trees [rni, rnd]
#                                    -> 1d circular BR plots [rni, rnd]
#                                    -> 3a random forest [one task per measure] -> 3c ML summary
#
# Check on jobs:   squeue -u $USER
# Logs:            /home/data/nbc/misc-projects/struc-func-plsc/log/
# =============================================================================
HPC_DIR=/home/data/nbc/misc-projects/struc-func-plsc/code/hpc
mkdir -p /home/data/nbc/misc-projects/struc-func-plsc/log   # SLURM won't create the log dir itself

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
