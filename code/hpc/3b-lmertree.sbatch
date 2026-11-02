#!/bin/bash
#SBATCH --job-name=sfp-3b-tree
#SBATCH --array=0-1
#SBATCH --time=12:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --account=iacc_nbc
#SBATCH --qos=pq_nbc
#SBATCH --partition=IB_44C_512G
#SBATCH --output=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%A_%a.out
#SBATCH --error=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%A_%a.err

# Step 3b: linear mixed-model trees (glmertree), one PLSC per array task
# (0 = RNI, 1 = RND). Does the latent score ~ measure slope differ across
# subgroups of pubertal stage / sex / age? Needs the data built by step 2 (2a).
# Needs: R packages glmertree, partykit in the container.
BLOCKS=(rni rnd)
export PLSC_BLOCK=${BLOCKS[${SLURM_ARRAY_TASK_ID:-0}]}
source /home/data/nbc/misc-projects/struc-func-plsc/code/hpc/hpc-env.sh
echo "PLSC block: rs-FC x ${PLSC_BLOCK}"

run_r Rscript 3b-ml-lmertree.R
status=$?
echo "Finished: $(date)  (exit ${status})"
exit ${status}
