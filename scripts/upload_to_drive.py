#!/usr/bin/env python3
"""Upload one shard directory to Google Drive (small-unit collection).

Auth: a GCP service-account JSON in env GDRIVE_SA_JSON; the target Drive
folder (env DRIVE_OUT_FOLDER, a folder id) must be shared with the service
account's email as Editor. Each shard becomes a subfolder named like
CFG_SEQ_QP containing its csv.gz / log / manifest files.

usage: upload_to_drive.py <shard_dir>
"""
import json, os, sys, mimetypes

def main(shard_dir):
    sa = os.environ.get("GDRIVE_SA_JSON")
    folder = os.environ.get("DRIVE_OUT_FOLDER")
    if not sa or not folder:
        print("GDRIVE_SA_JSON / DRIVE_OUT_FOLDER not set - skipping Drive upload")
        return 0
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload

    creds = service_account.Credentials.from_service_account_info(
        json.loads(sa), scopes=["https://www.googleapis.com/auth/drive"])
    svc = build("drive", "v3", credentials=creds)

    name = os.path.basename(os.path.normpath(shard_dir))
    # reuse existing subfolder on re-run
    q = (f"name='{name}' and '{folder}' in parents and "
         "mimeType='application/vnd.google-apps.folder' and trashed=false")
    hits = svc.files().list(q=q, fields="files(id)").execute().get("files", [])
    if hits:
        sub = hits[0]["id"]
    else:
        sub = svc.files().create(body={
            "name": name, "parents": [folder],
            "mimeType": "application/vnd.google-apps.folder"},
            fields="id").execute()["id"]

    for fn in sorted(os.listdir(shard_dir)):
        p = os.path.join(shard_dir, fn)
        if not os.path.isfile(p):
            continue
        mt = mimetypes.guess_type(fn)[0] or "application/octet-stream"
        media = MediaFileUpload(p, mimetype=mt, resumable=True)
        svc.files().create(body={"name": fn, "parents": [sub]},
                           media_body=media, fields="id").execute()
        print(f"uploaded {fn} ({os.path.getsize(p)} B)")
    print(f"shard {name} -> Drive folder {sub}")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
