# =============================================================================
# 1d-plsc-circular-plots.R - circular plots of PLSC bootstrap ratios
# -----------------------------------------------------------------------------
# Reads what 1b already saved (no PLSC is re-run), so it takes seconds and can
# be re-run as often as you like while tweaking the look.
#
# For each PLSC (rni, rnd; or just PLSC_BLOCK=rni) and each significant
# dimension (significant_dimensions.csv, or PLSC_DIMS=1,3) it writes to
# plsc-<block>/figures/:
#
#   circular_rsfc_<block>_Dim<k>.png/.pdf/.svg   rs-FC side: chord diagram
#       12 Gordon networks ordered along the S-A axis. Each chord is one
#       between-network connection; only |BR| > br_threshold is drawn,
#       coloured by its BR. An optional ring inside the network names holds the
#       within-network BR (show_within_ring). Chord width also grows with |BR| (chord_width_by_br); the layout
#       is identical across dimensions and PLSCs.
#
#   circular_<block>_Dim<k>.png/.pdf/.svg        RNI / RND side: circular barplot
#       68 Desikan regions, right hemisphere on the right and left on the left,
#       lobes running front (top) to back (bottom). Bar = BR; dashed rings at
#       +/- br_threshold; bars past the threshold are coloured.
#
# Every plot (both PLSCs, every dimension) shares ONE colour scale (br_lim), so
# the plots carry no colour bar of their own. The bar is saved once as
#   <variant>/circular_colorbar_BR.png/.pdf/.svg   (same style as the region plots)
# Each dimension's sign is arbitrary in the SVD, so by default it is flipped to match
# Bottenhorn et al. (align_signs, below). Read the two plots of a dimension together:
# red on one side goes with red on the other, blue with blue.
#
# Needs: circlize, ggplot2 (both on CRAN)
#   PLSC_ENV=local Rscript 1d-plsc-circular-plots.R
# =============================================================================
# Find config.R next to this script, whatever the working directory is
# (works with Rscript, source() from the R console, or RStudio)
local({
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  of <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  cands <- c(Sys.getenv("PLSC_CODE_DIR", ""),
             if (length(f)) dirname(f[1]),
             if (!is.null(of)) dirname(of),
             ".", "code", "~/Desktop/struc-func-plsc/code")
  cands <- file.path(cands[nzchar(cands)], "config.R")
  hit <- cands[file.exists(cands)]
  if (!length(hit)) stop("Can't find config.R. Looked in:\n  ", paste(cands, collapse = "\n  "),
                         "\nSet PLSC_CODE_DIR to the folder that holds config.R.")
  assign("code_dir", dirname(normalizePath(hit[1])), envir = globalenv())
})
source(file.path(code_dir, "config.R"))

for (p in c("circlize", "ggplot2")) {
  if (!requireNamespace(p, quietly = TRUE)) stop("Package '", p, "' is not installed (install.packages('", p, "'))")
}
suppressPackageStartupMessages({ library(circlize); library(ggplot2) })

# ---- Look and feel -----------------------------------------------------------
# Gordon networks (ABCD abbreviations) along the sensorimotor-association axis,
# same order as the network-matrix figure in 1b. Colours match plot-gord-desik / 1c-plsc-figures.
gordon <- data.frame(
  abbr  = c("vis", "smh", "smm", "aud", "cip", "ret", "doa", "cio", "vea", "sal", "frp", "def"),  # ABCD 7.0 codes
  label = c("VN", "SHN", "SMN", "AN", "CPN", "RTN",
            "DAN", "CON", "VAN", "SN", "FPN", "DN"),
  col   = c("#7419AE", "#FFBA4F", "#C187C0", "#75BDE8", "#F51D0F", "#85F0D6",
            "#FB8691", "#68A23F", "#F07107", "#FFEF7A", "#1B5CC1", "#EE1074"),
  group = c(rep("Sensorimotor", 4), rep("Attention / memory", 5), rep("Triple network", 3)),
  stringsAsFactors = FALSE
)

