# struc-func-plsc

Year 4 ABCD (7.0) structure-function coupling with two separate PLSCs. Both use
the same functional block, following Bottenhorn et al. (preprint, `papers/`):

| PLSC | Function block | Structure block |
|---|---|---|
| `rni` | rs-FC, 78 Gordon network connections (66 between + 12 within; "none" network excluded) | Cellular density: RNI, 34 lh + 34 rh Desikan cortical GM ROIs |
| `rnd` | same 78 | Neurite density: RND, 34 lh + 34 rh Desikan cortical GM ROIs |

Next, linear mixed-effects models (LMEs) relate each significant dimension to Year 4
**reward** (BIS/BAS, UPPS-P), **emotion regulation** (ERQ, DERS) and
**executive function** (NIH Toolbox Flanker and other Toolbox tasks). **Puberty**
(caregiver PDS: stage at Year 4, tempo since baseline, timing) is tested as a
predictor of the coupling patterns and as a moderator of the brain-behaviour links.
Finally, a **machine-learning** step tests whether the coupling patterns predict
behaviour in held-out sites and whether puberty modifies that prediction.

> LMEs tested the hypothesized associations; random forests evaluated whether
> microstructure-function coupling predicts behaviour in held-out youth and
> whether pubertal stage modifies these relationships nonlinearly.

The full analysis plan, with hypotheses and references, is in the Google Doc
"ABCD Year 4 Structure-Function PLSC: Analysis Plan".

Imaging and behaviour come from Year 4 (`ses-04A`). Each covariate is taken
from the wave set in `config.R`. That is either static, Year 4, or the most recent
value available up to Year 4. `covariate-sessions.csv` records which wave each
value came from. Both PLSCs use the same participants.

## Folders

```
dset/          inputs: the fake ABCD tables for local testing (.tsv + .parquet). Read only.
               On the HPC the real tables are read from
               /home/data/nbc/Laird_ABCD/7_0_data/tabulated/release_abcd and are never copied or changed.
code/          scripts (config.R holds every path and setting)
derivatives/   ALL outputs: cleaned/merged tables, PLSC results, figures, LME results
  plsc-rni/    rs-FC x RNI PLSC (report, loadings, scores, figures/, regression/)
  plsc-rnd/    rs-FC x RND PLSC
  ml/          random forest results, one folder per behaviour measure + combined summary
papers/
```

## Pipeline

| Step | Script | What it does | Outputs |
|---|---|---|---|
| 0 | `0-inspect-release.R` | Lists every table/column in the release. Checks each name in `config.R`, counts non-missing N at the wave used, and checks the 78/68/68 feature counts | `release_column_index.csv` |
| 0 | `0-pull-hpc-data.sh` | Copies the real ABCD 7.0 tables this project uses from the HPC to `dset/` on a laptop (`bash code/0-pull-hpc-data.sh USER@HPC_HOST`) | `dset/` |
| 0 | `0-make-fake-data.py` | Builds the fake release used for local testing | `dset/` |
| 1a | `1a-extract-abcd.R` | Extracts data: QC, missing codes, covariates by wave, complete cases | `clean-rsfc/rni/rnd.csv`, `covariate.csv`, `covariate-sessions.csv`, `lme-measures.csv`, `extraction-log.csv` |
| 1b | `1b-plsc-clean.Rmd` | Runs one PLSC per run (`block = rni` or `rnd`): residualizes, runs the PLSC, permutation test + bootstrap, makes figures (including the network matrix) | `plsc-<block>/`: HTML report, loadings + BRs, latent scores, `significant_dimensions.csv`, `figures/` |
| 2a | `2a-build-reg-data.R` | Builds per-dimension data for the LMEs | `plsc-<block>/regression/dim<k>/` |
| 2b | `2b-plsc-reg-boot.R` | **Primary:** latent scores ~ each measure | `plsc-<block>/regression/plsc-reg-boot-dim<k>-results.csv` |
| 2b | `2b-plsc-reg-corr.R` | **Exploratory:** each feature with abs(BR) > 2.5 ~ each measure | `plsc-<block>/regression/plsc-reg-corr-results-all.csv` |
| 2c | `2c-plsc-puberty.R` | **Puberty:** (A) score ~ puberty (stage, tempo, timing) × sex; (B) score ~ measure × pubertal stage, in everyone and by sex | `plsc-<block>/regression/plsc-puberty-main/-moderation-dim<k>-results.csv` |
| 3a | `3a-ml-rf.R` | **Random forest:** each measure ~ latent scores of both PLSCs (+ puberty) with site-grouped CV. Nested models M0/M1/M2 plus an elastic-net benchmark, permutation nulls, brain × puberty interaction strength (H²), partial-dependence plots by pubertal stage, cross-stage transfer | `ml/<measure>/` |
| 3b | `3b-ml-lmertree.R` | **Mixed-model trees:** does the score ~ measure slope differ across pubertal stage / sex / age subgroups? Keeps site/family random effects; FDR across trees | `plsc-<block>/regression/lmertree-dim<k>-*.csv`, `trees/*.png` |
| 3c | `3c-ml-summary.R` | Combines 3a across measures (FDR across measures) | `ml/ml-summary.csv`, `ml/ml-r2-by-model.png` |

`config.R` holds every path, table name, wave, variable list and setting.
`lme-helpers.R` has the model code that the 2b and 2c scripts use. Measures that are
missing at Year 4, or have N < 100, are skipped with a message. For example, some
NIH Toolbox tasks aren't given at every wave.

## 1. Test locally with the fake data

