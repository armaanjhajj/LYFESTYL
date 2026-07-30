# Verification

Offline checks for the parts of LYFESTYL where a wrong answer would look plausible.

Everything here runs on a Mac against the app's real source files. Nothing in this
directory ships in the app, and nothing in the app depends on it.

```sh
./Verification/setup.sh   # once: installs numpy/scipy and Garmin's SDK, fetches fixtures
./Verification/run.sh     # every suite
```

## Why these exist

Three areas of this codebase fail silently rather than loudly:

1. **Statistics.** A p-value that is wrong by an order of magnitude still renders as a
   number. Reference-checking against SciPy is the only way to know the maths is right.
2. **The FIT decoder.** FIT numbers its fields differently per message. `lap.avgHeartRate`
   is field 15 while `session.avgHeartRate` is field 16, so a plausible guess reads
   maximum heart rate as average with no error anywhere. Scales are worse: reading
   altitude without its divisor of 5 and offset of 500 produces an altitude that is
   wrong and looks fine.
3. **SF Symbol names.** A misspelled symbol renders as nothing at all, with no warning.
4. **API response parsing.** A wrong key in a `Decodable` struct does not throw. The property
   is simply nil and the app carries on with missing data.

Each check caught at least one real bug when it was written.

## Statistics

74 checks against SciPy/NumPy, to within 1e-10 for the distribution functions: mean,
variance, median, scaled median absolute deviation, percentiles, fractional ranks with
ties, the normal CDF and its inverse, two-tailed Student t at fractional degrees of
freedom, the regularized incomplete beta, Pearson and Spearman correlation, the
autocorrelation function, ordinary least squares, Theil-Sen (slope and joint intercept),
Mann-Kendall with tie and continuity corrections, the exponentially weighted moving
average, smallest worthwhile change, and gap interpolation.

**What it caught:** the autocorrelation correction was being applied to the time index
when regressing a metric against time. Since `0, 1, 2, ...` is almost perfectly
autocorrelated by construction, a clearly trending series was reported as p = 0.999.
Serial dependence is a property of the residuals, not of the predictor.

## FIT decoder

`fitdiff.mjs` decodes each file with both our decoder and Garmin's official JavaScript
SDK, then compares message group counts, per-field value counts and exact per-field
value sums. 688 comparisons across eight files: five official Garmin fixtures (one with
developer fields) plus three generated to cover strength `set` messages, sleep stages,
Body Battery, stress, HRV status, SpO2, respiration and a GPS-and-power activity.

`checkfields.mjs` parses `FITMessages.swift` and asserts that every field number it reads
exists on that message in Garmin's published profile, and that every scale and offset
written in the Swift matches the profile exactly. 181 checks.

**What they caught:** three off-by-N field errors (`lap` average and maximum heart rate
were reading maximum heart rate and cadence; `user_profile` gender, age, height and weight
were all shifted by two; `weight_scale` bone and muscle mass were reading hydration and
visceral fat), and one invalid-value bug where `0xFF` bytes inside an opaque byte array
were being dropped as "no value" when they were real data in a UUID.

One deliberate difference remains and is excluded from the comparison: profile-driven
component expansion of packed bit-fields, such as `hr.event_timestamp_12`, is not
implemented. Nothing the app reads depends on it.

## Analysis pipeline

63 assertions over the whole chain, run against a generated 180-day history that
deliberately contains signals the analysis must recover: heart-rate variability
responding to the PREVIOUS night's sleep, a bench press held flat against a
climbing squat, and a resting-heart-rate step two thirds of the way in. If the
correlation search does not find the sleep relationship at a one-day lag, its lag
alignment is broken. If the trend test cannot tell the flat lift from the climbing
one, it is not doing any work.

It also checks invariants that catch scaling errors: no session load above 400
points (one hour at threshold is 100 by definition), intensity factors inside
0.2 to 2.0, and neither fitness nor fatigue exceeding the largest single day, since
both are exponentially weighted averages of daily load and cannot. Plus spot checks
against published values: Epley and Brzycki at 10 reps, Riegel's exponent, Minetti
at zero gradient, the 42-day decay constant, and VDOT for a 20:00 5k.

**What it caught:** grade-adjusted pace was resampling a cumulative distance series
onto a grid finer than its own samples, which credited a full sample interval's
distance to one grid step and multiplied the implied speed by the ratio of the two
spacings. An ordinary trail run scored an intensity factor of 3.19 and a training
load of 1712 instead of about 143, and the fatigue curve peaked at 295. Every
individual formula was correct, which is exactly why an end-to-end check was needed.
It also caught a hamstring-to-quadriceps balance ratio that resolved both sides
through the body-system roll-up, and since both live in LEGS returned the same
number twice and reported 1.00 as "balanced" regardless of the data.

## Hevy parser against live data

```sh
export HEVY_API_KEY=...        # from hevy.com, Settings, Developer
./Verification/Hevy/fetch.sh   # writes to Verification/Hevy/samples (gitignored)
./Verification/run.sh
```

20 checks that decode REAL Hevy responses through the app's own DTOs and mapper, then assert
the fields we depend on actually arrived: both date formats parse, supersets decode, every
exercise type and muscle group maps, muscle attribution clears 85 percent, volume load and
estimated one-rep max land in plausible ranges, and warm-ups are excluded from working sets.

**What it caught:** Hevy's published OpenAPI document is stale, and three of its claims are
wrong against the live API. The read path returns `superset_id`, not `supersets_id`. Exercise
templates return `equipment`, not `equipment_category`. The exercise-type enum is missing
`bodyweight_weighted`, `bodyweight_assisted`, `floors_duration` and `steps_duration`. All
three decoded silently to nil or `.unknown`, so the app would have shown no supersets, no
equipment, and mis-typed exercises with nothing in any log to explain why.

The samples directory holds one person's training history and is gitignored.

## SF Symbols

Validates every SF Symbol name in the app against the system CoreGlyphs database
(9,184 names) and reports the highest iOS version any of them requires.
