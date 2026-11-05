#!/bin/bash
# =============================================================================
# 0-pull-hpc-data.sh - copy the ABCD 7.0 tables this project needs from the
# FIU HPC to dset/ on your laptop (tar streamed over ssh, so it's encrypted
# like scp but one connection, one password/Duo prompt).
#
# Usage (from anywhere):
#   bash code/0-pull-hpc-data.sh USER@HPC_HOST
#   REMOTE=USER@HPC_HOST bash code/0-pull-hpc-data.sh
#
# Tables that don't exist on the HPC are skipped with a WARN line instead of
# killing the whole transfer. Re-running overwrites files in dset/.
# NOTE: dset/ is git-ignored; real ABCD data must never be committed.
# =============================================================================
set -euo pipefail

REMOTE="${1:-${REMOTE:-USER@HPC_HOST}}"
SRC="/home/data/nbc/Laird_ABCD/7_0_data/tabulated/release_abcd"
DEST="${DEST:-$HOME/Desktop/struc-func-plsc/dset}"

TABLES="ab_p_demo ab_g_stc ab_g_dyn nc_y_ehis
mr_y_qc__mot mr_y_qc__incl mr_y_rsfmri__corr__gpnet
mr_y_rsi__rni__gm__dsk mr_y_rsi__rnd__gm__dsk
mh_y_bisbas mh_y_upps mh_y_erq mh_p_ders
nc_y_flnkr nc_y_nihtb"

if [ "$REMOTE" = "USER@HPC_HOST" ]; then
  echo "ERROR: give your HPC login, e.g.  bash $0 jdoe@hpc.fiu.edu" >&2
  exit 1
fi

mkdir -p "$DEST"
echo "Pulling from $REMOTE:$SRC"
echo "        into $DEST"

# Remote side: collect <table>.* for each table, warn about any that are
# missing, then stream one tar archive back over the ssh connection.
# shellcheck disable=SC2086
ssh "$REMOTE" bash -s -- "$SRC" $TABLES <<'REMOTE_EOF' | tar -xvf - -C "$DEST"
set -u
cd "$1" || { echo "ERROR: cannot cd to $1" >&2; exit 1; }
shift
shopt -s nullglob
files=()
for t in "$@"; do
  m=( "$t".* )
  if [ ${#m[@]} -eq 0 ]; then
    echo "WARN: no files for table '$t' - skipped" >&2
  else
    files+=( "${m[@]}" )
  fi
done
if [ ${#files[@]} -eq 0 ]; then
  echo "ERROR: none of the tables matched" >&2
  exit 1
fi
tar -cf - "${files[@]}"
REMOTE_EOF

echo "Done. $(ls -1 "$DEST" | wc -l | tr -d ' ') files in $DEST"
