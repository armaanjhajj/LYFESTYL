#!/usr/bin/env bash
# Fetch real Hevy responses to check the parser against.
#
# The key is read from the environment and never written to disk. The samples it produces
# ARE one person's training history, so Verification/Hevy/samples is gitignored.
#
#   export HEVY_API_KEY=...
#   ./Verification/Hevy/fetch.sh
set -euo pipefail
cd "$(dirname "$0")"
: "${HEVY_API_KEY:?set HEVY_API_KEY first}"
mkdir -p samples

echo "==> workouts"
curl -sf -H "api-key: $HEVY_API_KEY" \
  "https://api.hevyapp.com/v1/workouts?page=1&pageSize=10" > samples/workouts.json

echo "==> exercise templates"
# Page size caps at 100 here; one page is plenty to validate the shape.
curl -sf -H "api-key: $HEVY_API_KEY" \
  "https://api.hevyapp.com/v1/exercise_templates?page=1&pageSize=100" > samples/templates.json

echo "==> body measurements"
curl -sf -H "api-key: $HEVY_API_KEY" \
  "https://api.hevyapp.com/v1/body_measurements?page=1&pageSize=10" > samples/measurements.json

echo "Done. Samples in $(pwd)/samples (gitignored)."
