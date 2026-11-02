#!/bin/bash
#SBATCH --job-name=sfp-2-lme
#SBATCH --array=0-1
#SBATCH --time=24:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --account=iacc_nbc
#SBATCH --qos=pq_nbc
#SBATCH --partition=IB_44C_512G
#SBATCH --output=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%A_%a.out
#SBATCH --error=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%A_%a.err

# Step 2: for one PLSC per array task (0 = RNI, 1 = RND), build per-dimension
# data, then
#   2b-plsc-reg-boot  LMEs: latent scores ~ each Year 4 measure      (confirmatory)
#   2b-plsc-reg-corr  LMEs: each significant feature ~ each measure  (exploratory)
#   2c-plsc-puberty   LMEs: scores ~ puberty (x sex); scores ~ measure x pubertal stage
BLOCKS=(rni rnd)
export PLSC_BLOCK=${BLOCKS[${SLURM_ARRAY_TASK_ID:-0}]}
source /home/data/nbc/misc-projects/struc-func-plsc/code/hpc/hpc-env.sh
echo "PLSC block: rs-FC x ${PLSC_BLOCK}"

set -e
run_r Rscript 2a-build-reg-data.R
run_r Rscript 2b-plsc-reg-boot.R
run_r Rscript 2b-plsc-reg-corr.R
run_r Rscript 2c-plsc-puberty.R
echo "Finished: $(date)"
