#!/bin/bash
#SBATCH --job-name=sfp-3a-rf
#SBATCH --array=0-15
#SBATCH --time=24:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --account=iacc_nbc
#SBATCH --qos=pq_nbc
#SBATCH --partition=IB_44C_512G
#SBATCH --output=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%A_%a.out
#SBATCH --error=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%A_%a.err

# Step 3a: random forest, one Year 4 behaviour measure per array task
# (task i = i-th measure in ml_outcomes in config.R; tasks beyond the number of
# available measures exit immediately). Features = latent scores of the
# significant dimensions of BOTH PLSCs + puberty + covariates. Site-grouped CV,
# permutation nulls (ml_n_perm), interaction H, partial dependence, transfer.
# Needs: R packages ranger, glmnet, ggplot2 in the container.
# Uses 8 threads per task (ranger). Quick trial: PLSC_ML_NPERM=20 sbatch hpc/3a-rf.sbatch
export PLSC_ML_INDEX=${SLURM_ARRAY_TASK_ID:-0}
source /home/data/nbc/misc-projects/struc-func-plsc/code/hpc/hpc-env.sh
for P in SINGULARITYENV APPTAINERENV; do
  export ${P}_PLSC_ML_INDEX=${PLSC_ML_INDEX}
  export ${P}_SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK:-1}
  [ -n "${PLSC_ML_NPERM}" ] && export ${P}_PLSC_ML_NPERM=${PLSC_ML_NPERM}
done
echo "ML measure index: ${PLSC_ML_INDEX}"

run_r Rscript 3a-ml-rf.R
status=$?
echo "Finished: $(date)  (exit ${status})"
exit ${status}