# Desikan-Killiany regions by lobe, roughly front to back within each lobe
dk_lobes <- list(
  Frontal   = c("frontalpole", "superiorfrontal", "rostralmiddlefrontal", "caudalmiddlefrontal",
                "parsorbitalis", "parstriangularis", "parsopercularis", "lateralorbitofrontal",
                "medialorbitofrontal", "precentral", "paracentral"),
  Insula    = c("insula"),
  Cingulate = c("rostralanteriorcingulate", "caudalanteriorcingulate", "posteriorcingulate", "isthmuscingulate"),
  Temporal  = c("temporalpole", "superiortemporal", "transversetemporal", "bankssts", "middletemporal",
                "inferiortemporal", "entorhinal", "parahippocampal", "fusiform"),
  Parietal  = c("postcentral", "supramarginal", "superiorparietal", "inferiorparietal", "precuneus"),
  Occipital = c("lingual", "pericalcarine", "cuneus", "lateraloccipital")
)
dk_short <- c(
  frontalpole = "frontal pole", superiorfrontal = "SFG", rostralmiddlefrontal = "rMFG",
  caudalmiddlefrontal = "cMFG", parsorbitalis = "pars orb", parstriangularis = "pars tri",
  parsopercularis = "pars operc", lateralorbitofrontal = "lat OFC", medialorbitofrontal = "med OFC",
  precentral = "precentral", paracentral = "paracentral", insula = "insula",
  rostralanteriorcingulate = "rACC", caudalanteriorcingulate = "cACC", posteriorcingulate = "PCC",
  isthmuscingulate = "isthmus CC", temporalpole = "temporal pole", superiortemporal = "STG",
  transversetemporal = "transv temp", bankssts = "banks STS", middletemporal = "MTG",
  inferiortemporal = "ITG", entorhinal = "entorhinal", parahippocampal = "parahipp",
  fusiform = "fusiform", postcentral = "postcentral", supramarginal = "SMG",
  superiorparietal = "SPL", inferiorparietal = "IPL", precuneus = "precuneus",
  lingual = "lingual", pericalcarine = "pericalc", cuneus = "cuneus", lateraloccipital = "LOC"
)
# light tints of the lobe hue families used for DK regions in plot-gord-desik / 1c
# (each is 30% of the way from the family's palest shade toward its mid shade)
lobe_cols <- c(Frontal = "#B5D1D7", Insula = "#F3E2B2", Cingulate = "#F6B1A9",
               Temporal = "#C5DEBD", Parietal = "#CEC3E1", Occipital = "#F4CCAA")

# Titles and subtitles above each figure (TRUE to show)
show_titles <- FALSE

# Inner ring of the chord diagram showing each within-network BR (TRUE to show)
show_within_ring <- FALSE

# Text size multiplier for the rs-FC chord diagrams (1 = original sizes)
rsfc_text_scale <- 1.8

# Chord look. The colours stay the same; these make strong vs weak easier to tell apart.
#   chord_alpha:       1 = solid (transparency was washing the dark shades toward the light ones)
#   chord_width_by_br: TRUE = stronger |BR| gets a wider chord as well as a darker colour
#   chord_min_width / chord_max_width: chord width at the threshold / at the colour limit
#                      (fraction of a slot; 0.84 = the old fixed width)
#   chord_outline:     thin white edge so crossing chords stay separate (NA = none)
chord_alpha       <- 1
chord_width_by_br <- TRUE
chord_min_width   <- 0.75
chord_max_width   <- 2.25
chord_outline     <- "grey"

# Region barplot: "clean" (labels hug the bars, BR scale in the top gap)
# or "classic" (the original look). bar_fill: "lobe" (DK lobe colours) or "br" (BR colour scale,
# so red/blue read the same as in the chord plot).
bar_style <- "clean"
bar_fill  <- "br"
# Flip each dimension's sign (rs-FC and structure together) to match Bottenhorn et al.,
# the same rule as make-ohbm-figures.py, make-ohbm-circular-parts.R and 1c-plsc-figures.ipynb:
#   LD1 = higher RNI/RND across cortex; LD2 = lower posterior RNI / higher posterior RND.
# Other dimensions: positive mean structural BR. FALSE = raw SVD signs (arbitrary).
align_signs <- TRUE
posterior_regions <- c("cuneus", "pericalcarine", "lateraloccipital", "lingual")
dim_sign <- function(block, k, regs, brQ) {
  if (!align_signs) return(1)
  if (k == 2) {
    post <- mean(brQ[regs$region %in% posterior_regions])
    return(if (block == "rni") (if (post < 0) 1 else -1) else (if (post > 0) 1 else -1))
  }
  if (mean(brQ) > 0) 1 else -1
}

# Shared colour limit for every plot and the one colour bar. NULL = the largest |BR|
# across every block and dimension plotted in this run, rounded up (set e.g. 11 to fix it).
br_lim <- NULL

lobe_bar_cols <- c(Frontal = "#4D8A95", Insula = "#EAC96F", Cingulate = "#EA7364",
                   Temporal = "#87BA76", Parietal = "#9A85BF", Occipital = "#EAA061")


