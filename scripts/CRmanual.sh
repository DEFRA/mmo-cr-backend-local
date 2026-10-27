#!/bin/bash
#
# CRmanual.sh - Manual curl helper for the Catch Recording Service, based on
# docs/running-locally-with-docker-compose.md (mmo-cr-catch-recording-service).
#
# Usage:
#   scripts/CRmanual.sh <Action>
#
# Actions:
#   Health        Health probe
#   WebCreate     Create the first persistent DRAFT Catch Record for a vessel
#   MobCreate     Same as WebCreate, plus an explicit catchRecordReference
#                 (GBR-{RSS}-{DDMMYY}-{HHMMSS})
#   GetCR         Retrieve one Catch Record
#   GetBasics     List/Get/History curl commands that read catch records
#   SaveTrip      PATCH trip — a complete section object
#   SavePairing   PATCH pairFishing — enabled
#   SaveGears     PATCH gears — an array
#   SaveNoLanded  PATCH speciesNotLanded
#   SaveWeb       Runs WebCreate, SaveTrip, SavePairing, SaveGears, SaveNoLanded in sequence
#   SaveMob       Complete mobile replacement (PUT)
#   Submit        Lifecycle transitions and submission artifacts, up to retrieving
#                 an immutable artifact body (json/pdf) as an attachment download
#   SaveFab       Vessel favourites and skippers — add favourites
#   DelFab        Vessel favourites and skippers — delete favourites
#
# Environment variables (defaults shown) may be overridden before running:
#   TOKEN, VESSEL_ID, VERSION, PORT_ID, CR_URL, GEAR_ID, CHARACTERISTIC_ID,
#   STATISTICAL_AREA_ID, SPECIES_ID, RSS, CATCH_RECORD_ID

set -euo pipefail

# ---- State persistence -------------------------------------------------------
# Each invocation of this script is a separate process, so a plain `export`
# only lives for that single run. To let CATCH_RECORD_ID/VERSION persist
# across separate commands (e.g. `CRmanual.sh WebCreate` followed later by
# `CRmanual.sh GetCR`), they are also written to and reloaded from a small
# state file sitting next to this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.CRmanual.state"

if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE"
fi

# Persists the given VAR=value env assignment to disk (replacing any existing
# entry for that var) and exports it in the current process.
save_state() {
  local var="$1" value="$2"
  export "${var}=${value}"
  touch "$STATE_FILE"
  grep -v "^export ${var}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
  echo "export ${var}=\"${value}\"" >> "$STATE_FILE"
}

# ---- Defaults --------------------------------------------------------------
: "${TOKEN:=Bearer write-token}"
: "${VESSEL_ID:=00000000-0000-4000-8000-000000000012}"
: "${VERSION:=1}"
: "${PORT_ID:=4e9d942b-ca2e-4983-a38d-6fdfc960ef88}"
: "${CR_URL:=http://localhost:3003}"
: "${GEAR_ID:=F3C85F59-1196-43DA-B74B-909F7D7BE451}"
: "${CHARACTERISTIC_ID:=ec4b5815-3b60-5463-934e-012280b5494a}"
: "${STATISTICAL_AREA_ID:=50640}"
: "${SPECIES_ID:=F7C56C89-DC86-490E-82AB-637BB1B40F0C}"
: "${RSS:=BM45}"
: "${CATCH_RECORD_ID:=}"

