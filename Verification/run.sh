#!/bin/sh
# Compile the app's pure-logic sources with the checks in main.swift and run them.
# Usage: Verification/run.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/lyfestyl-verify"
APP="$ROOT/LYFESTYLE"
xcrun swiftc -swift-version 6 -default-isolation MainActor -O \
  "$APP/DesignSystem/SolarizedPalette.swift" \
  "$APP/DesignSystem/Macro.swift" \
  "$APP/DesignSystem/Formatting.swift" \
  "$APP/Models/Nutrition.swift" \
  "$APP/Models/Goals.swift" \
  "$APP/Models/MealEntry.swift" \
  "$APP/Models/CommonFoods.swift" \
  "$APP/Models/LabelFacts.swift" \
  "$APP/Services/HabitEngine.swift" \
  "$APP/Services/MealExport.swift" \
  "$ROOT/Verification/main.swift" \
  -o "$OUT"
"$OUT"