# Graphics devices that don't need Cairo (often missing on macOS R, where png()
# and cairo_pdf() then fail with only a warning and write nothing)
open_png <- function(f, width, height, res) {
  if (requireNamespace("ragg", quietly = TRUE)) ragg::agg_png(f, width = width, height = height, res = res)
  else png(f, width = width, height = height, res = res)
}
pdf_device <- if (isTRUE(capabilities("cairo"))) cairo_pdf else grDevices::pdf
# SVG (text stays text, so it stays sharp when resized). Prefers svglite (install.packages("svglite"));
# falls back to grDevices::svg when Cairo is available; otherwise SVGs are skipped with a message.
svg_device <- if (requireNamespace("svglite", quietly = TRUE)) {
  function(filename, width, height, ...) svglite::svglite(filename, width = width, height = height)
} else if (isTRUE(capabilities("cairo"))) {
  function(filename, width, height, ...) grDevices::svg(filename, width = width, height = height)
} else NULL
if (is.null(svg_device)) message("No SVG device: install.packages('svglite') to also save .svg files")
devs <- c("png", "pdf", if (!is.null(svg_device)) "svg")

# Diverging scale: pale at the threshold, dark at the max; grey = not significant
neg_dark <- "#08306B"; neg_pale <- "#9ECAE1"; pos_pale <- "#FCBBA1"; pos_dark <- "#67000D"
ns_grey  <- "grey85"
br_col_fun <- function(lim) {
  circlize::colorRamp2(c(-lim, -br_threshold, br_threshold, lim), c(neg_dark, neg_pale, pos_pale, pos_dark))
}
br_cols <- function(br, lim) ifelse(abs(br) > br_threshold, br_col_fun(lim)(br), ns_grey)

# ---- Parsers -----------------------------------------------------------------
# rs-FC row names: <prefix><net>_<net>   e.g. mr_y_rsfmri__corr__gpnet__dla_vta
parse_rsfc <- function(rn) {
  lab <- sub("_mean$", "", sub(rsfc_block$prefix, "", rn, fixed = TRUE))
  pr  <- strsplit(lab, "__", fixed = TRUE)                       # 7.0: <a>__<b>_mean
  ok  <- vapply(pr, function(p) length(p) == 2 && all(p %in% gordon$abbr), logical(1))
  if (!all(ok)) stop("Could not parse Gordon network pairs from rs-FC names, e.g.: ",
                     paste(head(lab[!ok], 3), collapse = ", "),
                     "\nEdit parse_rsfc() in 1d-plsc-circular-plots.R to match the real column names.")
  data.frame(a = vapply(pr, `[`, "", 1), b = vapply(pr, `[`, "", 2), stringsAsFactors = FALSE)
}
# RSI row names: <prefix><region>__<hemi>  e.g. mr_y_rsi__rni__dsk__precuneus__lh
# (hemisphere found anywhere in the name, so other orders also work)
# ABCD 7.0 Desikan abbreviations -> FreeSurfer names (from the release .json dictionary)
dk_abbr <- c(bstmps = "bankssts", cac = "caudalanteriorcingulate", cmfrt = "caudalmiddlefrontal",
  cn = "cuneus", er = "entorhinal", ff = "fusiform", ic = "isthmuscingulate", ins = "insula",
  iprt = "inferiorparietal", itmp = "inferiortemporal", lg = "lingual", lobfrt = "lateralorbitofrontal",
  locc = "lateraloccipital", mobfrt = "medialorbitofrontal", mtmp = "middletemporal", pactr = "paracentral",
  pcc = "pericalcarine", pcg = "posteriorcingulate", pfrt = "frontalpole", ph = "parahippocampal",
  pob = "parsorbitalis", poctr = "postcentral", pop = "parsopercularis", prcn = "precuneus",
  prctr = "precentral", ptg = "parstriangularis", ptmp = "temporalpole", rac = "rostralanteriorcingulate",
  rmfrt = "rostralmiddlefrontal", sfrt = "superiorfrontal", sm = "supramarginal", sprt = "superiorparietal",
  stmp = "superiortemporal", ttmp = "transversetemporal")
parse_dk <- function(rn, prefix) {
  lab  <- tolower(sub("_mean$", "", sub(prefix, "", rn, fixed = TRUE)))
  hemi <- ifelse(grepl("(^|[_.])lh([_.]|$)", lab), "lh", ifelse(grepl("(^|[_.])rh([_.]|$)", lab), "rh", NA))
  reg  <- gsub("(^|[_.])(lh|rh)([_.]|$)", "", lab)
  reg  <- gsub("[_.]", "", reg)
  reg  <- ifelse(reg %in% names(dk_abbr), dk_abbr[reg], reg)
  ok   <- !is.na(hemi) & reg %in% unlist(dk_lobes)
  if (!all(ok)) stop("Could not parse Desikan region/hemisphere from names, e.g.: ",
                     paste(head(lab[!ok], 3), collapse = ", "),
                     "\nEdit parse_dk() in 1d-plsc-circular-plots.R to match the real column names.")
  data.frame(region = reg, hemi = hemi, stringsAsFactors = FALSE)
}

