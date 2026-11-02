#!/bin/bash
#SBATCH --job-name=sfp-1b-plsc
#SBATCH --array=0-1
#SBATCH --time=24:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G
#SBATCH --account=iacc_nbc
#SBATCH --qos=pq_nbc
#SBATCH --partition=IB_44C_512G
#SBATCH --output=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%A_%a.out
#SBATCH --error=/home/data/nbc/misc-projects/struc-func-plsc/log/%x_%A_%a.err

# Step 1b: two separate PLSCs, run in parallel as a 2-task array
#   task 0 -> rs-FC x RNI (cellular density)
#   task 1 -> rs-FC x RND (neurite density)
# Each: residualize, PLSC, 10,000 permutations + 10,000 bootstraps.
# Run just one with:  sbatch --array=1 hpc/1b-plsc.sbatch
#
# An .Rmd can't be run with "Rscript file.Rmd". It has to be *rendered*, which
# runs every chunk top to bottom and writes an HTML report. Rendering needs
# pandoc; if the container doesn't have it, we extract the R code with
# knitr::purl() and run that instead (same results, just no HTML report).
BLOCKS=(rni rnd)
export PLSC_BLOCK=${BLOCKS[${SLURM_ARRAY_TASK_ID:-0}]}
source /home/data/nbc/misc-projects/struc-func-plsc/code/hpc/hpc-env.sh
echo "PLSC block: rs-FC x ${PLSC_BLOCK}"

run_r Rscript -e "
  block   <- '${PLSC_BLOCK}'
  out_dir <- file.path('${OUT_DIR}', paste0('plsc-', block))
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  if (rmarkdown::pandoc_available()) {
    rmarkdown::render('1b-plsc-clean.Rmd',
                      params            = list(block = block),
                      output_dir        = out_dir,
                      output_file       = paste0('1b-plsc-', block, '_', format(Sys.time(), '%Y%m%d-%H%M'), '.html'),
                      intermediates_dir = tempdir(),
                      knit_root_dir     = getwd(),
                      envir             = new.env())
  } else {
    message('pandoc not found in container: running the R code without the HTML report')
    r_file <- file.path(tempdir(), '1b-plsc-clean.R')
    knitr::purl('1b-plsc-clean.Rmd', output = r_file, quiet = TRUE)
    source(r_file, echo = TRUE, max.deparse.length = Inf)
  }
"
status=$?
echo "Finished: $(date)  (exit ${status})"
exit ${status}
