#!/bin/bash
#SBATCH --job-name=sfp-1a-extract
#SBATCH --time=02:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --account=iacc_nbc
#SBATCH --qos=pq_nbc
#SBATCH --partition=IB_44C_512G
#SBATCH --output=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%j.out
#SBATCH --error=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%j.err

# Step 1a: read ABCD 7.0 tables -> clean-rsfc.csv, clean-smri.csv, covariate.csv, lme-measures.csv
source /home/data/nbc/misc-projects/struc-func-plsc/code/hpc/hpc-env.sh

run_r Rscript 1a-extract-abcd.R
status=$?
echo "Finished: $(date)  (exit ${status})"
exit ${status}