# ---- rs-FC chord diagram -----------------------------------------------------
plot_rsfc_chord <- function(br, pairs, lim, title, subtitle) {
  n    <- nrow(gordon)
  nets <- gordon$abbr
  idx  <- setNames(seq_len(n), nets)
  df   <- data.frame(pairs, br = br, stringsAsFactors = FALSE)
  within  <- df[df$a == df$b, ]
  between <- df[df$a != df$b, ]

  # Each network has one slot per partner network (11). Slots are ordered so a
  # chord to the counter-clockwise neighbour sits at the counter-clockwise end:
  # this keeps chords from twisting across each other.
  slot_of <- function(i, j) {                      # position of partner j inside sector i
    partners <- setdiff(seq_len(n), i)
    ord <- partners[order(-((partners - i) %% n))]
    match(j, ord) - 0.5
  }

  par(mar = c(0.5, 0.5, if (nzchar(title) || nzchar(subtitle)) 3.5 + 1.2 * (rsfc_text_scale - 1) else 0.5, 0.5), xpd = NA)
  circos.clear()
  circos.par(start.degree = 90 + 360 / n / 2, clock.wise = TRUE, gap.degree = 2.5,
             cell.padding = c(0, 0, 0, 0), track.margin = c(0.005, 0.005),
             canvas.xlim = c(-1.45, 1.45), canvas.ylim = c(-1.45, 1.45), points.overflow.warning = FALSE)
  circos.initialize(factor(nets, levels = nets), xlim = c(0, n - 1))

  # Track 1: network blocks + names
  circos.track(ylim = c(0, 1), track.height = 0.07, bg.border = NA, panel.fun = function(x, y) {
    i <- idx[CELL_META$sector.index]
    circos.rect(0, 0, n - 1, 1, col = gordon$col[i], border = "white")
    circos.text(CELL_META$xcenter, 2.1, gordon$label[i], facing = "bending.inside",
                niceFacing = TRUE, cex = 0.72 * rsfc_text_scale, col = "grey15")
  })
  # Track 2: within-network BR (optional, see show_within_ring)
  if (show_within_ring) circos.track(ylim = c(0, 1), track.height = 0.07, bg.border = NA, panel.fun = function(x, y) {
    a <- CELL_META$sector.index
    v <- within$br[within$a == a]
    if (length(v) == 0) return()
    circos.rect(0.4, 0.05, n - 1.4, 0.95, col = br_cols(v, lim), border = "grey60", lwd = 0.5)
    circos.text(CELL_META$xcenter, 0.5, sprintf("%.1f", v), cex = 0.55 * rsfc_text_scale,
                col = if (abs(v) > 0.75 * lim) "white" else "grey20", facing = "bending.inside", niceFacing = TRUE)
  })

  # Chords: significant between-network connections, weakest drawn first
  sig <- between[abs(between$br) > br_threshold, ]
  sig <- sig[order(abs(sig$br)), ]
  cf  <- br_col_fun(lim)
  for (k in seq_len(nrow(sig))) {
    i <- idx[sig$a[k]]; j <- idx[sig$b[k]]
    si <- slot_of(i, j); sj <- slot_of(j, i)
    hw <- if (chord_width_by_br) {
      frac <- min(1, max(0, (abs(sig$br[k]) - br_threshold) / (lim - br_threshold)))
      (chord_min_width + frac * (chord_max_width - chord_min_width)) / 2
    } else 0.42
    circos.link(sig$a[k], c(si - hw, si + hw), sig$b[k], c(sj - hw, sj + hw),
                col = adjustcolor(cf(sig$br[k]), alpha.f = chord_alpha),
                border = chord_outline, lwd = 0.6, h.ratio = 0.55)
  }
  if (nrow(sig) == 0) text(0, 0, "No between-network\nconnection passes\n|BR| > threshold", cex = 0.8 * rsfc_text_scale, col = "grey40")

  # Network-family arcs outside the names
  for (g in unique(gordon$group)) {
    s   <- gordon$abbr[gordon$group == g]
    deg <- c(get.cell.meta.data("cell.start.degree", sector.index = s[1], track.index = 1),
             get.cell.meta.data("cell.end.degree",   sector.index = s[length(s)], track.index = 1))
    draw.sector(deg[1] - 0.5, deg[2] + 0.5, rou1 = 1.235, rou2 = 1.245, clock.wise = TRUE,
                col = "grey55", border = NA)
    # label centred on the group: middle of the middle sector, or the edge between the two middle ones
    m <- (length(s) + 1) / 2
    sec <- s[ceiling(m)]; xx <- if (m %% 1 == 0) (n - 1) / 2 else 0
    circos.text(xx, 5.9, g, sector.index = sec, track.index = 1, facing = "bending.inside",
                niceFacing = TRUE, cex = 0.7 * rsfc_text_scale, col = "grey35", font = 3)
  }
  title(main = title, cex.main = 1.05 * rsfc_text_scale, line = 2.2 + 0.8 * (rsfc_text_scale - 1))
  mtext(subtitle, side = 3, line = 0.9, cex = 0.72 * rsfc_text_scale, col = "grey30")
  circos.clear()
}

