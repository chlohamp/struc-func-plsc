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
#   circular_rsfc_<block>_Dim<k>.png/.pdf   rs-FC side: chord diagram
#       12 Gordon networks ordered along the S-A axis. Each chord is one
#       between-network connection; only |BR| > br_threshold is drawn,
#       coloured by its BR. The ring just inside the network names holds the
#       within-network BR. Every pair has the same chord width, so the layout
#       is identical across dimensions and PLSCs.
#
#   circular_<block>_Dim<k>.png/.pdf        RNI / RND side: circular barplot
#       68 Desikan regions, right hemisphere on the right and left on the left,
#       lobes running front (top) to back (bottom). Bar = BR; dashed rings at
#       +/- br_threshold; bars past the threshold are coloured.
#
# Both plots of a dimension share one colour scale. Because each dimension's
# sign is arbitrary, read them together: red on one side goes with red on the
# other, blue with blue.
#
# Needs: circlize, ggplot2 (both on CRAN)
#   PLSC_ENV=local Rscript 1d-plsc-circular-plots.R
# =============================================================================
source(file.path(Sys.getenv("PLSC_CODE_DIR", "."), "config.R"))

for (p in c("circlize", "ggplot2")) {
  if (!requireNamespace(p, quietly = TRUE)) stop("Package '", p, "' is not installed (install.packages('", p, "'))")
}
suppressPackageStartupMessages({ library(circlize); library(ggplot2) })

# ---- Look and feel -----------------------------------------------------------
# Gordon networks (ABCD abbreviations) along the sensorimotor-association axis,
# same order as the network-matrix figure in 1b. Colours match 1c-plsc-figures.
gordon <- data.frame(
  abbr  = c("vs", "smh", "smm", "ad", "ca", "rspltp", "dla", "cgc", "vta", "sa", "fo", "dt"),
  label = c("Visual", "SM hand", "SM mouth", "Auditory", "Cing-parietal", "Retrosplen-temp",
            "Dorsal attn", "Cing-opercular", "Ventral attn", "Salience", "Fronto-parietal", "Default"),
  col   = c("#44256B", "#1BBFE0", "#0050BF", "#5B040D", "#CE4E05", "#004502",
            "#DCAA32", "#8D0102", "#8A388F", "#010F89", "#018900", "#F89400"),
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
lobe_cols <- c(Frontal = "#C9D7E8", Insula = "#E8D9C9", Cingulate = "#E3C9E8",
               Temporal = "#CDE8C9", Parietal = "#E8E4C9", Occipital = "#D6D6D6")

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
  lab <- sub(rsfc_block$prefix, "", rn, fixed = TRUE)
  pr  <- strsplit(lab, "_", fixed = TRUE)
  ok  <- vapply(pr, function(p) length(p) == 2 && all(p %in% gordon$abbr), logical(1))
  if (!all(ok)) stop("Could not parse Gordon network pairs from rs-FC names, e.g.: ",
                     paste(head(lab[!ok], 3), collapse = ", "),
                     "\nEdit parse_rsfc() in 1d-plsc-circular-plots.R to match the real column names.")
  data.frame(a = vapply(pr, `[`, "", 1), b = vapply(pr, `[`, "", 2), stringsAsFactors = FALSE)
}
# RSI row names: <prefix><region>__<hemi>  e.g. mr_y_rsi__rni__dsk__precuneus__lh
# (hemisphere found anywhere in the name, so other orders also work)
parse_dk <- function(rn, prefix) {
  lab  <- tolower(sub(prefix, "", rn, fixed = TRUE))
  hemi <- ifelse(grepl("(^|[_.])lh([_.]|$)", lab), "lh", ifelse(grepl("(^|[_.])rh([_.]|$)", lab), "rh", NA))
  reg  <- gsub("(^|[_.])(lh|rh)([_.]|$)", "", lab)
  reg  <- gsub("[_.]", "", reg)
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

  layout(matrix(1:2, nrow = 1), widths = c(5, 1))
  par(mar = c(0.5, 0.5, 3.5, 0.5), xpd = NA)
  circos.clear()
  circos.par(start.degree = 90 + 360 / n / 2, clock.wise = TRUE, gap.degree = 2.5,
             cell.padding = c(0, 0, 0, 0), track.margin = c(0.005, 0.005),
             canvas.xlim = c(-1.3, 1.3), canvas.ylim = c(-1.3, 1.3), points.overflow.warning = FALSE)
  circos.initialize(factor(nets, levels = nets), xlim = c(0, n - 1))

  # Track 1: network blocks + names
  circos.track(ylim = c(0, 1), track.height = 0.07, bg.border = NA, panel.fun = function(x, y) {
    i <- idx[CELL_META$sector.index]
    circos.rect(0, 0, n - 1, 1, col = gordon$col[i], border = "white")
    circos.text(CELL_META$xcenter, 2.1, gordon$label[i], facing = "bending.inside",
                niceFacing = TRUE, cex = 0.72, col = "grey15")
  })
  # Track 2: within-network BR
  circos.track(ylim = c(0, 1), track.height = 0.07, bg.border = NA, panel.fun = function(x, y) {
    a <- CELL_META$sector.index
    v <- within$br[within$a == a]
    if (length(v) == 0) return()
    circos.rect(0.4, 0.05, n - 1.4, 0.95, col = br_cols(v, lim), border = "grey60", lwd = 0.5)
    circos.text(CELL_META$xcenter, 0.5, sprintf("%.1f", v), cex = 0.55,
                col = if (abs(v) > 0.75 * lim) "white" else "grey20", facing = "bending.inside", niceFacing = TRUE)
  })

  # Chords: significant between-network connections, weakest drawn first
  sig <- between[abs(between$br) > br_threshold, ]
  sig <- sig[order(abs(sig$br)), ]
  cf  <- br_col_fun(lim)
  for (k in seq_len(nrow(sig))) {
    i <- idx[sig$a[k]]; j <- idx[sig$b[k]]
    si <- slot_of(i, j); sj <- slot_of(j, i)
    circos.link(sig$a[k], c(si - 0.42, si + 0.42), sig$b[k], c(sj - 0.42, sj + 0.42),
                col = adjustcolor(cf(sig$br[k]), alpha.f = 0.85), border = NA, h.ratio = 0.55)
  }
  if (nrow(sig) == 0) text(0, 0, "No between-network\nconnection passes\n|BR| > threshold", cex = 0.8, col = "grey40")

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
                niceFacing = TRUE, cex = 0.7, col = "grey35", font = 3)
  }
  title(main = title, cex.main = 1.05, line = 2.2)
  mtext(subtitle, side = 3, line = 0.9, cex = 0.72, col = "grey30")
  circos.clear()

  # Colour bar
  par(mar = c(7, 1.2, 7, 3.2), xpd = FALSE)
  vals <- seq(-lim, lim, length.out = 201)
  cols <- br_cols(vals, lim)
  image(1, vals, matrix(vals, nrow = 1), col = cols, breaks = c(vals - diff(vals)[1] / 2, lim + diff(vals)[1] / 2),
        axes = FALSE, xlab = "", ylab = "")
  tk <- pretty(c(-lim, lim)); tk <- tk[abs(tk) <= lim]
  axis(4, at = tk, las = 1, cex.axis = 0.75, tck = -0.3)
  abline(h = c(-br_threshold, br_threshold), lty = 2, lwd = 0.8)
  mtext("Bootstrap\nratio", side = 3, line = 0.8, cex = 0.72)
  layout(1)
}

