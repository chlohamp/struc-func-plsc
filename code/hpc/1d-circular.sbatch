#!/bin/bash
#SBATCH --job-name=sfp-1d-circular
#SBATCH --array=0-1
#SBATCH --time=00:30:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --account=iacc_nbc
#SBATCH --qos=pq_nbc
#SBATCH --partition=IB_44C_512G
#SBATCH --output=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%A_%a.out
#SBATCH --error=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%A_%a.err

# Step 1d: circular plots of the bootstrap ratios (task 0 = RNI, 1 = RND).
# Only reads what 1b saved, so it takes seconds; re-run it on its own after
# changing the look:   sbatch hpc/1d-circular.sbatch
# Needs the R packages circlize and ggplot2 in the container.
BLOCKS=(rni rnd)
export PLSC_BLOCK=${BLOCKS[${SLURM_ARRAY_TASK_ID:-0}]}
source /home/data/nbc/misc-projects/struc-func-plsc/code/hpc/hpc-env.sh
echo "PLSC block: rs-FC x ${PLSC_BLOCK}"

run_r Rscript 1d-plsc-circular-plots.R
status=$?
echo "Finished: $(date)  (exit ${status})"
exit ${status}