# ---- RNI / RND circular barplot ----------------------------------------------
plot_struct_bars_classic <- function(br, regs, lim, title, subtitle) {
  df <- data.frame(regs, br = br, stringsAsFactors = FALSE)
  lobe_of <- setNames(rep(names(dk_lobes), lengths(dk_lobes)), unlist(dk_lobes))
  df$lobe <- lobe_of[df$region]

  # Order: right hemisphere clockwise from the top (front -> back), then the left
  # hemisphere continuing clockwise from the bottom back up (back -> front), so
  # homologous regions mirror each other across the vertical midline.
  gap_lobe <- 1; gap_hemi <- 3
  rows <- list(); pos <- gap_hemi / 2
  for (h in c("rh", "lh")) {
    lobes <- if (h == "rh") names(dk_lobes) else rev(names(dk_lobes))
    for (lb in lobes) {
      regs_lb <- if (h == "rh") dk_lobes[[lb]] else rev(dk_lobes[[lb]])
      sub <- df[df$hemi == h & df$lobe == lb, ]
      sub <- sub[match(regs_lb, sub$region), ]
      sub <- sub[!is.na(sub$region), ]
      sub$pos <- pos + seq_len(nrow(sub))
      pos <- pos + nrow(sub) + gap_lobe
      rows[[length(rows) + 1]] <- sub
    }
    pos <- pos - gap_lobe + gap_hemi
  }
  df <- do.call(rbind, rows)
  x_max <- pos - gap_hemi / 2 + 0.5       # full circle

  df$sig  <- abs(df$br) > br_threshold
  df$fill <- ifelse(df$sig, df$br, NA)
  df$label <- dk_short[df$region]

  # Radial layout (in BR units)
  hole    <- 0.55 * lim             # empty centre
  band_lo <- lim * 1.04; band_hi <- lim * 1.2
  lab_y   <- lim * 1.25
  y_min   <- -lim - hole; y_max <- lim * 1.75

  # Text angles: readable on both halves
  ang <- 90 - 360 * (df$pos - 0.5) / x_max
  df$hjust <- ifelse(ang < -90, 1, 0)
  df$angle <- ifelse(ang < -90, ang + 180, ang)

  lobes_df <- do.call(rbind, lapply(split(df, list(df$hemi, df$lobe), drop = TRUE), function(s)
    data.frame(hemi = s$hemi[1], lobe = s$lobe[1], xmin = min(s$pos) - 0.5, xmax = max(s$pos) + 0.5)))
  lobes_df$mid <- (lobes_df$xmin + lobes_df$xmax) / 2
  la <- 360 * (lobes_df$mid) / x_max     # clockwise from top: tangential text, kept upright
  lobes_df$angle <- ifelse(la > 90 & la < 270, 180 - la, -la)
  lobes_df$short <- ifelse(lobes_df$xmax - lobes_df$xmin >= 3, lobes_df$lobe, substr(lobes_df$lobe, 1, 3))

  ggplot(df) +
    geom_rect(data = lobes_df, aes(xmin = xmin, xmax = xmax, ymin = band_lo, ymax = band_hi, fill = NULL),
              fill = lobe_cols[lobes_df$lobe], colour = NA) +
    geom_text(data = lobes_df, aes(x = mid, y = (band_lo + band_hi) / 2, label = short, angle = angle),
              size = 2.1, colour = "grey25") +
    geom_hline(yintercept = 0, colour = "grey40", linewidth = 0.35) +
    geom_hline(yintercept = c(-br_threshold, br_threshold), colour = "grey40", linewidth = 0.3, linetype = "22") +
    geom_col(aes(x = pos, y = br, fill = fill), width = 0.8, colour = NA) +
    geom_text(aes(x = pos, y = lab_y, label = label, angle = angle, hjust = hjust),
              size = 2.05, colour = ifelse(df$sig, "grey10", "grey55")) +
    annotate("text", x = c(x_max * 0.25, x_max * 0.75), y = -lim - hole * 0.25, label = c("Right", "Left"),
             size = 3.2, fontface = "bold", colour = "grey35") +
    scale_fill_gradientn(colours = c(neg_dark, neg_pale, ns_grey, ns_grey, pos_pale, pos_dark),
                         values = scales::rescale(c(-lim, -br_threshold, -br_threshold + 1e-3,
                                                    br_threshold - 1e-3, br_threshold, lim)),
                         limits = c(-lim, lim), na.value = ns_grey, guide = "none") +
    scale_x_continuous(limits = c(0, x_max), expand = c(0, 0)) +
    scale_y_continuous(limits = c(y_min, y_max), expand = c(0, 0)) +
    coord_polar(start = 0, clip = "off") +
    labs(title = title, subtitle = subtitle) +
    theme_void(base_size = 10) +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12),
          plot.subtitle = element_text(hjust = 0.5, colour = "grey30", size = 8.5),
          legend.title = element_text(size = 8), legend.text = element_text(size = 7),
          plot.background = element_rect(fill = "white", colour = NA),
          plot.margin = margin(8, 8, 8, 8))
}

