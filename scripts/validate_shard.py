#!/usr/bin/env python3
"""Per-shard subset of the acceptance checks (V1-V4, V7, V8).

Until the instrumentation patch lands, S1/S2/S3 files won't exist and this
script only checks that the encode completed. Once the patch produces the
streams, the checks below activate automatically.

Cross-shard checks (V5 Phase-1 reconciliation, V6 AI completeness, V9
manifest) run in the analysis tree after all shards are collected.
"""
import sys, os, gzip, csv, json

def rows(path):
    with gzip.open(path, "rt") as f:
        yield from csv.DictReader(f)

def main(shard_dir):
    ok = True
    log = os.path.join(shard_dir, "encoder.log.gz")
    if not os.path.exists(log):
        print("FAIL: encoder.log.gz missing"); return 1
    tail = gzip.open(log, "rt").read()[-2000:]
    if "Total Time" not in tail and "Bytes written" not in tail:
        print("WARN: encoder log has no completion footer - encode may have died")
        ok = False

    s1 = [f for f in os.listdir(shard_dir) if f.startswith("S1_")]
    if not s1:
        print("NOTE: no S1 stream (instrumentation patch not applied) - "
              "encode-only validation passed" if ok else "...and encode looks broken")
        return 0 if ok else 1

    s1p = os.path.join(shard_dir, s1[0])
    winners = 0; last = -1; mono = True
    tu_win = {}
    shapes = set()
    LEGAL = {1, 2, 4, 8, 16, 32, 64}
    for r in rows(s1p):
        c = int(r["fwd_ctr"])
        if c <= last: mono = False
        last = c
        w, h = int(r["w"]), int(r["h"])
        shapes.add((w, h))
        if w not in LEGAL or h not in LEGAL:
            print(f"FAIL V8: illegal dim {w}x{h}"); ok = False
        if r["is_winner"] == "1":
            winners += 1
            tu_win[r["tu_id"]] = tu_win.get(r["tu_id"], 0) + 1
    dup = sum(1 for v in tu_win.values() if v > 1)
    print(f"S1 rows ok: winners={winners}, dup-winner tu_ids={dup}, "
          f"ctr monotonic={mono}, shapes={len(shapes)}")
    if dup: print("FAIL V1: duplicate winners"); ok = False
    if not mono: print("FAIL V7: fwd_ctr not monotonic"); ok = False

    for tag in ("S2_", "S3_"):
        fs = [f for f in os.listdir(shard_dir) if f.startswith(tag)]
        if not fs:
            print(f"WARN: {tag}* missing"); ok = False
    # V3/V4 joins
    s2 = [f for f in os.listdir(shard_dir) if f.startswith("S2_")]
    s3 = [f for f in os.listdir(shard_dir) if f.startswith("S3_")]
    if s2:
        s2rows = list(rows(os.path.join(shard_dir, s2[0])))
        if len(s2rows) != winners:
            print(f"FAIL V3: S2 rows {len(s2rows)} != S1 winners {winners}"); ok = False
        if s3:
            exp = sum(1 for r in s2rows if r["cbf"] == "1" and r.get("is_ts", "0") != "1")
            got = sum(1 for _ in rows(os.path.join(shard_dir, s3[0])))
            if got != exp:
                print(f"FAIL V4: S3 rows {got} != expected {exp}"); ok = False
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
