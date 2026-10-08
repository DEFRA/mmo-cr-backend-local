#!/bin/bash
set -euo pipefail

# S3 buckets
# Idempotent: with floci's hybrid storage mode (shared floci-data volume), the
# bucket persists across restarts, so a plain "aws s3 mb" would fail on rerun.
BUCKET="mmo-cr-catch-recording-artifacts"
if aws s3api head-bucket --bucket "$BUCKET" --endpoint-url http://localhost:4566 2>/dev/null; then
  echo "[floci-init] Bucket '${BUCKET}' already exists; skipping creation."
else
  aws s3 mb "s3://${BUCKET}" --endpoint-url http://localhost:4566
fi

# SQS queues
#aws sqs create-queue --queue-name my-queue
