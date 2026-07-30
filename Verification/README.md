# Verification

Offline checks for the parts of LYFESTYL where a wrong answer would look plausible.

Everything here runs on a Mac against the app's real source files. Nothing in this
directory ships in the app, and nothing in the app depends on it.

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

Each check caught at least one real bug when it was written.

## Statistics

```sh
cd Verification/Statistics
python3 -m venv venv && ./venv/bin/pip install numpy scipy
swiftc -O -o harness ../../LYFESTYLE/Services/Analytics/Statistics.swift harness.swift
./harness > swift_out.txt
./venv/bin/python verify.py
```

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

```sh
cd Verification/FIT
npm install @garmin/fitsdk
node synth.mjs                    # generate coverage files with Garmin's own encoder
swiftc -O -o fitdump ../../LYFESTYLE/Services/Integrations/FIT/FITDecoder.swift dump/main.swift
node fitdiff.mjs fitdata/*.fit    # differential against Garmin's reference decoder
node checkfields.mjs              # field numbers and scales against the Global Profile
```

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

## SF Symbols

```sh
python3 Verification/check_symbols.py
```

Validates every SF Symbol name in the app against the system CoreGlyphs database
(9,184 names) and reports the highest iOS version any of them requires.