usage() {
  sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

if [ "$#" -ne 1 ]; then
  usage
fi

ACTION="$1"

# ---- Individual actions -----------------------------------------------------

# Pretty-print a JSON response body via jq; falls back gracefully when the
# body is empty (e.g. 204 No Content from DELETE endpoints).
print_json() {
  local body
  body="$(cat)"
  if [ -z "$body" ]; then
    echo "(no content)"
  else
    echo "$body" | jq . 2>/dev/null || echo "$body"
  fi
}

# Extracts "version" from a PATCH/PUT JSON response and persists it, so the
# next chained save in this script (or a later invocation) uses the
# up-to-date If-Match value instead of a stale one.
update_version_from() {
  local response="$1" new_version
  new_version=$(echo "$response" | jq -r '.version // empty' 2>/dev/null || true)
  if [ -n "${new_version:-}" ]; then
    save_state VERSION "$new_version"
    echo ">>> VERSION updated to $VERSION"
  fi
}

do_Health() {
  echo "# Health probe"
  curl -s "$CR_URL/health" | print_json
}

do_WebCreate() {
  echo "# Create the first persistent DRAFT Catch Record for a vessel."
  local response
  response=$(curl -s -X POST "$CR_URL/v1/catch-records" \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: $(uuidgen)" \
    -d "{\"vesselId\": \"$VESSEL_ID\"}")

  echo "$response" | print_json

  local new_id new_version
  new_id=$(echo "$response" | jq -r '.id // empty')
  new_version=$(echo "$response" | jq -r '.version // empty')

  if [ -n "${new_id:-}" ]; then
    save_state CATCH_RECORD_ID "$new_id"
    echo ">>> CATCH_RECORD_ID updated to $CATCH_RECORD_ID"
  fi
  if [ -n "${new_version:-}" ]; then
    save_state VERSION "$new_version"
    echo ">>> VERSION updated to $VERSION"
  fi
}

do_MobCreate() {
  echo "# Create the first persistent DRAFT Catch Record for a vessel, with an"
  echo "# explicit catchRecordReference (GBR-{RSS}-{DDMMYY}-{HHMMSS})."
  local catch_record_reference
  catch_record_reference="GBR-${RSS}-$(date +%d%m%y)-$(date +%H%M%S)"

  local response
  response=$(curl -s -X POST "$CR_URL/v1/catch-records" \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: $(uuidgen)" \
    -d "{\"vesselId\": \"$VESSEL_ID\", \"catchRecordReference\": \"$catch_record_reference\"}")

  echo "$response" | print_json

  local new_id new_version
  new_id=$(echo "$response" | jq -r '.id // empty')
  new_version=$(echo "$response" | jq -r '.version // empty')

  if [ -n "${new_id:-}" ]; then
    save_state CATCH_RECORD_ID "$new_id"
    echo ">>> CATCH_RECORD_ID updated to $CATCH_RECORD_ID"
  fi
  if [ -n "${new_version:-}" ]; then
    save_state VERSION "$new_version"
    echo ">>> VERSION updated to $VERSION"
  fi
}

do_GetCR() {
  echo "# Retrieve one Catch Record"
  curl -s "$CR_URL/v1/catch-records/$CATCH_RECORD_ID" \
    -H "Authorization: $TOKEN" | print_json
}

do_GetBasics() {
  echo "# List your own Catch Records"
  curl -s "$CR_URL/v1/catch-records?limit=20" \
    -H "Authorization: $TOKEN" | print_json

  echo
  echo "# Retrieve one Catch Record"
  curl -s "$CR_URL/v1/catch-records/$CATCH_RECORD_ID" \
    -H "Authorization: $TOKEN" | print_json

  echo
  echo "# Combined lifecycle/audit history"
  curl -s "$CR_URL/v1/catch-records/$CATCH_RECORD_ID/history?limit=20" \
    -H "Authorization: $TOKEN" | print_json
}

do_SaveTrip() {
  echo "# trip — a complete section object"
  local response
  response=$(curl -s -X PATCH "$CR_URL/v1/catch-records/$CATCH_RECORD_ID" \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -H "If-Match: $VERSION" \
    -d "{
      \"section\": \"trip\",
      \"data\": {
        \"startedAndFinishedToday\": true,
        \"departurePort\": { \"id\": \"$PORT_ID\" },
        \"returnPort\": { \"id\": \"$PORT_ID\" }
      }
    }")
  echo "$response" | print_json
  update_version_from "$response"
}

do_SavePairing() {
  echo "# pairFishing — enabled"
  local response
  response=$(curl -s -X PATCH "$CR_URL/v1/catch-records/$CATCH_RECORD_ID" \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -H "If-Match: $VERSION" \
    -d '{
      "section": "pairFishing",
      "data": { "enabled": false, "pairVessel": null, "pairSkipperName": null }
    }')
  echo "$response" | print_json
  update_version_from "$response"
}

do_SaveGears() {
  echo "# gears — an array"
  local response
  response=$(curl -s -X PATCH "$CR_URL/v1/catch-records/$CATCH_RECORD_ID" \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -H "If-Match: $VERSION" \
    -d "{
      \"section\": \"gears\",
      \"data\": [
        {
          \"gear\": { \"id\": \"$GEAR_ID\" },
          \"statisticalArea\": { \"id\": \"$STATISTICAL_AREA_ID\" },
          \"characteristics\": [
            { \"characteristicId\": \"$CHARACTERISTIC_ID\", \"value\": 9 }
          ],
          \"speciesCaught\": [
            {
              \"id\": \"$SPECIES_ID\",
              \"weightAboveMinimumKg\": 120.5,
              \"weightBelowMinimumKg\": 4,
              \"weightLegallyDiscardedKg\": null,
              \"weightPrecision\": \"oneDecimalPlace\"
            }
          ]
        }
      ]
    }")
  echo "$response" | print_json
  update_version_from "$response"
}

do_SaveNoLanded() {
  echo "# speciesNotLanded — a root-level, trip-wide array"
  local response
  response=$(curl -s -X PATCH "$CR_URL/v1/catch-records/$CATCH_RECORD_ID" \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -H "If-Match: $VERSION" \
    -d "{
      \"section\": \"speciesNotLanded\",
      \"data\": [
        {
          \"id\": \"$SPECIES_ID\",
          \"weightAboveMinimumKg\": null,
          \"weightBelowMinimumKg\": 2.5,
          \"weightLegallyDiscardedKg\": null,
          \"weightPrecision\": \"oneDecimalPlace\"
        }
      ]
    }")
  echo "$response" | print_json
  update_version_from "$response"
}

