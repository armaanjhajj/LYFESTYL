#!/usr/bin/env bash
# Fetch the reference data and dependencies the verification harnesses need.
# Nothing here is committed: the FIT fixtures and profile come from Garmin, and the
# Python and Node dependencies are ordinary package installs.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Statistics: numpy and scipy"
python3 -m venv Statistics/venv
./Statistics/venv/bin/pip install --quiet --upgrade pip numpy scipy

echo "==> FIT: Garmin reference SDK"
cd FIT
[ -f package.json ] || npm init -y >/dev/null 2>&1
npm install --silent @garmin/fitsdk

echo "==> FIT: Garmin Global Profile"
curl -sL -o fit_profile.mjs \
  "https://raw.githubusercontent.com/garmin/fit-javascript-sdk/main/src/profile.js"

echo "==> FIT: official Garmin test fixtures"
mkdir -p fitdata
base_js="https://raw.githubusercontent.com/garmin/fit-javascript-sdk/main/test/data"
base_py="https://raw.githubusercontent.com/garmin/fit-python-sdk/main/tests/fits"
base_sw="https://raw.githubusercontent.com/garmin/fit-swift-sdk/main/Tests/FITSwiftSDKTests/TestData"
for f in Activity.fit HrmPluginTestActivity.fit WithGearChangeData.fit; do
  curl -sL -o "fitdata/$f" "$base_js/$f"
done
curl -sL -o fitdata/ActivityDevFields.fit "$base_py/ActivityDevFields.fit"
curl -sL -o fitdata/HrMesgTestActivity.fit "$base_sw/HrMesgTestActivity.fit"

echo "==> FIT: generating coverage files with Garmin's encoder"
node synth.mjs

echo
echo "Setup complete. Run ./Verification/run.sh"
