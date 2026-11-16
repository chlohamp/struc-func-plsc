#!/bin/bash
#SBATCH --job-name=sfp-0-setup
#SBATCH --time=04:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --account=acc_nbc
#SBATCH --qos=highmem1
#SBATCH --partition=highmem1-sapphirerapids
#SBATCH --output=/home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc/code/log/%x_%j.out
#SBATCH --error=/home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc/code/log/%x_%j.err
# =============================================================================
# 0-setup-env.sh - build the R environment for the pipeline. Run ONCE
# (it needs internet to download the image and packages):
#
#   cd /home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc/code
#   mkdir -p log && sbatch 0-setup-env.sh
#   (if compute nodes have no internet, run it on the login node instead:
#    bash 0-setup-env.sh)
#
# Makes, inside the project folder (so it doesn't fill your home quota):
#   envs/plsc-r.sif   rocker/tidyverse image: R, tidyverse, rmarkdown, pandoc
#   envs/Rlib/        the extra R packages the scripts need
# Safe to re-run: skips the image if it exists, installs only missing packages,
# then checks that every package loads.
# =============================================================================
set -euo pipefail
PROJECT_DIR=/home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc
ENV_DIR=${PROJECT_DIR}/envs
SIF=${ENV_DIR}/plsc-r.sif
R_LIB_DIR=${ENV_DIR}/Rlib
IMAGE=docker://rocker/tidyverse:4.4.2
SINGULARITY_MODULE=${SINGULARITY_MODULE:-apptainer-container/1.4.1}

mkdir -p "${ENV_DIR}" "${R_LIB_DIR}" "${PROJECT_DIR}/code/log" "${PROJECT_DIR}/derivatives"

module load ${SINGULARITY_MODULE} 2>/dev/null || true
if command -v singularity >/dev/null 2>&1; then BIN=singularity
elif command -v apptainer >/dev/null 2>&1; then BIN=apptainer
else echo "ERROR: no singularity/apptainer. Try: module avail apptainer" >&2; exit 1; fi
echo "Using $(${BIN} --version)"

# Keep the image cache and build temp files out of $HOME
export SINGULARITY_CACHEDIR=${ENV_DIR}/cache APPTAINER_CACHEDIR=${ENV_DIR}/cache
export SINGULARITY_TMPDIR=${ENV_DIR}/tmp     APPTAINER_TMPDIR=${ENV_DIR}/tmp
mkdir -p "${SINGULARITY_CACHEDIR}" "${SINGULARITY_TMPDIR}"

if [ ! -f "${SIF}" ]; then
  echo "Pulling ${IMAGE} -> ${SIF} (a few minutes)"
  ${BIN} pull "${SIF}" "${IMAGE}"
else
  echo "Image already there: ${SIF}"
fi

echo "Installing R packages into ${R_LIB_DIR}"
${BIN} exec --cleanenv -B /home/data/nbc:/home/data/nbc \
  --env R_LIBS=${R_LIB_DIR},SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK:-2} "${SIF}" Rscript -e '
  lib <- Sys.getenv("R_LIBS"); options(Ncpus = as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "2")))
  cran <- c("ExPosition", "TExPosition", "corrplot", "kableExtra", "circlize",
            "lmerTest", "ranger", "glmnet", "glmertree", "partykit", "arrow",
            "plyr", "scales", "remotes")
  need <- cran[!vapply(cran, requireNamespace, logical(1), quietly = TRUE)]
  if (length(need)) install.packages(need, lib = lib)
  gh <- c(PTCA4CATA = "HerveAbdi/PTCA4CATA", data4PCCAR = "HerveAbdi/data4PCCAR")
  for (p in names(gh)) if (!requireNamespace(p, quietly = TRUE))
    remotes::install_github(gh[[p]], lib = lib, upgrade = "never", dependencies = TRUE)

  all <- c(cran, names(gh), "tidyverse", "dplyr", "readr", "ggplot2", "tidyselect",
           "rmarkdown", "knitr")
  ok  <- vapply(all, function(p) suppressWarnings(requireNamespace(p, quietly = TRUE)), logical(1))
  cat("\nR", R.version.string, "\nlibrary paths:", .libPaths(), sep = "\n  ")
  cat("\npandoc available:", rmarkdown::pandoc_available(), "\n")
  if (any(!ok)) { cat("MISSING:", all[!ok], "\n"); quit(status = 1) }
  cat("All", length(all), "packages load. Environment ready.\n")
'
