// Generate FIT files with Garmin's own encoder covering exactly the message types the
// app depends on for Garmin data: strength sets, sleep stages, Body Battery, stress,
// HRV status, SpO2, respiration, VO2max, and a rich activity with GPS + power.
//
// Round-tripping these through our own decoder proves the paths we actually use.
import { Encoder, Profile } from '@garmin/fitsdk';
import { writeFileSync } from 'fs';

const FIT_EPOCH = 631065600;
const t0 = 1030732282; // a FIT timestamp from the real fixtures

function write(name, mesgs) {
  const enc = new Encoder();
  for (const [num, fields] of mesgs) enc.onMesg(num, fields);
  const bytes = enc.close();
  writeFileSync(`fitdata/${name}`, Buffer.from(bytes));
  console.log(name, bytes.length, 'bytes,', mesgs.length, 'messages');
}

// ---- 1. Strength training file with `set` messages (mesg 225).
{
  const m = [];
  m.push([0, { type: 4, manufacturer: 1, product: 4024, timeCreated: t0, serialNumber: 12345 }]);
  let t = t0;
  // Alternating active/rest sets, mirroring how a Garmin watch records lifting.
  const plan = [
    { reps: 10, weightKg: 60.0, cat: 11 },   // bench-ish
    { reps: 8,  weightKg: 82.5, cat: 11 },
    { reps: 5,  weightKg: 100.0, cat: 11 },
    { reps: 12, weightKg: 40.25, cat: 22 },
    { reps: 15, weightKg: 0, cat: 22 },      // bodyweight: zero load
  ];
  for (const [i, p] of plan.entries()) {
    m.push([225, {
      timestamp: t + 120, startTime: t, duration: 45.0,
      repetitions: p.reps, weight: p.weightKg, setType: 1,
      category: [p.cat], weightDisplayUnit: 2, messageIndex: i * 2,
    }]);
    t += 45;
    m.push([225, { timestamp: t + 90, startTime: t, duration: 90.0, setType: 0, messageIndex: i * 2 + 1 }]);
    t += 90;
  }
  m.push([18, {
    timestamp: t, startTime: t0, sport: 10, subSport: 20,
    totalElapsedTime: t - t0, totalTimerTime: t - t0, totalCalories: 210,
    avgHeartRate: 118, maxHeartRate: 152, workoutRpe: 70, workoutFeel: 75,
    numLaps: 1, event: 8, eventType: 1,
  }]);
  m.push([34, { timestamp: t, totalTimerTime: t - t0, numSessions: 1, type: 0, event: 26, eventType: 1 }]);
  write('SynthStrength.fit', m);
}

// ---- 2. Wellness/monitoring file: sleep stages, Body Battery, stress, HRV, SpO2,
//         respiration, VO2max.
{
  const m = [];
  m.push([0, { type: 32, manufacturer: 1, product: 4024, timeCreated: t0, serialNumber: 12345 }]);
  let t = t0;
  // Sleep stages: unmeasurable(0) awake(1) light(2) deep(3) rem(4)
  const stages = [1, 2, 3, 2, 4, 2, 3, 2, 4, 1];
  for (const s of stages) {
    m.push([275, { timestamp: t, sleepLevel: s }]);
    t += 1800;
  }
  m.push([346, { timestamp: t, combinedAwakeScore: 72, awakeTimeScore: 80, sleepDurationScore: 68 }]);
  // Body Battery: an array of per-interval levels.
  m.push([314, { timestamp: t0, processingInterval: 120, level: [42, 45, 51, 58, 66, 71, 79, 84] }]);
  // Stress levels, one message per reading.
  for (let i = 0; i < 6; i++) {
    m.push([227, { stressLevelvalue: 20 + i * 7, stressLevelTime: t0 + i * 900 }]);
  }
  m.push([306, { timestamp: t0, processingInterval: 180, stressLevel: [18, 22, 31, 44, 27, 19] }]);
  // HRV status summary (RMSSD in ms) and individual values.
  m.push([370, {
    timestamp: t0, weeklyAverage: 58.5, lastNightAverage: 62.0,
    lastNight5MinHigh: 78.5, baselineLowUpper: 45.0,
    baselineBalancedLower: 52.0, baselineBalancedUpper: 70.0, status: 4,
  }]);
  for (let i = 0; i < 8; i++) m.push([371, { timestamp: t0 + i * 300, value: 50 + i * 2.5 }]);
  // SpO2 and respiration.
  for (let i = 0; i < 5; i++) m.push([269, { timestamp: t0 + i * 600, readingSpo2: 95 + (i % 3), readingConfidence: 2 }]);
  for (let i = 0; i < 5; i++) m.push([297, { timestamp: t0 + i * 600, respirationRate: 13.5 + i * 0.25 }]);
  // VO2max.
  m.push([229, { updateTime: t0, vo2Max: 52.7, sport: 1, subSport: 0 }]);
  write('SynthWellness.fit', m);
}