# ---- RNI / RND circular barplot, clean style -------------------------------
# Same order as the classic plot; labels and lobe band sit just outside the
# outermost bar, a BR scale runs down the top gap, bigger centre so inward
# (negative) bars are not squeezed.
plot_struct_bars_clean <- function(br, regs, lim, title, subtitle) {
  df <- data.frame(regs, br = br, stringsAsFactors = FALSE)
  lobe_of <- setNames(rep(names(dk_lobes), lengths(dk_lobes)), unlist(dk_lobes))
  df$lobe <- lobe_of[df$region]

  gap_lobe <- 1; gap_hemi <- 5
  rows <- list(); pos <- gap_hemi / 2
  for (h in c("rh", "lh")) {
    lobes <- if (h == "rh") names(dk_lobes) else rev(names(dk_lobes))
    for (lb in lobes) {
      regs_lb <- if (h == "rh") dk_lobes[[lb]] else rev(dk_lobes[[lb]])
      sub <- df[df$hemi == h & df$lobe == lb, ]
      sub <- sub[match(regs_lb, sub$region), ]
      sub <- sub[!is.na(sub$region), ]
      sub$pos <- pos + seq_len(nrow(sub))
      pos <- pos + nrow(sub) + gap_lobe
      rows[[length(rows) + 1]] <- sub
    }
    pos <- pos - gap_lobe + gap_hemi
  }
  df <- do.call(rbind, rows)
  x_max <- pos - gap_hemi / 2 + 0.5

  df$sig   <- abs(df$br) > br_threshold
  df$label <- dk_short[df$region]
  df$fillc <- if (bar_fill == "lobe") ifelse(df$sig, lobe_bar_cols[df$lobe], ns_grey)
              else br_cols(df$br, lim)

  # Radial layout (BR units). Everything outside the bars hugs the outermost bar.
  hole    <- 0.7 * lim
  out_top <- max(br_threshold, max(df$br, 0, na.rm = TRUE))   # outer edge of data
  band_lo <- out_top + 0.06 * lim; band_hi <- band_lo + 0.09 * lim
  lab_y   <- band_hi + 0.04 * lim
  y_min   <- -lim - hole; y_max <- lab_y + 0.75 * lim

  ang <- 90 - 360 * (df$pos - 0.5) / x_max
  df$hjust <- ifelse(ang < -90, 1, 0)
  df$angle <- ifelse(ang < -90, ang + 180, ang)

  lobes_df <- do.call(rbind, lapply(split(df, list(df$hemi, df$lobe), drop = TRUE), function(s)
    data.frame(hemi = s$hemi[1], lobe = s$lobe[1], xmin = min(s$pos) - 0.5, xmax = max(s$pos) + 0.5)))
  lobes_df$mid <- (lobes_df$xmin + lobes_df$xmax) / 2
  la <- 360 * lobes_df$mid / x_max
  lobes_df$angle <- ifelse(la > 90 & la < 270, 180 - la, -la)
  lobes_df$short <- ifelse(lobes_df$xmax - lobes_df$xmin >= 3, lobes_df$lobe, substr(lobes_df$lobe, 1, 3))

  # Radial scale in the top gap: 0, +/- threshold and round values within the data range
  lo <- min(df$br, -br_threshold, na.rm = TRUE); hi <- out_top
  tk <- sort(unique(c(0, -br_threshold, br_threshold, pretty(c(lo, hi), n = 4))))
  tk <- tk[tk >= lo - 1e-9 & tk <= hi + 1e-9]
  tk <- tk[!(abs(tk) > 0 & abs(abs(tk) - br_threshold) < 0.6 & abs(tk) != br_threshold)]  # avoid clutter near +/-thr
  ticks <- data.frame(y = tk, lab = ifelse(tk == 0, "0", formatC(tk, format = "fg")))
  # tick labels at the top midline (x = 0 / x_max), slightly into the gap
  ring_df <- data.frame(y = c(-br_threshold, br_threshold))
  grid_df <- data.frame(y = setdiff(tk, c(0, -br_threshold, br_threshold)))

  p <- ggplot(df) +
    geom_rect(data = lobes_df, aes(xmin = xmin, xmax = xmax, ymin = band_lo, ymax = band_hi),
              fill = lobe_cols[lobes_df$lobe], colour = NA) +
    # geom_text(data = lobes_df, aes(x = mid, y = (band_lo + band_hi) / 2, label = short, angle = angle),
    #           size = 2.0, colour = "grey30") +
    geom_hline(data = grid_df, aes(yintercept = y), colour = "grey88", linewidth = 0.3) +
    geom_hline(yintercept = 0, colour = "grey30", linewidth = 0.4) +
    geom_hline(data = ring_df, aes(yintercept = y), colour = "grey55", linewidth = 0.3, linetype = "22") +
    geom_col(aes(x = pos, y = br), fill = df$fillc, width = 0.78, colour = NA) +
    geom_text(aes(x = pos, y = lab_y, label = label, angle = angle, hjust = hjust),
              size = 4, colour = ifelse(df$sig, "grey10", "grey60")) +
    geom_text(data = ticks, aes(x = 0, y = y, label = lab), size = 4.2, colour = "grey40", hjust = 0.5) +
    #annotate("text", x = 0, y = lo - 0.12 * lim, label = "BR", size = 1.9, colour = "grey40", fontface = "italic") +
    annotate("text", x = c(x_max * 0.25, x_max * 0.75), y = y_min + hole * 0.8, label = c("Right", "Left"),
             size = 4, fontface = "bold", colour = "grey35") +
    scale_x_continuous(limits = c(0, x_max), expand = c(0, 0)) +
    scale_y_continuous(limits = c(y_min, y_max), expand = c(0, 0)) +
    coord_polar(start = 0, clip = "off") +
    labs(title = title, subtitle = subtitle) +
    theme_void(base_size = 10) +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12),
          plot.subtitle = element_text(hjust = 0.5, colour = "grey30", size = 8.5),
          plot.background = element_rect(fill = "white", colour = NA),
          plot.margin = margin(4, 4, 4, 4))

  p
}

