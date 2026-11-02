#!/bin/bash
# =============================================================================
# hpc-env.sh - shared settings sourced by every sbatch script in code/hpc/
# Edit the two lines marked CHANGE ME, everything else should just work.
# =============================================================================

PROJECT_DIR=/home/data/nbc/misc-projects/struc-func-plsc
CODE_DIR=${PROJECT_DIR}/code
OUT_DIR=${PROJECT_DIR}/derivatives
LOG_DIR=${PROJECT_DIR}/log

# CHANGE ME: the shared R/ExPosition image in the group folder
SIF=/home/data/cis/singularity-images/CHANGE_ME.sif

# CHANGE ME (if needed): the singularity module name on the cluster
SINGULARITY_MODULE=singularity-3.8.2

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
  echo "ERROR: container image not found: ${SIF}  (edit SIF in hpc-env.sh)" >&2
  return 1 2>/dev/null || exit 1
fi

# --cleanenv keeps your login environment (and personal R library) out of the
# container; these variables are passed in explicitly instead. config.R reads them.
for P in SINGULARITYENV APPTAINERENV; do
  export ${P}_PLSC_ENV=hpc
  export ${P}_PLSC_PROJECT_DIR=${PROJECT_DIR}
  export ${P}_PLSC_CODE_DIR=${CODE_DIR}
  export ${P}_OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
done
# Optional overrides, passed through only if you set them before sbatch:
#   PLSC_NITER=1000 sbatch hpc/1b-plsc.sbatch      (quick trial run on real data)
#   PLSC_DIMS=1,3   sbatch hpc/2-lme.sbatch        (choose dimensions by hand)
#   PLSC_BLOCK is set per array task by the sbatch scripts (rni / rnd)
#   PLSC_DATA_FORMAT=tsv                           (force TSV instead of parquet)
for V in PLSC_BLOCK PLSC_NITER PLSC_DIMS PLSC_DATA_FORMAT PLSC_SEED; do
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
echo "--------------------------------------------------------------"