# ---- RNI / RND circular barplot ----------------------------------------------
plot_struct_bars <- function(br, regs, lim, title, subtitle) {
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
                         limits = c(-lim, lim), na.value = ns_grey, name = "Bootstrap\nratio",
                         guide = guide_colourbar(barheight = unit(5, "cm"), barwidth = unit(0.35, "cm"),
                                                 ticks.colour = "grey30")) +
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

# ---- Run ---------------------------------------------------------------------
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
    lim <- max(ceiling(max(abs(c(brP, brQ)), na.rm = TRUE)), ceiling(br_threshold) + 1)
    pct_txt <- if (!is.null(pct) && length(pct) >= k) sprintf(" (%.1f%% of covariance)", pct[k]) else ""

    # rs-FC chord
    title1 <- sprintf("rs-FC x %s, Dimension %d%s: functional side", toupper(block), k, pct_txt)
    sub1   <- sprintf("Chords: between-network rs-FC with |BR| > %.1f   Inner ring: within-network BR", br_threshold)
    for (dev in c("png", "pdf")) {
      f <- file.path(d$fig, sprintf("circular_rsfc_%s_Dim%d.%s", block, k, dev))
      if (dev == "png") png(f, width = 2400, height = 2000, res = 300) else pdf(f, width = 8, height = 6.67)
      plot_rsfc_chord(brP, pairs, lim, title1, sub1)
      invisible(dev.off())
    }

    # RNI / RND bars
    title2 <- sprintf("rs-FC x %s, Dimension %d%s: %s", toupper(block), k, pct_txt, sb$label)
    sub2   <- sprintf("Bars: regional BR (dashed rings at +/-%.1f; grey = not reliable)", br_threshold)
    p2 <- plot_struct_bars(brQ, regs, lim, title2, sub2)
    ggsave(file.path(d$fig, sprintf("circular_%s_Dim%d.png", block, k)), p2, width = 8, height = 7.2, dpi = 300, bg = "white")
    ggsave(file.path(d$fig, sprintf("circular_%s_Dim%d.pdf", block, k)), p2, width = 8, height = 7.2, device = cairo_pdf)

    message(sprintf("  Dim%d: %d/%d rs-FC and %d/%d %s features with |BR| > %.1f -> circular_*_Dim%d.png/.pdf",
                    k, sum(abs(brP) > br_threshold), length(brP), sum(abs(brQ) > br_threshold), length(brQ),
                    toupper(block), br_threshold, k))
  }
}
message("\nDone.")
