#!/usr/bin/env python3
"""
0-make-fake-data.py
-------------------
Builds a small FAKE ABCD-7.0-style release so the whole pipeline can be tested
on a laptop. Nothing here is real data.

Mimics the real release layout: one file per table, each written as both
<table>.parquet and <table>.tsv, long format with participant_id + session_id.

Sessions:  ses-00A (baseline), ses-02A (Year 2), ses-04A (Year 4)
  - imaging (rs-FC, RNI, RND, motion, QC, scanner) at ses-02A and ses-04A
  - reward / ER / EF questionnaires and tasks at ses-02A and ses-04A
  - some caregiver demographics only at baseline, and household income
    missing at Year 4 for ~20%, so the "most recent available" covariate
    logic in 1a-extract-abcd.R gets exercised

Built-in structure (loosely after Bottenhorn et al. preprint) so the PLSCs and
LMEs have something to find:
  z_glob : global RNI  <-> sensorimotor rs-FC gradient
  z_attn : widespread RND  <-> attention profile (DAN/FPN up, VAN/CON down);
           also better flanker, lower UPPS urgency, lower DERS
  z_rc   : rostro-caudal RNI/RND gradient <-> weaker sensorimotor gradient
  z_trip : triple-network rs-FC  <-> ERQ reappraisal
  z_pt   : pubertal timing (earlier maturers) -> stronger RNI-linked
           sensorimotor-gradient coupling (RNI only, not RND)
  puberty moderation: the attention-profile -> Flanker link grows with
           Year 4 pubertal stage (weak in pre/early, strong in late puberty)

Puberty: caregiver PDS category (1 pre .. 5 post) at every wave, in
separate female / male columns like ABCD (ph_p_pds).

Output:  <project>/dset/   (pipeline outputs go to derivatives/, never here)
Column names match the defaults in config.R.

Usage (from code/):   python3 0-make-fake-data.py [--n 600]
Needs: numpy, pandas, pyarrow
"""
import argparse
from pathlib import Path

import numpy as np
import pandas as pd

parser = argparse.ArgumentParser()
parser.add_argument("--n", type=int, default=600, help="number of fake participants")
parser.add_argument("--seed", type=int, default=2026)
parser.add_argument(
    "--out",
    default=str(Path(__file__).resolve().parent.parent / "dset"),
)
args = parser.parse_args()

rng = np.random.default_rng(args.seed)
out = Path(args.out)
out.mkdir(parents=True, exist_ok=True)
for f in list(out.glob("*.tsv")) + list(out.glob("*.parquet")):   # replace old fake tables only
    f.unlink()
N = args.n
ALL_SES = ["ses-00A", "ses-02A", "ses-04A"]
IMG_SES = ["ses-02A", "ses-04A"]

