# Data versioning

Raw Kinetics clips are **not** DVC-tracked (TBs — pointless to hash). They live
in the S3 data bucket, which has **bucket versioning enabled** (immutable). What
gets versioned is the small stuff that defines a dataset snapshot:

- `manifests/train.csv`, `manifests/val.csv` — `path,label` rows
- `manifests/dataset_version.json` — counts + content hashes + source URI

## Workflow

```bash
# 1. Build manifests from a class-foldered video tree (local or FSx mount)
python data/build_manifest.py \
  --videos-root /data/kinetics400 \
  --out-dir data/manifests --val-split 0.1 \
  --source-uri s3://<data-bucket>/kinetics400

# 2. One-time DVC init + S3 remote, then track + push
DATA_BUCKET=<data-bucket> ./scripts/setup_dvc.sh
git add data/manifests/*.dvc data/.gitignore .dvc/config
git commit -m "data: version kinetics manifests with dvc"
dvc push
```

The trainer logs the manifest hash to MLflow per run (`dataset_hash` tag), so an
experiment is reproducible: `git checkout <commit> && dvc pull` restores the
exact manifests that produced a model.
