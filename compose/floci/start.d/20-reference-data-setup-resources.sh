#!/bin/bash
# Idempotent local bucket provisioning for the Reference Data Service.
# Runs automatically as a Floci startup hook (see compose.yml volume mount).
set -euo pipefail

BUCKET="${REFERENCE_DATA_BUCKET:-mmo-cr-reference-data-service}"
REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-eu-west-2}}"

echo "[floci-init] Ensuring bucket '${BUCKET}' exists in region '${REGION}'..."

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "[floci-init] Bucket '${BUCKET}' already exists; skipping creation."
else
  # us-east-1 rejects an explicit LocationConstraint; every other region requires one.
  if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET"
  else
    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
  echo "[floci-init] Created bucket '${BUCKET}'."
fi

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
echo "[floci-init] Bucket versioning enabled on '${BUCKET}'."

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo "[floci-init] Public access blocked on '${BUCKET}'."

echo "[floci-init] Reference-data bucket provisioning complete."
