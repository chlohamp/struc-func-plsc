#!/bin/bash
# =============================================================================
# hpc-env.sh - shared settings sourced by every sbatch script in code/
# Paths for the PLSC_StrucFunc analysis folder. Run 0-setup-env.sh once first.
# =============================================================================

PROJECT_DIR=/home/data/nbc/Laird_ABCD/data-analyses/PLSC_StrucFunc
CODE_DIR=${PROJECT_DIR}/code
LOG_DIR=${PROJECT_DIR}/code/log
# ABCD 7.0 tables are read from (set in config.R, not here):
#   /home/data/nbc/Laird_ABCD/7_0_data/tabulated/release_abcd

# Which analysis (see config.R): katie-baseline-vars | katie-Y2-vars | katie-y4-vars
export PLSC_VARIANT=${PLSC_VARIANT:-katie-y4-vars}
OUT_DIR=${PROJECT_DIR}/derivatives/${PLSC_VARIANT}

# R environment, built once by 0-setup-env.sh:
#   envs/plsc-r.sif  rocker/tidyverse image (R + tidyverse + rmarkdown + pandoc)
#   envs/Rlib/       extra packages (ExPosition, TExPosition, PTCA4CATA, ...)
ENV_DIR=${PROJECT_DIR}/envs
SIF=${ENV_DIR}/plsc-r.sif
R_LIB_DIR=${ENV_DIR}/Rlib

# Module that provides singularity/apptainer ("module avail apptainer" to check)
SINGULARITY_MODULE=${SINGULARITY_MODULE:-apptainer-container/1.4.1}

# Bind the whole NBC data tree so the container sees both the ABCD release
# (/home/data/nbc/Laird_ABCD/...) and the project folder.
BIND="-B /home/data/nbc:/home/data/nbc"

# -----------------------------------------------------------------------------
module load ${SINGULARITY_MODULE} 2>/dev/null || true
if command -v singularity >/dev/null 2>&1; then
  CONTAINER_BIN=singularity
elif command -v apptainer >/dev/null 2>&1; then
  CONTAINER_BIN=apptainer
else
  echo "ERROR: neither singularity nor apptainer found (check SINGULARITY_MODULE in hpc-env.sh)" >&2
  return 1 2>/dev/null || exit 1
fi
if [ ! -f "${SIF}" ]; then
  echo "ERROR: container image not found: ${SIF}  (run: sbatch 0-setup-env.sh)" >&2
  return 1 2>/dev/null || exit 1
fi

# --cleanenv keeps your login environment (and personal R library) out of the
# container; these variables are passed in explicitly instead. config.R reads them.
for P in SINGULARITYENV APPTAINERENV; do
  export ${P}_PLSC_ENV=hpc
  export ${P}_PLSC_PROJECT_DIR=${PROJECT_DIR}
  export ${P}_PLSC_CODE_DIR=${CODE_DIR}
  export ${P}_PLSC_VARIANT=${PLSC_VARIANT}
  export ${P}_R_LIBS=${R_LIB_DIR}
  export ${P}_OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
done
# Optional overrides, passed through only if you set them before sbatch:
#   PLSC_NITER=1000 sbatch 1b-plsc.sbatch      (quick trial run on real data)
#   PLSC_DIMS=1,3   sbatch 2-lme.sbatch        (choose dimensions by hand)
#   PLSC_BLOCK is set per array task by the sbatch scripts (rni / rnd)
#   PLSC_DATA_FORMAT=tsv                           (force TSV instead of parquet)
for V in PLSC_BLOCK PLSC_NITER PLSC_DIMS PLSC_DATA_FORMAT PLSC_SEED PLSC_SIG_ALPHA; do
  if [ -n "${!V}" ]; then
    export SINGULARITYENV_${V}="${!V}" APPTAINERENV_${V}="${!V}"
  fi
done

run_r() {
  ${CONTAINER_BIN} exec --cleanenv ${BIND} "${SIF}" "$@"
}

mkdir -p "${LOG_DIR}" "${OUT_DIR}"
cd "${CODE_DIR}" || { return 1 2>/dev/null || exit 1; }

echo "--------------------------------------------------------------"
echo "Job:       ${SLURM_JOB_NAME:-interactive} (${SLURM_JOB_ID:-none}) on $(hostname)"
echo "Started:   $(date)"
echo "Container: ${SIF}"
echo "Code dir:  ${CODE_DIR}"
echo "Variant:   ${PLSC_VARIANT}  ->  ${OUT_DIR}"
echo "--------------------------------------------------------------"
