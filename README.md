# vtm-workload-campaign

CI harness for the one-shot VTM data-collection campaign
(see `VTM_DATA_COLLECTION_SPEC.pdf` in the analysis tree).

**This repo contains CODE ONLY. CTC test sequences are NOT redistributable and
must NEVER be committed here.** Sequence YUVs live in a shared Google Drive
folder; jobs fetch them via the `DRIVE_IDS` secret and hold them in the free
GitHub Actions cache (10 GB/repo). Shard outputs are uploaded in small units
to a Drive output folder (`DRIVE_OUT_FOLDER`) so nothing large accumulates in
GitHub storage; Actions artifacts are the fallback copy.

## Architecture

| where | what runs |
|---|---|
| GitHub-hosted runners (free, unlimited on public repo, 6 h/job cap) | build + smoke + light shards: class C/D all configs, class B/E AI |
| self-hosted runner on a GCP trial-credit spot VM (no 6 h cap) | heavy shards: class B/E RA/LDB/LDP |
| local 16-core machine or GCP trial VM | class A1/A2 UHD extension set |
| shared Google Drive | YUV sequences in (`DRIVE_IDS`), shard outputs collected (`DRIVE_OUT_FOLDER`) |

## Setup (once)

1. Confirm every sequence file in the Drive folder is link-accessible
   ("Anyone with the link") - gdown on the runner has no Google login.
2. Repo -> Settings -> Secrets and variables -> Actions:
   - `DRIVE_IDS` - JSON map {SequenceName: GoogleDriveFileId} for the YUVs
     (kept as a secret so CTC file ids never appear in the public repo)
   - `DRIVE_OUT_FOLDER` - Drive folder id where shards are collected
   - `GDRIVE_SA_JSON` - a GCP service-account key (Drive API enabled); share
     the output folder with the service account's email as Editor
3. Run the **smoke** workflow (Actions tab -> smoke -> Run workflow).
   It builds VTM and encodes 30 frames of BQSquare AI QP32 on a hosted runner.
4. When the instrumentation patch lands in `patch/`, re-run smoke and check
   the S1/S2/S3 shard files it uploads.
5. Dispatch `campaign` with the shard filters you want.

## Self-hosted GCP runner (heavy shards)

```bash
# on a fresh GCP VM (e.g. c2d-standard-8 SPOT, Ubuntu 22.04, ~$0.10/h):
sudo apt-get update && sudo apt-get install -y build-essential cmake git ccache python3-pip
mkdir actions-runner && cd actions-runner
# then: repo -> Settings -> Actions -> Runners -> New self-hosted runner,
# copy the ./config.sh line GitHub shows you, add labels:  gcp,heavy
./run.sh   # or install as a service
```

Dispatch `campaign` with `runner=self-hosted` for the heavy shard set.

## VTM version

`VTM_TAG` in the workflows **must match the Phase-1 runs exactly** -
reconciliation check V5 depends on it. It is currently a placeholder:
set it before the first real shard. The instrumentation patch is
OBSERVATION-ONLY: it logs, never changes a coding decision, so bitstreams
stay bit-identical to the unpatched reference model.

## Shard naming / outputs

`S{1,2,3}_<cfg>_<seq>_<qp>.csv.gz` + `manifest.frag.json` per job, one Drive
subfolder per shard. Validation: `scripts/validate_shard.py`
(V1-V4, V7, V8 subset that is checkable per-shard).
