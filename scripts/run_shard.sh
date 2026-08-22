#!/usr/bin/env bash
# Run one (sequence, config, qp) shard.
# usage: run_shard.sh <Sequence> <AI|RA|LDB|LDP> <qp> [frames_override]
set -euo pipefail
SEQ="$1"; CFG="$2"; QP="$3"; FRAMES_OVR="${4:-}"

meta() { python3 -c "import json,sys; d=json.load(open('sequences.json')); print(d['$SEQ']['$1'])"; }
W=$(meta width); H=$(meta height); FPS=$(meta fps); FRAMES=$(meta frames); BD=$(meta bitdepth)
[ -n "$FRAMES_OVR" ] && FRAMES="$FRAMES_OVR"

case "$CFG" in
  AI)  CFGF=encoder_intra_vtm.cfg ;;
  RA)  CFGF=encoder_randomaccess_vtm.cfg ;;
  LDB) CFGF=encoder_lowdelay_vtm.cfg ;;
  LDP) CFGF=encoder_lowdelay_P_vtm.cfg ;;
  *) echo "bad cfg $CFG"; exit 2 ;;
esac

YUV="seq/${SEQ}.yuv"
[ -f "$YUV" ] || { echo "missing $YUV - sequence fetch failed"; exit 3; }

OUT="shards/${CFG}_${SEQ}_${QP}"
mkdir -p "$OUT"
# The instrumentation patch reads TRACE_DIR and writes S1/S2/S3 csv.gz there.
export TRACE_DIR="$PWD/$OUT"

PERSEQ="vtm/cfg/per-sequence/${SEQ}.cfg"
EXTRA=()
[ -f "$PERSEQ" ] && EXTRA+=(-c "$PERSEQ")

time ./vtm/build/source/App/EncoderApp/EncoderApp \
  -c "vtm/cfg/${CFGF}" "${EXTRA[@]}" \
  -i "$YUV" -wdt "$W" -hgt "$H" -fr "$FPS" -f "$FRAMES" \
  --InputBitDepth="$BD" -q "$QP" \
  -b "$OUT/str.bin" -o /dev/null \
  > "$OUT/encoder.log" 2>&1

gzip -f "$OUT/encoder.log"
rm -f "$OUT/str.bin"          # bitstream not needed for the campaign
( cd "$OUT" && sha256sum * > SHA256SUMS ) || true
python3 - <<PY
import json, os, glob
frag = {"shard": "${CFG}_${SEQ}_${QP}",
        "seq": "$SEQ", "cfg": "$CFG", "qp": $QP, "frames": $FRAMES,
        "files": {os.path.basename(f): os.path.getsize(f)
                  for f in glob.glob("$OUT/*")}}
json.dump(frag, open("$OUT/manifest.frag.json", "w"), indent=1)
PY
echo "shard $CFG/$SEQ/QP$QP done"