do_SaveWeb() {
  do_WebCreate
  echo
  do_SaveTrip
  echo
  do_SavePairing
  echo
  do_SaveGears
  echo
  do_SaveNoLanded
}

do_SaveMob() {
  echo "# Complete mobile replacement (PUT)"
  local response
  response=$(curl -s -X PUT "$CR_URL/v1/catch-records/$CATCH_RECORD_ID" \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -H "If-Match: $VERSION" \
    -d "{
      \"vessel\": { \"id\": \"$VESSEL_ID\" },
      \"trip\": {
        \"startedAndFinishedToday\": true,
        \"departurePort\": { \"id\": \"$PORT_ID\" },
        \"returnPort\": { \"id\": \"$PORT_ID\" }
      },
      \"pairFishing\": { \"enabled\": false, \"pairVessel\": null, \"pairSkipperName\": null },
      \"gears\": [
        {
          \"gear\": { \"id\": \"$GEAR_ID\" },
          \"statisticalArea\": { \"id\": \"$STATISTICAL_AREA_ID\" },
          \"characteristics\": [
            { \"characteristicId\": \"$CHARACTERISTIC_ID\", \"value\": 9 }
          ],
          \"speciesCaught\": []
        }
      ],
      \"speciesNotLanded\": []
    }")
  echo "$response" | print_json
  update_version_from "$response"
}

do_Submit() {
  echo "# Submit — generates the immutable JSON snapshot and PDF receipt"
  curl -s -X POST "$CR_URL/v1/catch-records/$CATCH_RECORD_ID/submission" \
    -H "Authorization: $TOKEN" \
    -H "If-Match: $VERSION" \
    -H "Idempotency-Key: $(uuidgen)" | print_json

  echo
  echo "# List every submission version's artifact metadata (no artifact body)"
  curl -s "$CR_URL/v1/catch-records/$CATCH_RECORD_ID/submissions" \
    -H "Authorization: $TOKEN" | print_json

  echo
  echo "# Retrieve one immutable artifact body (json) as an attachment download"
  curl -s "$CR_URL/v1/catch-records/$CATCH_RECORD_ID/submissions/1/json" \
    -H "Authorization: $TOKEN" \
    -o snapshot.json

  echo
  echo "# Retrieve one immutable artifact body (pdf) as an attachment download"
  curl -s "$CR_URL/v1/catch-records/$CATCH_RECORD_ID/submissions/1/pdf" \
    -H "Authorization: $TOKEN" \
    -o receipt.pdf
}

do_SaveFab() {
  echo "# Add a favourite gear"
  curl -s -X POST "$CR_URL/v1/vessels/$VESSEL_ID/favourite-gears" \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"gearId\": \"$GEAR_ID\"}" | print_json

  echo
  echo "# Add a favourite species"
  curl -s -X POST "$CR_URL/v1/vessels/$VESSEL_ID/favourite-species" \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"speciesId\": \"$SPECIES_ID\"}" | print_json

  echo
  echo "# Add a favourite port"
  curl -s -X POST "$CR_URL/v1/vessels/$VESSEL_ID/favourite-ports" \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"portId\": \"$PORT_ID\"}" | print_json
}

do_DelFab() {
  echo "# Remove the favourite gear"
  curl -s -X DELETE "$CR_URL/v1/vessels/$VESSEL_ID/favourite-gears/$GEAR_ID" \
    -H "Authorization: $TOKEN" | print_json

  echo
  echo "# Remove the favourite species"
  curl -s -X DELETE "$CR_URL/v1/vessels/$VESSEL_ID/favourite-species/$SPECIES_ID" \
    -H "Authorization: $TOKEN" | print_json

  echo
  echo "# Remove the favourite port"
  curl -s -X DELETE "$CR_URL/v1/vessels/$VESSEL_ID/favourite-ports/$PORT_ID" \
    -H "Authorization: $TOKEN" | print_json
}

# ---- Dispatch ---------------------------------------------------------------

case "$ACTION" in
  Health)       do_Health ;;
  WebCreate)    do_WebCreate ;;
  MobCreate)    do_MobCreate ;;
  GetCR)        do_GetCR ;;
  GetBasics)    do_GetBasics ;;
  SaveTrip)     do_SaveTrip ;;
  SavePairing)  do_SavePairing ;;
  SaveGears)    do_SaveGears ;;
  SaveNoLanded) do_SaveNoLanded ;;
  SaveWeb)      do_SaveWeb ;;
  SaveMob)      do_SaveMob ;;
  Submit)       do_Submit ;;
  SaveFab)      do_SaveFab ;;
  DelFab)       do_DelFab ;;
  *)
    echo "Error: unknown parameter '$ACTION'" >&2
    usage
    ;;
esac
