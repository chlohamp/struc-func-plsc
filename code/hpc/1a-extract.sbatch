#!/bin/bash
#SBATCH --job-name=sfp-1a-extract
#SBATCH --time=02:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --account=acc_nbc
#SBATCH --qos=highmem1
#SBATCH --partition=highmem1-sapphirerapids
#SBATCH --output=/home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc/code/log/%x_%j.out
#SBATCH --error=/home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc/code/log/%x_%j.err

# Step 1a: read ABCD 7.0 tables -> clean-rsfc.csv, clean-smri.csv, covariate.csv, lme-measures.csv
source /home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc/code/hpc-env.sh

run_r Rscript 1a-extract-abcd.R
status=$?
echo "Finished: $(date)  (exit ${status})"
exit ${status}
