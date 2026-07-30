// Validate every FIT field number used in FITMessages.swift against Garmin's published
// Global Profile: that the field exists on that message, and that the scale and offset
// written in the Swift match the profile exactly.
//
// This is the guard against the off-by-N field bug: FIT numbers fields differently per
// message (lap.avgHeartRate is 15 while session.avgHeartRate is 16), so a plausible
// guess reads the wrong metric with no error anywhere.
import P from './fit_profile.mjs';
import { readFileSync } from 'fs';

import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
const here = dirname(fileURLToPath(import.meta.url));
const SWIFT_SRC = join(here, '..', '..', 'LYFESTYLE', 'Services', 'Integrations', 'FIT', 'FITMessages.swift');
const swift = readFileSync(SWIFT_SRC, 'utf8');

// Which Swift struct maps to which global message number.
const STRUCT_TO_MESG = {
  FITFileID: 0, FITUserProfile: 3, FITSession: 18, FITLap: 19, FITRecord: 20,
  FITSet: 225, FITSleepLevel: 275, FITHRVStatusSummary: 370, FITHRVValue: 371,
  FITBodyBattery: 314, FITStressData: 306, FITStressLevel: 227, FITSpo2: 269,
  FITRespirationRate: 297, FITMaxMetData: 229, FITTimeInZone: 216, FITWeightScale: 30,
};

// Split the file into per-struct bodies.
const bodies = {};
for (const name of Object.keys(STRUCT_TO_MESG)) {
  const re = new RegExp(`struct ${name} \\{([\\s\\S]*?)\\n\\}`, 'm');
  const m = swift.match(re);
  if (!m) { console.log(`  ! struct ${name} not found`); continue; }
  bodies[name] = m[1];
}

let checks = 0, fails = 0;

// Accessor call forms we emit.
const CALLS = [
  // m.scaled(F, scale: S) / m.scaled(F, scale: S, offset: O)
  /m\.scaled\((\d+),\s*scale:\s*([\d.]+)(?:,\s*offset:\s*([\d.]+))?\)/g,
  // m.scaledArray(F, scale: S)
  /m\.scaledArray\((\d+),\s*scale:\s*([\d.]+)\)/g,
];
const PLAIN = [
  /m\.raw\((\d+)\)/g,
  /m\.date\((\d+)\)/g,
  /m\.enumValue\((\d+)\)/g,
  /m\.degrees\((\d+)\)/g,
  /m\.string\((\d+)\)/g,
  /m\[(\d+)\]/g,
];

function profileField(mesgNum, fieldNum) {
  const msg = P.messages[mesgNum];
  if (!msg) return null;
  return msg.fields[fieldNum] ?? null;
}
function norm(v, dflt) {
  if (Array.isArray(v)) v = v.length ? v[0] : dflt;
  return v === undefined || v === null ? dflt : Number(v);
}

for (const [name, body] of Object.entries(bodies)) {
  const mesgNum = STRUCT_TO_MESG[name];
  const msgName = P.messages[mesgNum]?.name ?? '?';

  // Scaled accessors: field must exist AND the scale/offset must match the profile.
  for (const re of CALLS) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(body))) {
      const fieldNum = Number(m[1]);
      const swiftScale = Number(m[2]);
      const swiftOffset = m[3] === undefined ? 0 : Number(m[3]);
      checks++;
      const f = profileField(mesgNum, fieldNum);
      if (!f) {
        console.log(`  MISSING ${name}(${msgName}).${fieldNum}: no such field in profile`);
        fails++; continue;
      }
      const pScale = norm(f.scale, 1);
      const pOffset = norm(f.offset, 0);
      if (Math.abs(pScale - swiftScale) > 1e-9) {
        console.log(`  SCALE ${name}(${msgName}).${fieldNum} ${f.name}: swift=${swiftScale} profile=${pScale}`);
        fails++;
      }
      if (Math.abs(pOffset - swiftOffset) > 1e-9) {
        console.log(`  OFFSET ${name}(${msgName}).${fieldNum} ${f.name}: swift=${swiftOffset} profile=${pOffset}`);
        fails++;
      }
    }
  }

  // preferEnhanced(E, legacy: L, scale: S[, offset: O]) - both fields, one scale.
  const pe = /m\.preferEnhanced\((\d+),\s*legacy:\s*(\d+),\s*scale:\s*([\d.]+)(?:,\s*offset:\s*([\d.]+))?\)/g;
  let m;
  while ((m = pe.exec(body))) {
    const swiftScale = Number(m[3]);
    const swiftOffset = m[4] === undefined ? 0 : Number(m[4]);
    for (const fieldNum of [Number(m[1]), Number(m[2])]) {
      checks++;
      const f = profileField(mesgNum, fieldNum);
      if (!f) {
        console.log(`  MISSING ${name}(${msgName}).${fieldNum} (preferEnhanced)`);
        fails++; continue;
      }
      const pScale = norm(f.scale, 1), pOffset = norm(f.offset, 0);
      if (Math.abs(pScale - swiftScale) > 1e-9) {
        console.log(`  SCALE ${name}(${msgName}).${fieldNum} ${f.name}: swift=${swiftScale} profile=${pScale}`);
        fails++;
      }
      if (Math.abs(pOffset - swiftOffset) > 1e-9) {
        console.log(`  OFFSET ${name}(${msgName}).${fieldNum} ${f.name}: swift=${swiftOffset} profile=${pOffset}`);
        fails++;
      }
    }
  }

  // Unscaled accessors: the field must exist, and must have scale 1 / offset 0 in the
  // profile, otherwise we are reading a raw value that needed conversion.
  for (const re of PLAIN) {
    re.lastIndex = 0;
    let mm;
    while ((mm = re.exec(body))) {
      const fieldNum = Number(mm[1]);
      checks++;
      const f = profileField(mesgNum, fieldNum);
      if (!f) {
        console.log(`  MISSING ${name}(${msgName}).${fieldNum}: no such field in profile`);
        fails++; continue;
      }
      const pScale = norm(f.scale, 1), pOffset = norm(f.offset, 0);
      // m[N] returns the raw array and callers scale separately, so skip those.
      if (re.source.startsWith('m\\[')) continue;
      if (Math.abs(pScale - 1) > 1e-9 || Math.abs(pOffset) > 1e-9) {
        console.log(`  UNSCALED ${name}(${msgName}).${fieldNum} ${f.name} read raw but profile has scale=${pScale} offset=${pOffset}`);
        fails++;
      }
    }
  }
}

// Cross-check the global message numbers declared in FITMesg.
const decoderMesg = readFileSync(SWIFT_SRC, 'utf8');
const mesgRe = /static let (\w+): UInt16 = (\d+)/g;
let mm2;
while ((mm2 = mesgRe.exec(decoderMesg))) {
  const [, name, num] = mm2;
  checks++;
  const profName = P.messages[Number(num)]?.name;
  if (!profName) { console.log(`  BAD MESG ${name} = ${num}: not in profile`); fails++; continue; }
  // Compare case-insensitively ignoring separators.
  const a = name.toLowerCase().replace(/[^a-z0-9]/g, '');
  const b = profName.toLowerCase().replace(/[^a-z0-9]/g, '');
  if (a !== b) { console.log(`  MESG NAME ${name} = ${num} but profile calls it ${profName}`); fails++; }
}

console.log(`\n${checks} field/scale checks`);
if (fails) { console.log(`${fails} FAILURES`); process.exit(1); }
console.log('ALL FIT FIELD NUMBERS AND SCALES MATCH THE GARMIN PROFILE');
