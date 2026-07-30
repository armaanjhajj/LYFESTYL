#!/usr/bin/env bash
# Run every verification suite. Expects ./setup.sh to have been run once.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
status=0

echo "=== SF Symbols ==="
python3 Verification/check_symbols.py || status=1

echo
echo "=== Statistics against SciPy ==="
swiftc -O -o /tmp/lyfe-stats \
  LYFESTYLE/Services/Analytics/Statistics.swift \
  Verification/Statistics/harness/main.swift || status=1
( cd Verification/Statistics && /tmp/lyfe-stats > swift_out.txt \
  && ./venv/bin/python verify.py ) || status=1

echo
echo "=== FIT decoder against Garmin's SDK ==="
swiftc -O -o /tmp/lyfe-fitdump \
  LYFESTYLE/Services/Integrations/FIT/FITDecoder.swift \
  Verification/FIT/dump/main.swift || status=1
cp /tmp/lyfe-fitdump Verification/FIT/fitdump
( cd Verification/FIT && node fitdiff.mjs fitdata/*.fit && node checkfields.mjs ) || status=1

echo
echo "=== Analysis pipeline ==="
swiftc -DDEBUG -O -o /tmp/lyfe-pipe \
  LYFESTYLE/Models/Unified/*.swift LYFESTYLE/Services/Analytics/*.swift \
  LYFESTYLE/Models/HealthInsight.swift \
  LYFESTYLE/Models/Exercise.swift LYFESTYLE/Models/ExerciseLibrary.swift \
  LYFESTYLE/Models/Workout.swift LYFESTYLE/Models/JournalEntry.swift \
  LYFESTYLE/DesignSystem/SolarizedPalette.swift LYFESTYLE/DesignSystem/Formatting.swift \
  LYFESTYLE/DesignSystem/InsightCategory.swift \
  LYFESTYLE/Services/WorkoutMerge.swift LYFESTYLE/Models/TimelineItem.swift \
  Verification/Pipeline/SampleHistory.swift Verification/Pipeline/main.swift || status=1
/tmp/lyfe-pipe || status=1

echo
echo "=== Hevy parser against live data ==="
if [ -f Verification/Hevy/samples/workouts.json ]; then
  swiftc -O -o /tmp/lyfe-hevy \
    LYFESTYLE/Models/Unified/*.swift LYFESTYLE/Services/Analytics/*.swift \
    LYFESTYLE/Models/HealthInsight.swift LYFESTYLE/Models/Exercise.swift \
    LYFESTYLE/Models/ExerciseLibrary.swift LYFESTYLE/Models/Workout.swift \
    LYFESTYLE/Models/JournalEntry.swift LYFESTYLE/DesignSystem/SolarizedPalette.swift \
    LYFESTYLE/DesignSystem/Formatting.swift LYFESTYLE/DesignSystem/InsightCategory.swift \
    LYFESTYLE/Services/Integrations/HevyAPI.swift \
    LYFESTYLE/Services/Integrations/HevyMapper.swift \
    Verification/Hevy/main.swift || status=1
  /tmp/lyfe-hevy Verification/Hevy/samples || status=1
else
  echo "  skipped: no samples. Run HEVY_API_KEY=... ./Verification/Hevy/fetch.sh"
fi

echo
[ $status -eq 0 ] && echo "ALL SUITES PASSED" || echo "SOME SUITES FAILED"
exit $status