The fake data in `dset/` has 600 fake participants at
baseline, Year 2 and Year 4. Every table is saved as both .tsv and .parquet. Card sort and list sort are
left out at Year 4, and some covariates exist only at earlier waves, so the
skip and fallback code gets tested. Puberty (PDS) is included, with two built-in
effects so the puberty analyses have something to find: earlier maturers express
the RNI (not RND) coupling pattern more strongly, and the attention-profile →
Flanker link strengthens with pubertal stage. Run `python3 code/0-make-fake-data.py` to rebuild it.

```bash
cd ~/Desktop/struc-func-plsc/code
Rscript 1a-extract-abcd.R
Rscript -e "rmarkdown::render('1b-plsc-clean.Rmd', params = list(block = 'rni'), output_dir = '../derivatives/plsc-rni')"
Rscript -e "rmarkdown::render('1b-plsc-clean.Rmd', params = list(block = 'rnd'), output_dir = '../derivatives/plsc-rnd')"
Rscript 2a-build-reg-data.R          # both PLSCs (or PLSC_BLOCK=rni Rscript ...)
Rscript 2b-plsc-reg-boot.R
Rscript 2b-plsc-reg-corr.R           # several minutes
Rscript 2c-plsc-puberty.R
Rscript 3a-ml-rf.R                   # all measures, ~1 min each with the local settings
Rscript 3b-ml-lmertree.R
Rscript 3c-ml-summary.R
```

In RStudio, set the working directory to `code/` and use **Knit with Parameters...** to choose `rni` or `rnd`.
If the project isn't at `~/Desktop/struc-func-plsc`, put `PLSC_PROJECT_DIR=/path/...` in front of each command.

Packages: `tidyverse`, `ExPosition`, `TExPosition`, `PTCA4CATA`, `data4PCCAR`,
`corrplot`, `kableExtra`, `rmarkdown`, `lmerTest`, and for step 3 `ranger`,
`glmnet`, `glmertree` (+ `partykit`). `arrow` is optional. Without it, the scripts read the .tsv files.

### Python environment (for `plot-gord-desik.ipynb`)

The atlas plotting notebook uses a Python 3.9 virtual environment in `.venv/` at the
project root. The folder is git-ignored, so each computer has to build its own. Run this once in the terminal:

```bash
cd ~/Desktop/struc-func-plsc

# 1. check that Python 3.9 is installed (it should print Python 3.9.x)
python3.9 --version

# 2. create the environment
python3.9 -m venv .venv

# 3. activate it (your prompt will start with "(.venv)")
source .venv/bin/activate

# 4. install the packages (gradec installs from GitHub, so git must be installed)
python -m pip install --upgrade pip
python -m pip install -r code/requirements.txt

# 5. register it as a Jupyter kernel
python -m ipykernel install --user --name struc-func-plsc --display-name "Python (struc-func-plsc)"
```

To use the environment later, run `cd ~/Desktop/struc-func-plsc && source .venv/bin/activate`,
and run `deactivate` when you're done. In VS Code, open `code/plot-gord-desik.ipynb`, click **Select Kernel** (top right),
and pick `.venv` or **Python (struc-func-plsc)**.

Notes:
- If `python3.9` isn't found, install Python 3.9 (for example `brew install python@3.9`
  or the installer from python.org) and try again. The pinned versions in
  `requirements.txt` (for example `numpy==2.0.2`) need Python 3.9.
- To start over, delete the environment with `rm -rf .venv` and repeat steps 2 to 5.
- On first run the notebook downloads the fs_LR surfaces (`neuromaps`) and the DK atlas
  (`netneurotools`, to `~/nnt-data`), so it needs internet access.
- PNGs are saved to `derivatives/figures/`.

## 2. Run on the HPC

```bash
cd /home/data/nbc/misc-projects/struc-func-plsc/code

# (one time) edit hpc/hpc-env.sh: SIF= your container in /home/data/cis/singularity-images
#            and check the #SBATCH account / qos / partition lines against your usual template

# (one time) check the real names, Year 4 Ns and 78/68/68 counts, then fix "# VERIFY" lines in config.R
source hpc/hpc-env.sh && run_r Rscript 0-inspect-release.R

PLSC_NITER=500 bash hpc/submit-all.sh    # quick trial on the real data
bash hpc/submit-all.sh                   # full run: 1a -> 1b -> 2 -> 3 (see the dependency graph in submit-all.sh)
bash hpc/submit-all.sh 1b                # rerun from the PLSCs onward
bash hpc/submit-all.sh 2                 # rerun the LMEs and ML
bash hpc/submit-all.sh 3                 # rerun only the ML step
PLSC_ML_NPERM=20 sbatch hpc/3a-rf.sbatch # quick random-forest trial (fewer permutations)
sbatch --array=1 hpc/1b-plsc.sbatch      # rerun only the RND PLSC (0 = rni, 1 = rnd)
PLSC_DIMS=1,2 bash hpc/submit-all.sh 2   # LMEs on dimensions you choose

squeue -u $USER
ls ../log/        # <job>_<arrayjob>_<task>.out / .err
```

### How the .Rmd runs on the HPC

You can't run an `.Rmd` file with `Rscript file.Rmd`. It has to be rendered.
`hpc/1b-plsc.sbatch` is a 2-task array job. Each task calls `rmarkdown::render()`
with `params = list(block = ...)` inside the container and saves a time-stamped HTML
report in `derivatives/plsc-<block>/`. Rendering needs pandoc. If the container doesn't have it,
the job pulls the R code out with `knitr::purl()` and runs that instead. You get the
same results files but no HTML report. All figures are saved as PNGs to `figures/`.