# ---------------------------------------------------------------------------
# participants, families, sites, latent factors
# ---------------------------------------------------------------------------
ids = np.array([f"sub-NDARINVFAKE{i:04d}" for i in range(N)])
fam = np.arange(N)
sib_idx = rng.choice(N, size=N // 4, replace=False)          # ~25% twins/sibs
fam[sib_idx] = fam[(sib_idx + 1) % N]
fam_ids = np.array([f"fam{f:05d}" for f in fam])
sites = rng.integers(1, 23, size=N)
site_ids = np.array([f"site{s:02d}" for s in sites])
site_eff = rng.normal(0, 0.3, size=23)[sites]
manu_by_site = {s: rng.choice(["SIEMENS", "GE MEDICAL SYSTEMS", "Philips Medical Systems"], p=[.6, .25, .15])
                for s in range(1, 23)}
manufacturer = np.array([manu_by_site[s] for s in sites])
sex = rng.choice([1, 2], size=N)

z_glob, z_attn, z_rc, z_trip = (rng.normal(size=N) for _ in range(4))
age0 = rng.uniform(9.0, 10.9, size=N)

# Puberty: girls start ~1 year earlier; z_pt = individual timing (earlier = higher)
z_pt = rng.normal(size=N)
onset = np.where(sex == 2, 10.3, 11.4)


def pds_stage_at(years_from_baseline):
    m = (age0 + years_from_baseline - onset) / 1.4 + 0.7 * z_pt + rng.normal(0, 0.3, N)
    return np.clip(np.round(1 + m), 1, 5)


pds_by_ses = {"ses-00A": pds_stage_at(0), "ses-02A": pds_stage_at(2), "ses-04A": pds_stage_at(4)}
pds_y4 = pds_by_ses["ses-04A"]
rsfmri_fd = np.abs(rng.gamma(2, 0.08, size=N))
dmri_motion = np.abs(rng.gamma(4, 0.3, size=N))


def write(df, name):
    df.to_parquet(out / f"{name}.parquet", index=False)
    df.to_csv(out / f"{name}.tsv", sep="\t", index=False, na_rep="")
    print(f"  wrote {name:<28} {df.shape[0]:>6} rows x {df.shape[1]:>4} cols")


def long_frame(make_cols, sessions):
    """make_cols(session_index) -> dict of column arrays for that session."""
    frames = []
    for i, ses in enumerate(sessions):
        df = pd.DataFrame({"participant_id": ids, "session_id": ses})
        for k, v in make_cols(i, ses).items():
            df[k] = v
        frames.append(df)
    return pd.concat(frames, ignore_index=True)


def drop_rows(df, frac, cols=None):
    cols = cols if cols is not None else df.columns[2:]
    df.loc[rng.random(len(df)) < frac, cols] = np.nan
    return df


print(f"Writing fake ABCD release to {out}")

# ---------------------------------------------------------------------------
# admin / demographics
# ---------------------------------------------------------------------------
write(pd.DataFrame({"participant_id": ids, "ab_g_stc__cohort_sex": sex,
                    "ab_g_stc__design_id__fam": fam_ids}), "ab_g_stc")

write(long_frame(lambda i, s: {
    "ab_g_dyn__visit_age": np.round(age0 + 2 * i + rng.normal(0, .1, N), 2),
    "ab_g_dyn__design_site": site_ids}, ALL_SES), "ab_g_dyn")

prnt_gender = rng.choice([1, 2], size=N, p=[.1, .9])
origin = rng.choice([1, 2, 3], size=N, p=[.85, .1, .05])
prnt_ed = rng.integers(10, 22, size=N).astype(float)
prtnr_ed = rng.integers(10, 22, size=N).astype(float)
prtnr_ed[rng.random(N) < 0.08] = 777
prnt_age0 = np.round(rng.normal(40, 6, N))


def demo_cols(i, ses):
    income = np.clip(rng.integers(1, 11, size=N) + i, 1, 10).astype(float)
    income[rng.random(N) < 0.05] = 999
    if ses == "ses-04A":
        income[rng.random(N) < 0.20] = np.nan        # missing at Y4 -> falls back to Y2
    return {
        "ab_p_demo__age__prnt": prnt_age0 + 2 * i,
        "ab_p_demo__gender__prnt": prnt_gender if ses == "ses-00A" else np.nan,   # baseline only
        "ab_p_demo__edu__prnt": prnt_ed if ses != "ses-04A" else np.nan,          # not asked at Y4
        "ab_p_demo__edu__prtnr": prtnr_ed if ses != "ses-04A" else np.nan,
        "ab_p_demo__income__hhold": income,
        "ab_p_demo__origin__child": origin if ses == "ses-00A" else np.nan,       # baseline only
    }


write(long_frame(demo_cols, ALL_SES), "ab_p_demo")

# ---------------------------------------------------------------------------
# MRI admin / motion / QC  (imaging waves only)
# ---------------------------------------------------------------------------
write(long_frame(lambda i, s: {"mr_y_adm__info__dev_manufacturer": manufacturer}, IMG_SES), "mr_y_adm__info")
write(long_frame(lambda i, s: {
    "mr_y_qc__motion__rsfmri__fd_mean": np.round(rsfmri_fd + rng.normal(0, .02, N).clip(0), 4),
    "mr_y_qc__motion__dmri__mean": np.round(dmri_motion + rng.normal(0, .1, N).clip(0), 3)}, IMG_SES),
    "mr_y_qc__motion")
write(long_frame(lambda i, s: {
    "mr_y_qc__incl__rsfmri_indicator": (rng.random(N) > 0.08).astype(int),
    "mr_y_qc__incl__dmri_indicator": (rng.random(N) > 0.05).astype(int)}, IMG_SES), "mr_y_qc__incl")

# ---------------------------------------------------------------------------
# FUNCTION: Gordon network-network rs-FC (13 nets incl "none" -> 78 after excluding n)
# ---------------------------------------------------------------------------
sensorimotor = {"vs", "smh", "smm", "ad"}
attn_memory = {"ca", "rspltp", "dla", "cgc", "vta"}
triple = {"sa", "fo", "dt"}
nets = ["ad", "cgc", "ca", "dt", "dla", "fo", "n", "rspltp", "smh", "smm", "sa", "vta", "vs"]
pairs = [(a, b) for i, a in enumerate(nets) for b in nets[i:]]


def rsfc_loadings(a, b):
    s = {a, b}
    # sensorimotor gradient: within-SM up, SM x triple down
    sm = 0.04 if s <= sensorimotor else (-0.03 if (s & sensorimotor and s & triple) else 0.0)
    # attention profile: DAN / FPN up, VAN / CON down, within-network down
    at = 0.03 * bool(s & {"dla", "fo"}) - 0.03 * bool(s & {"vta", "cgc"}) - (0.015 if a == b else 0)
    tr = 0.03 if (s <= triple) else 0.0
    return sm, at, tr


rsfc = {}
for a, b in pairs:
    base = 0.25 if a == b else rng.normal(0, 0.05)
    sm, at, tr = rsfc_loadings(a, b)
    vals = (base + sm * (z_glob + 0.6 * z_pt) + 0.4 * sm * z_rc + at * z_attn + tr * z_trip
            + 0.02 * site_eff + 0.05 * rsfmri_fd + rng.normal(0, 0.06, N))
    rsfc[f"mr_y_rsfmri__corr__gpnet__{a}_{b}"] = vals
rs_df = long_frame(lambda i, s: {k: np.round(v + rng.normal(0, .03, N), 4) for k, v in rsfc.items()}, IMG_SES)
write(drop_rows(rs_df, 0.04), "mr_y_rsfmri__corr__gpnet")

# ---------------------------------------------------------------------------
# STRUCTURE: RSI restricted normalized isotropic (RNI) and directional (RND),
# Desikan cortical GM, 34 lh + 34 rh, unitless 0-1
# ---------------------------------------------------------------------------
dsk = ["bankssts", "caudalanteriorcingulate", "caudalmiddlefrontal", "cuneus", "entorhinal",
       "fusiform", "inferiorparietal", "inferiortemporal", "isthmuscingulate", "lateraloccipital",
       "lateralorbitofrontal", "lingual", "medialorbitofrontal", "middletemporal", "parahippocampal",
       "paracentral", "parsopercularis", "parsorbitalis", "parstriangularis", "pericalcarine",
       "postcentral", "posteriorcingulate", "precentral", "precuneus", "rostralanteriorcingulate",
       "rostralmiddlefrontal", "superiorfrontal", "superiorparietal", "superiortemporal",
       "supramarginal", "frontalpole", "temporalpole", "transversetemporal", "insula"]
anterior = {"caudalanteriorcingulate", "caudalmiddlefrontal", "lateralorbitofrontal", "medialorbitofrontal",
            "parsopercularis", "parsorbitalis", "parstriangularis", "rostralanteriorcingulate",
            "rostralmiddlefrontal", "superiorfrontal", "frontalpole", "insula"}
posterior = {"cuneus", "lateraloccipital", "lingual", "pericalcarine", "inferiorparietal",
             "superiorparietal", "precuneus", "isthmuscingulate", "posteriorcingulate"}
rnd_exceptions = {"insula", "pericalcarine", "parsopercularis", "paracentral"}


def rsi_table(name, base_mean, w_glob, w_attn, w_rc_sign, w_pt=0.0):
    cols = {}
    for roi in dsk:
        rc = 1 if roi in anterior else (-1 if roi in posterior else 0)
        base = rng.uniform(base_mean - .05, base_mean + .05)
        for hemi in ["lh", "rh"]:
            attn_w = 0 if roi in rnd_exceptions else w_attn
            vals = (base + w_glob * z_glob + w_pt * z_pt + attn_w * z_attn + w_rc_sign * rc * 0.010 * z_rc
                    + 0.006 * site_eff - 0.004 * dmri_motion + rng.normal(0, 0.02, N))
            cols[f"mr_y_rsi__{name}__dsk__{roi}__{hemi}"] = vals
    df = long_frame(lambda i, s: {k: np.round(v + 0.01 * (i + 1) + rng.normal(0, .008, N), 4)
                                  for k, v in cols.items()}, IMG_SES)
    roi_cols = [c for c in df.columns if c.startswith(f"mr_y_rsi__{name}__dsk__")]
    df[f"mr_y_rsi__{name}__dsk__mean"] = df[roi_cols].mean(axis=1).round(4)
    write(drop_rows(df, 0.03), f"mr_y_rsi__{name}__dsk")


rsi_table("rni", 0.32, w_glob=0.012, w_attn=0.002, w_rc_sign=+1, w_pt=0.008)   # cell density: global + anterior-high
rsi_table("rnd", 0.42, w_glob=0.002, w_attn=0.010, w_rc_sign=-1)   # neurite density: widespread + posterior-high

# ---------------------------------------------------------------------------
# Behaviour at Year 2 and Year 4
# ---------------------------------------------------------------------------
def clip_round(x, lo, hi, nd=0):
    return np.round(np.clip(x, lo, hi), nd)


write(long_frame(lambda i, s: {
    "mh_y_bisbas__bis_sum": clip_round(12 + rng.normal(0, 3, N), 0, 21),
    "mh_y_bisbas__rr_sum": clip_round(13 + 0.3 * z_trip + rng.normal(0, 2.5, N), 0, 15),
    "mh_y_bisbas__drive_sum": clip_round(6 + rng.normal(0, 2.5, N), 0, 12),
    "mh_y_bisbas__fs_sum": clip_round(7 + 0.3 * z_glob + rng.normal(0, 2.2, N), 0, 12)}, IMG_SES), "mh_y_bisbas")

write(long_frame(lambda i, s: {
    "mh_y_upps__nurg_sum": clip_round(9 - 0.8 * z_attn + rng.normal(0, 2.5, N), 4, 16),
    "mh_y_upps__purg_sum": clip_round(8 - 0.5 * z_attn + rng.normal(0, 2.5, N), 4, 16),
    "mh_y_upps__lpm_sum": clip_round(8 - 0.4 * z_attn + rng.normal(0, 2.5, N), 4, 16),
    "mh_y_upps__lps_sum": clip_round(7 + rng.normal(0, 2.3, N), 4, 16),
    "mh_y_upps__ss_sum": clip_round(10 + 0.4 * z_glob + rng.normal(0, 2.6, N), 4, 16)}, IMG_SES), "mh_y_upps")

write(long_frame(lambda i, s: {
    "mh_y_erq__reapp_mean": clip_round(3.4 + 0.3 * z_trip + rng.normal(0, .8, N), 1, 5, 2),
    "mh_y_erq__suppr_mean": clip_round(2.8 + rng.normal(0, .8, N), 1, 5, 2)}, IMG_SES), "mh_y_erq")

write(long_frame(lambda i, s: {
    "mh_p_ders_sum": clip_round(60 - 4 * z_attn - 3 * z_trip + rng.normal(0, 14, N), 33, 140)}, IMG_SES), "mh_p_ders")


def nihtb_cols(i, ses):
    cols = {
        # puberty moderation: slope on z_attn rises from ~1 (pre) to ~15 (post-pubertal)
        "nc_y_nihtb__flnkr__agecor": np.round(95 + (1 + 3.5 * (pds_y4 - 1)) * z_attn + rng.normal(0, 10, N)),
        "nc_y_nihtb__pttcp__agecor": np.round(95 + 1.5 * z_glob + rng.normal(0, 15, N)),
    }
    # Card sort / list sort only at baseline-style waves: absent at Y4 to test skipping
    cols["nc_y_nihtb__cardsort__agecor"] = np.round(95 + rng.normal(0, 14, N)) if ses != "ses-04A" else np.nan
    cols["nc_y_nihtb__lswmt__agecor"] = np.round(100 + rng.normal(0, 15, N)) if ses != "ses-04A" else np.nan
    return cols


nb = long_frame(nihtb_cols, IMG_SES)

# ---------------------------------------------------------------------------
# Puberty: caregiver PDS category, female and male columns (ABCD layout)
# ---------------------------------------------------------------------------
def pds_cols(i, ses):
    st = pds_by_ses[ses].copy()
    st[rng.random(N) < 0.04] = np.nan                  # some missing reports
    return {"ph_p_pds__f_categ": np.where(sex == 2, st, np.nan),
            "ph_p_pds__m_categ": np.where(sex == 1, st, np.nan)}


write(long_frame(pds_cols, ALL_SES), "ph_p_pds")
nb.loc[rng.random(len(nb)) < 0.06, "nc_y_nihtb__flnkr__agecor"] = np.nan
write(nb, "nc_y_nihtb")

print("Done.")
