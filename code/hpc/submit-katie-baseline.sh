#!/bin/bash
# =============================================================================
# submit-katie-baseline.sh - PLSC only (no regressions) with the Bottenhorn et al.
# (bioRxiv 2026) covariates: age, sex, handedness, site, scanner manufacturer.
# Motion is exclusion-only, same cutoffs as the main analysis (config.R).
# Everything is written to derivatives/katie-baseline-vars/, so the main
# results in derivatives/ are not touched.
#
#   cd /home/data/nbc/misc-projects/struc-func-plsc/code
#   bash hpc/submit-katie-baseline.sh
#
# Chain: 1a extract -> 1b PLSC [rni, rnd] -> 1d circular plots [rni, rnd]
# =============================================================================
export PLSC_VARIANT=katie-baseline-vars          # sbatch passes this into each job
HPC_DIR=/home/data/nbc/misc-projects/struc-func-plsc/code/hpc
mkdir -p /home/data/nbc/misc-projects/struc-func-plsc/log

j1a=$(sbatch --parsable --job-name=kbv-1a-extract  ${HPC_DIR}/1a-extract.sbatch) || exit 1
echo "1a extract          -> job ${j1a}"
j1b=$(sbatch --parsable --job-name=kbv-1b-plsc     --dependency=afterok:${j1a} ${HPC_DIR}/1b-plsc.sbatch) || exit 1
echo "1b PLSC (rni, rnd)  -> job ${j1b}"
j1d=$(sbatch --parsable --job-name=kbv-1d-circular --dependency=afterok:${j1b} ${HPC_DIR}/1d-circular.sbatch) || exit 1
echo "1d circular plots   -> job ${j1d}"
echo "Outputs: /home/data/nbc/misc-projects/struc-func-plsc/derivatives/${PLSC_VARIANT}/"