plot_struct_bars <- function(...) {
  if (bar_style == "classic") plot_struct_bars_classic(...) else plot_struct_bars_clean(...)
}

# ---- Stand-alone colour bar (saved once) -------------------------------------
# Same look as the legend the region plots used to carry: BR colour scale with grey
# for |BR| <= br_threshold, ticks at round values and at +/- br_threshold.
br_colorbar_grob <- function(lim) {
  brks <- sort(unique(c(-br_threshold, br_threshold, pretty(c(-lim, lim)))))
  brks <- brks[abs(brks) <= lim]
  p <- ggplot(data.frame(x = 0, y = 0, v = c(-lim, lim)), aes(x, y, colour = v)) +
    geom_point(alpha = 0) +
    scale_colour_gradientn(colours = c(neg_dark, neg_pale, ns_grey, ns_grey, pos_pale, pos_dark),
                           values = scales::rescale(c(-lim, -br_threshold, -br_threshold + 1e-3,
                                                      br_threshold - 1e-3, br_threshold, lim)),
                           limits = c(-lim, lim), breaks = brks, labels = function(x) formatC(x, format = "fg"),
                           name = "Bootstrap\nratio",
                           guide = guide_colourbar(barheight = unit(5, "cm"), barwidth = unit(0.35, "cm"),
                                                   ticks.colour = "grey30")) +
    theme_void(base_size = 10) +
    theme(legend.title = element_text(size = 8), legend.text = element_text(size = 7))
  g <- ggplotGrob(p)
  i <- grep("guide-box", g$layout$name)
  i <- i[!vapply(g$grobs[i], inherits, logical(1), "zeroGrob")][1]   # ggplot2 >= 3.5 has one box per side
  g$grobs[[i]]
}

