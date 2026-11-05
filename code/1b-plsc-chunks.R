# =============================================================================
# 1b-plsc-chunks.R - run PLSC permutations / bootstraps in independent chunks
# -----------------------------------------------------------------------------
# For machines where one long R session is not practical (e.g. a laptop
# sandbox that kills long jobs). Results are combined exactly by
# 1b-plsc-clean.Rmd, which uses the chunks in plsc-<block>/chunks/ whenever
# they exist (delete that folder to go back to a single in-Rmd run).
#
#   1. Render 1b-plsc-clean.Rmd once (any PLSC_NITER) -> writes plsc_input.rds
#   2. Rscript 1b-plsc-chunks.R <block> perm <nIter> <seed>   (repeat, new seed each time)
#      Rscript 1b-plsc-chunks.R <block> boot <nIter> <seed>
#   3. Render 1b-plsc-clean.Rmd again with PLSC_NITER = total iterations
#
# perm: concatenating permEigenvalues from chunks and recomputing p is
#       identical to one perm4PLSC() call with the summed nIter.
# boot: concatenating bootstrap bricks and recomputing mean / sd is identical
#       to one Boot4PLSC() call with the summed nIter.
# =============================================================================
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4) stop("usage: Rscript 1b-plsc-chunks.R <rni|rnd> <perm|boot> <nIter> <seed>")
block <- args[1]; type <- args[2]; n <- as.integer(args[3]); seed <- as.integer(args[4])
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "config.R"))
suppressPackageStartupMessages({ library(TExPosition); library(data4PCCAR) })

dirs <- plsc_dirs(block)
inp  <- readRDS(file.path(dirs$plsc, "plsc_input.rds"))
cdir <- file.path(dirs$plsc, "chunks"); dir.create(cdir, showWarnings = FALSE)
set.seed(seed)
t0 <- Sys.time()
if (type == "perm") {
  r <- perm4PLSC(inp$data1, inp$data2, permType = "byColumns", nIter = n)
  out <- list(type = "perm", n = n, seed = seed,
              fixedEigenvalues = r$fixedEigenvalues, fixedInertia = r$fixedInertia,
              permEigenvalues = r$permEigenvalues)
} else if (type == "boot") {
  r <- Boot4PLSC(inp$data1, inp$data2, nIter = n, Fi = inp$Fi, Fj = inp$Fj,
                 nf2keep = inp$nf_boot, critical.value = br_threshold, alphaLevel = 0.05)
  out <- list(type = "boot", n = n, seed = seed, nf_boot = inp$nf_boot,
              brick.i = r$bootstrapBrick.i, brick.j = r$bootstrapBrick.j)
} else stop("type must be perm or boot")
f <- file.path(cdir, sprintf("%s_n%d_seed%d.rds", type, n, seed))
saveRDS(out, f)
message(sprintf("%s %s: %d iterations (seed %d) in %.0f s -> %s", block, type, n, seed,
                as.numeric(difftime(Sys.time(), t0, units = "secs")), basename(f)))
