#!/bin/bash
#
# restart - Restart a single mmo-cr backend service (down + build + up).
#
# Usage:
#   scripts/restart rd   # restart mmo-cr-reference-data-service
#   scripts/restart cr   # restart mmo-cr-catch-recording-service

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <rd|cr>"
  echo
  echo "  rd   Restart mmo-cr-reference-data-service"
  echo "  cr   Restart mmo-cr-catch-recording-service"
  exit 1
}

if [ "$#" -ne 1 ]; then
  usage
fi

case "$1" in
  rd)
    SERVICE="mmo-cr-reference-data-service"
    ;;
  cr)
    SERVICE="mmo-cr-catch-recording-service"
    ;;
  *)
    echo "Error: unknown parameter '$1'" >&2
    usage
    ;;
esac

cd "${REPO_ROOT}"

echo "Restarting ${SERVICE}..."

docker compose down "${SERVICE}"
docker compose up --build -d "${SERVICE}"

echo "${SERVICE} restarted."