# ---- Run ---------------------------------------------------------------------
# One shared colour limit across every block and dimension (so one colour bar fits all plots)
if (is.null(br_lim)) {
  all_br <- unlist(lapply(blocks_to_run(), function(block) {
    d  <- plsc_dirs(block)
    pf <- file.path(d$plsc, "rsfc_P-components.csv")
    qf <- file.path(d$plsc, sprintf("%s_Q-components.csv", block))
    if (!file.exists(pf) || !file.exists(qf)) return(NULL)
    P <- read.csv(pf, row.names = 1, check.names = FALSE); Q <- read.csv(qf, row.names = 1, check.names = FALSE)
    cols <- intersect(paste0("BR_Dim", sig_dims(block)), intersect(names(P), names(Q)))
    unlist(c(P[cols], Q[cols]))
  }))
  br_lim <- if (length(all_br)) max(ceiling(max(abs(all_br), na.rm = TRUE)), ceiling(br_threshold) + 1) else 10
}
message(sprintf("Shared colour limit: +/-%g", br_lim))
for (dev in devs) {
  f <- file.path(deriv_dir, sprintf("circular_colorbar_BR.%s", dev))
  if (dev == "png") open_png(f, width = 450, height = 800, res = 300)
  else if (dev == "svg") svg_device(f, width = 1.5, height = 2.67)
  else pdf_device(f, width = 1.5, height = 2.67)
  grid::grid.newpage(); grid::grid.draw(br_colorbar_grob(br_lim))
  invisible(dev.off())
}
message("Colour bar -> ", file.path(deriv_dir, sprintf("circular_colorbar_BR.{%s}", paste(devs, collapse = ","))))

for (block in blocks_to_run()) {
  d  <- plsc_dirs(block)
  sb <- struct_blocks[[block]]
  message(sprintf("\n=== PLSC rs-FC x %s ===", toupper(block)))
  pf <- file.path(d$plsc, "rsfc_P-components.csv")
  qf <- file.path(d$plsc, sprintf("%s_Q-components.csv", block))
  if (!file.exists(pf) || !file.exists(qf)) { message("  no PLSC results in ", d$plsc, " - run 1b for this block first"); next }

  P <- read.csv(pf, row.names = 1, check.names = FALSE)
  Q <- read.csv(qf, row.names = 1, check.names = FALSE)
  pairs <- parse_rsfc(rownames(P))
  regs  <- parse_dk(rownames(Q), sb$prefix)

  vf  <- file.path(d$plsc, "percent_variance_explained.csv")
  pct <- if (file.exists(vf)) read.csv(vf)$Percent_Variance else NULL

  for (k in sig_dims(block)) {
    col <- paste0("BR_Dim", k)
    if (!col %in% names(P) || !col %in% names(Q)) { message("  no ", col, " (only ", nf2keep, " dims bootstrapped) - skipped"); next }
    brP <- P[[col]]; brQ <- Q[[col]]
    s   <- dim_sign(block, k, regs, brQ)
    brP <- s * brP; brQ <- s * brQ          # flip both sides together, so the pairing is unchanged
    lim <- br_lim
    pct_txt <- if (!is.null(pct) && length(pct) >= k) sprintf(" (%.1f%% of covariance)", pct[k]) else ""

    # rs-FC chord
    title1 <- sprintf("rsFC x %s, Dimension %d%s: functional side", toupper(block), k, pct_txt)
    sub1   <- sprintf("Chords: between-network rsFC with |BR| > %.1f%s", br_threshold,
                    if (show_within_ring) "   Inner ring: within-network BR" else "")
    for (dev in devs) {
      f <- file.path(d$fig, sprintf("circular_rsfc_%s_Dim%d.%s", block, k, dev))
      if (dev == "png") open_png(f, width = 2000, height = 2000, res = 300)
      else if (dev == "svg") svg_device(f, width = 6.67, height = 6.67)
      else pdf(f, width = 6.67, height = 6.67)
      if (show_titles) plot_rsfc_chord(brP, pairs, lim, title1, sub1) else plot_rsfc_chord(brP, pairs, lim, "", "")
      invisible(dev.off())
    }

    # RNI / RND bars
    title2 <- sprintf("rsFC x %s, Dimension %d%s: %s", toupper(block), k, pct_txt, sb$label)
    sub2   <- sprintf("Bars: regional BR (dashed rings at +/-%.1f; grey = not reliable)", br_threshold)
    p2 <- if (show_titles) plot_struct_bars(brQ, regs, lim, title2, sub2) else plot_struct_bars(brQ, regs, lim, NULL, NULL)
    ggsave(file.path(d$fig, sprintf("circular_%s_Dim%d.png", block, k)), p2, width = 7.2, height = 7.2, dpi = 300, bg = "white")
    ggsave(file.path(d$fig, sprintf("circular_%s_Dim%d.pdf", block, k)), p2, width = 7.2, height = 7.2, device = pdf_device)
    if (!is.null(svg_device))
      ggsave(file.path(d$fig, sprintf("circular_%s_Dim%d.svg", block, k)), p2, width = 7.2, height = 7.2, device = svg_device, bg = "white")

    message(sprintf("  Dim%d (sign %+d): %d/%d rs-FC and %d/%d %s features with |BR| > %.1f -> circular_*_Dim%d.png/.pdf/.svg",
                    k, s, sum(abs(brP) > br_threshold), length(brP), sum(abs(brQ) > br_threshold), length(brQ),
                    toupper(block), br_threshold, k))
  }
}
message("\nDone.")
