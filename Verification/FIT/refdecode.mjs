import { Decoder, Stream } from '@garmin/fitsdk';
import { readFileSync, writeFileSync } from 'fs';
const file = process.argv[2];
const bytes = readFileSync(file);
const stream = Stream.fromBuffer(bytes);
console.log('isFIT:', Decoder.isFIT(stream));
const decoder = new Decoder(stream);
console.log('checkIntegrity:', decoder.checkIntegrity());
// Decode with NO conversions so raw field numbers/values are comparable.
const { messages, errors } = decoder.read({
  applyScaleAndOffset: false,
  expandSubFields: false,
  expandComponents: false,
  convertTypesToStrings: false,
  convertDateTimesToDates: false,
  includeUnknownFields: true,
  mergeHeartRates: false,
});
if (errors.length) console.log('errors:', errors.slice(0,3));
const summary = {};
for (const [k, v] of Object.entries(messages)) summary[k] = Array.isArray(v) ? v.length : 1;
console.log('groups:', JSON.stringify(summary));
writeFileSync(file + '.ref.json', JSON.stringify(messages, null, 1));
// Print a compact fingerprint we can compare against Swift.
const out = {};
const sess = messages.sessionMesgs?.[0];
if (sess) out.session = {
  sport: sess.sport, subSport: sess.subSport, startTime: sess.startTime,
  totalTimerTime: sess.totalTimerTime, totalElapsedTime: sess.totalElapsedTime,
  totalDistance: sess.totalDistance, totalCalories: sess.totalCalories,
  avgHeartRate: sess.avgHeartRate, maxHeartRate: sess.maxHeartRate,
  avgSpeed: sess.avgSpeed, maxSpeed: sess.maxSpeed, avgCadence: sess.avgCadence,
  avgPower: sess.avgPower, maxPower: sess.maxPower, normalizedPower: sess.normalizedPower,
  totalAscent: sess.totalAscent, totalDescent: sess.totalDescent,
  enhancedAvgSpeed: sess.enhancedAvgSpeed, enhancedAvgAltitude: sess.enhancedAvgAltitude,
  timeInHrZone: sess.timeInHrZone, trainingStressScore: sess.trainingStressScore,
  intensityFactor: sess.intensityFactor, workoutRpe: sess.workoutRpe,
};
const recs = messages.recordMesgs || [];
out.recordCount = recs.length;
if (recs.length) {
  const pick = i => { const r = recs[i]; return r && {
    timestamp: r.timestamp, positionLat: r.positionLat, positionLong: r.positionLong,
    heartRate: r.heartRate, cadence: r.cadence, distance: r.distance, speed: r.speed,
    enhancedSpeed: r.enhancedSpeed, altitude: r.altitude, enhancedAltitude: r.enhancedAltitude,
    power: r.power, temperature: r.temperature }; };
  out.firstRecord = pick(0);
  out.midRecord = pick(Math.floor(recs.length/2));
  out.lastRecord = pick(recs.length-1);
  const hrs = recs.map(r=>r.heartRate).filter(v=>typeof v==='number');
  out.hrStats = { n: hrs.length, min: Math.min(...hrs), max: Math.max(...hrs),
                  sum: hrs.reduce((a,b)=>a+b,0) };
  const ds = recs.map(r=>r.distance).filter(v=>typeof v==='number');
  out.distMax = ds.length ? Math.max(...ds) : null;
  const lats = recs.map(r=>r.positionLat).filter(v=>typeof v==='number');
  out.latCount = lats.length;
  out.latSum = lats.reduce((a,b)=>a+b,0);
}
out.fileId = messages.fileIdMesgs?.[0];
console.log(JSON.stringify(out, null, 1));
