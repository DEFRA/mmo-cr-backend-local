#!/bin/bash
# Uploads every reference-data collection file in datafiles/ to the running
# reference-data service, replacing the matching dataset's collection.
#
# Reads dataset/schemaVersion/version from each file's own envelope (jq),
# so it works for any file dropped into datafiles/ without hardcoding names.
#
# Requires: WRITE_TOKEN and BASE_URL exported first, e.g.
#   export WRITE_TOKEN=write-token
#   export BASE_URL=http://localhost:3002
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="${DATA_DIR:-$REPO_ROOT/datafiles}"

: "${WRITE_TOKEN:?WRITE_TOKEN must be exported (see docs/manual-testing.md §2)}"
: "${BASE_URL:?BASE_URL must be exported, e.g. http://localhost:3002}"

for file in "$DATA_DIR"/*.json "$DATA_DIR"/*.geojson; do
  [ -e "$file" ] || continue

  dataset=$(jq -r '.dataset' "$file")
  schema_version=$(jq -r '.schemaVersion' "$file")
  version=$(jq -r '.version' "$file")

  echo "Uploading $file -> dataset=$dataset schemaVersion=$schema_version version=$version"

  curl -s -X PUT "$BASE_URL/api/v1/reference-data/$dataset" \
    -H "Authorization: Bearer $WRITE_TOKEN" \
    -F "file=@${file};type=application/json" \
    -F "schemaVersion=${schema_version}" \
    -F "version=${version}" | jq

  echo
done