// ---- 3. Rich activity: GPS, HR, power, cadence, altitude, running dynamics.
{
  const m = [];
  m.push([0, { type: 4, manufacturer: 1, product: 4024, timeCreated: t0, serialNumber: 999 }]);
  m.push([21, { timestamp: t0, event: 0, eventType: 0 }]);
  const n = 600;
  let dist = 0;
  const baseLat = 40.7128, baseLon = -74.0060;
  const SEMI = 2 ** 31 / 180;
  for (let i = 0; i < n; i++) {
    const speed = 3.2 + Math.sin(i / 60) * 0.4;       // m/s
    dist += speed;
    m.push([20, {
      timestamp: t0 + i,
      positionLat: Math.round((baseLat + i * 0.00002) * SEMI),
      positionLong: Math.round((baseLon + i * 0.00003) * SEMI),
      distance: dist,
      enhancedSpeed: speed,
      enhancedAltitude: 30 + Math.sin(i / 120) * 25,
      heartRate: Math.round(140 + Math.sin(i / 90) * 12),
      cadence: Math.round(84 + Math.sin(i / 45) * 3),
      power: Math.round(260 + Math.sin(i / 30) * 40),
      temperature: 22,
      verticalOscillation: 8.4,
      stanceTime: 240.5,
      stepLength: 1180.0,
      enhancedRespirationRate: 32.5,
    }]);
  }
  m.push([21, { timestamp: t0 + n, event: 0, eventType: 4 }]);
  m.push([19, {
    timestamp: t0 + n, startTime: t0, sport: 1, subSport: 3,
    totalElapsedTime: n, totalTimerTime: n, totalDistance: dist,
    avgHeartRate: 141, maxHeartRate: 155, avgSpeed: 3.2, maxSpeed: 3.7,
    avgPower: 261, maxPower: 302, totalAscent: 48, totalDescent: 44, messageIndex: 0,
  }]);
  m.push([18, {
    timestamp: t0 + n, startTime: t0, sport: 1, subSport: 3,
    totalElapsedTime: n, totalTimerTime: n, totalDistance: dist,
    totalCalories: 420, avgHeartRate: 141, maxHeartRate: 155, minHeartRate: 118,
    avgSpeed: 3.2, maxSpeed: 3.7, enhancedAvgSpeed: 3.2, enhancedMaxSpeed: 3.7,
    avgCadence: 84, maxCadence: 88, avgPower: 261, maxPower: 302,
    normalizedPower: 268, trainingStressScore: 62.5, intensityFactor: 0.812,
    thresholdPower: 300, totalAscent: 48, totalDescent: 44,
    enhancedAvgAltitude: 32.5, enhancedMaxAltitude: 55.0, enhancedMinAltitude: 8.0,
    avgTemperature: 22, maxTemperature: 24, totalTrainingEffect: 3.4,
    totalAnaerobicTrainingEffect: 1.2, avgVerticalOscillation: 8.4,
    avgStanceTime: 240.5, avgStepLength: 1180.0, avgRespirationRate: 32,
    rmssdHrv: 41, sdrrHrv: 55, workoutRpe: 65,
    timeInHrZone: [12.0, 180.0, 240.0, 150.0, 18.0],
    numLaps: 1, event: 8, eventType: 1,
  }]);
  m.push([216, {
    timestamp: t0 + n, referenceMesg: 18, referenceIndex: 0,
    timeInHrZone: [12.0, 180.0, 240.0, 150.0, 18.0],
    hrZoneHighBoundary: [110, 130, 150, 170, 190],
    maxHeartRate: 190, restingHeartRate: 52, thresholdHeartRate: 168,
    functionalThresholdPower: 300,
  }]);
  m.push([78, { time: [0.812, 0.798, 0.821, 0.805] }]);
  m.push([34, { timestamp: t0 + n, totalTimerTime: n, numSessions: 1, type: 0, event: 26, eventType: 1 }]);
  write('SynthRun.fit', m);
}
