#!/bin/bash
#SBATCH --job-name=sfp-3c-summary
#SBATCH --time=00:30:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --account=iacc_nbc
#SBATCH --qos=pq_nbc
#SBATCH --partition=IB_44C_512G
#SBATCH --output=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%j.out
#SBATCH --error=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%j.err

# Step 3c: combine the per-measure random forest results into derivatives/ml/
source /home/data/nbc/misc-projects/struc-func-plsc/code/hpc/hpc-env.sh
run_r Rscript 3c-ml-summary.R
status=$?
echo "Finished: $(date)  (exit ${status})"
exit ${status}
