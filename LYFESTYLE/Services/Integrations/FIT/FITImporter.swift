//
//  FITImporter.swift
//  LYFESTYL
//
//  Turns a decoded FIT file into the app's canonical types. This is the bridge that gives
//  Garmin sessions the same analysis depth an Apple Watch session gets.
//
//  Three kinds of file are handled, distinguished by the `file_id` message:
//
//    ACTIVITY  -> a `UnifiedWorkout`, with the full sample series (heart rate, speed,
//                 power, cadence, altitude, cumulative distance) plus the GPS track and,
//                 for strength activities, the per-set breakdown from `set` messages.
//    WELLNESS  -> `DailySnapshot`s carrying sleep stages, HRV (RMSSD), Body Battery,
//                 stress, SpO2, respiration and VO2 max. Several of these never reach
//                 Apple Health at all.
//    WEIGHT    -> body-composition readings folded into the matching day.
//
//  A single import can also seed the athlete profile: FIT files carry the device's own
//  configured max, resting and threshold heart rate and FTP (in `time_in_zone` and
//  `user_profile`), which are real settings rather than a population estimate.
//
//  Everything is computed from the file's own samples, so the numbers are the athlete's
//  actual session, not a reconstruction.
//

import Foundation

// MARK: - Result

/// What one FIT file yielded.
nonisolated struct FITImportResult: Sendable {
    var workouts: [UnifiedWorkout] = []
    /// Partial daily wellness, keyed by day. Merged into existing snapshots by the caller.
    var snapshots: [DailySnapshot] = []
    /// Anchors the file revealed about the athlete, from the device's own configuration.
    var observedMaxHeartRate: Double?
    var observedRestingHeartRate: Double?
    var observedThresholdHeartRate: Double?
    var observedFTP: Double?
    var observedBodyMassKg: Double?
    var observedSex: AthleteSex?
    /// True when the file decoded but produced nothing the app understands.
    var wasEmpty: Bool { workouts.isEmpty && snapshots.isEmpty }
    /// Set when the file's trailing checksum did not verify. The data is still imported,
    /// because a readable file with a bad CRC is usually a truncated transfer rather than
    /// corrupt content, but the UI mentions it.
    var checksumFailed: Bool = false
    var wasTruncated: Bool = false

    mutating func merge(_ other: FITImportResult) {
        workouts.append(contentsOf: other.workouts)
        snapshots.append(contentsOf: other.snapshots)
        observedMaxHeartRate = [observedMaxHeartRate, other.observedMaxHeartRate].compactMap { $0 }.max()
        observedRestingHeartRate = other.observedRestingHeartRate ?? observedRestingHeartRate
        observedThresholdHeartRate = other.observedThresholdHeartRate ?? observedThresholdHeartRate
        observedFTP = [observedFTP, other.observedFTP].compactMap { $0 }.max()
        observedBodyMassKg = other.observedBodyMassKg ?? observedBodyMassKg
        observedSex = other.observedSex ?? observedSex
        checksumFailed = checksumFailed || other.checksumFailed
        wasTruncated = wasTruncated || other.wasTruncated
    }
}

// MARK: - Importer

nonisolated enum FITImporter {

    /// Decode and interpret one FIT file's bytes.
    static func `import`(data: Data, filename: String? = nil, calendar: Calendar = .current) throws -> FITImportResult {
        let file = try FITDecoder.decode(data)
        var result = interpret(file, filename: filename, calendar: calendar)
        result.checksumFailed = !file.crcValid
        result.wasTruncated = file.wasTruncated
        return result
    }

    /// Interpret an already-decoded file.
    static func interpret(_ file: FITFile, filename: String? = nil, calendar: Calendar = .current) -> FITImportResult {
        var result = FITImportResult()

        // Anchors from the device's own configuration, which beat any estimate.
        for message in file.all(FITMesg.timeInZone) {
            let zone = FITTimeInZone(message)
            if let value = zone.maxHeartRate, ProfileSnapshot.plausibleMaxHeartRate.contains(value) {
                result.observedMaxHeartRate = max(result.observedMaxHeartRate ?? 0, value)
            }
            if let value = zone.restingHeartRate, ProfileSnapshot.plausibleRestingHeartRate.contains(value) {
                result.observedRestingHeartRate = value
            }
            if let value = zone.thresholdHeartRate, value > 80, value < 220 {
                result.observedThresholdHeartRate = value
            }
            if let value = zone.functionalThresholdPower, value > 40, value < 700 {
                result.observedFTP = max(result.observedFTP ?? 0, value)
            }
        }
        if let message = file.first(FITMesg.userProfile) {
            let profile = FITUserProfile(message)
            if let value = profile.defaultMaxHeartRate ?? profile.defaultMaxRunningHeartRate,
               ProfileSnapshot.plausibleMaxHeartRate.contains(value) {
                result.observedMaxHeartRate = max(result.observedMaxHeartRate ?? 0, value)
            }
            if let value = profile.restingHeartRate, ProfileSnapshot.plausibleRestingHeartRate.contains(value) {
                result.observedRestingHeartRate = value
            }
            if let value = profile.weightKg, value > 25, value < 350 {
                result.observedBodyMassKg = value
            }
            result.observedSex = profile.athleteSex
        }
        // A session's own threshold power is another real anchor.
        for message in file.all(FITMesg.session) {
            if let value = FITSession(message).thresholdPowerWatts, value > 40, value < 700 {
                result.observedFTP = max(result.observedFTP ?? 0, value)
            }
        }

        // Activity files carry sessions; a session becomes a workout.
        let sessions = file.all(FITMesg.session)
        if !sessions.isEmpty {
            let records = file.all(FITMesg.record).map(FITRecord.init)
            let sets = file.all(FITMesg.set).map(FITSet.init)
            let fileID = file.first(FITMesg.fileID).map(FITFileID.init)
            let serial = fileID?.serialNumber

            for (index, message) in sessions.enumerated() {
                let session = FITSession(message)
                if let workout = buildWorkout(
                    session: session,
                    sessionIndex: index,
                    sessionCount: sessions.count,
                    records: records,
                    sets: sets,
                    serialNumber: serial,
                    filename: filename,
                    calendar: calendar
                ) {
                    result.workouts.append(workout)
                }
            }
        }

        // Wellness content, which can sit in the same file as an activity or its own.
        let wellness = buildSnapshots(file, calendar: calendar)
        result.snapshots = wellness

        return result
    }

    // MARK: - Activity

    private static func buildWorkout(
        session: FITSession,
        sessionIndex: Int,
        sessionCount: Int,
        records: [FITRecord],
        sets: [FITSet],
        serialNumber: Double?,
        filename: String?,
        calendar: Calendar
    ) -> UnifiedWorkout? {
        guard let start = session.startTime else { return nil }
        let movingSeconds = session.effectiveMovingSeconds ?? 0
        let elapsedSeconds = session.totalElapsedSeconds ?? movingSeconds
        guard elapsedSeconds > 10 || movingSeconds > 10 else { return nil }
        let end = session.timestamp ?? start.addingTimeInterval(elapsedSeconds)

        let sport = FITSportMapper.sport(fitSport: session.sport, fitSubSport: session.subSport)

        // Keep only the records inside this session's window. A multisport file holds one
        // continuous record stream covering every leg, so slicing by time is what keeps a
        // triathlon's swim, bike and run from all inheriting the whole file's samples.
        let windowStart = start.addingTimeInterval(-1)
        let windowEnd = end.addingTimeInterval(1)
        let ownRecords = sessionCount == 1
            ? records
            : records.filter { record in
                guard let t = record.timestamp else { return false }
                return t >= windowStart && t <= windowEnd
            }

        let series = buildSeries(records: ownRecords, start: start)

        // Strength sessions: the per-set breakdown from `set` messages.
        var strength: StrengthSession?
        if sport.family == .strength {
            let ownSets = sets.filter { set in
                guard let t = set.startTime ?? set.timestamp else { return false }
                return t >= windowStart && t <= windowEnd
            }
            strength = buildStrength(sets: ownSets.isEmpty ? sets : ownSets)
        }

        // A stable identity. The device serial plus the start instant is unique and, more
        // importantly, DETERMINISTIC, so re-importing the same file updates the existing
        // workout instead of duplicating it.
        let identity: String
        if let serialNumber {
            identity = "\(Int(serialNumber))-\(Int(start.timeIntervalSince1970))-\(sessionIndex)"
        } else {
            identity = "\(Int(start.timeIntervalSince1970))-\(Int(elapsedSeconds))-\(sessionIndex)"
        }
        let origin = SourceRef(source: .garmin, foreignID: identity, updatedAt: session.timestamp)

        // Normalized power: prefer the device's own figure, else compute it from the
        // power series with Coggan's algorithm.
        let normalizedPower = session.normalizedPowerWatts
            ?? series.power.flatMap { TrainingLoad.normalizedPower($0) }

        let decoupling = TrainingLoad.aerobicDecoupling(
            heartRateSeries: series.heartRate,
            powerSeries: series.power,
            speedSeries: series.speed
        )

        var workout = UnifiedWorkout(
            id: origin.uniqueKey,
            origin: origin,
            sport: sport,
            title: title(for: sport, start: start, filename: filename),
            notes: nil,
            start: start,
            end: end,
            movingSeconds: movingSeconds > 0 ? movingSeconds : elapsedSeconds,
            isIndoor: FITSportMapper.isIndoor(fitSubSport: session.subSport) ?? sport.isIndoorByNature,
            distanceMeters: positive(session.totalDistanceMeters),
            activeEnergyKcal: positive(session.totalCalories),
            elevationGainMeters: positive(session.totalAscentMeters),
            elevationLossMeters: positive(session.totalDescentMeters),
            averageHeartRate: plausibleHeartRate(session.averageHeartRate),
            maxHeartRate: plausibleHeartRate(session.maxHeartRate),
            averageSpeedMps: positive(session.averageSpeedMps),
            maxSpeedMps: positive(session.maxSpeedMps),
            averagePowerWatts: positive(session.averagePowerWatts),
            maxPowerWatts: positive(session.maxPowerWatts),
            averageCadence: positive(session.averageCadence),
            averageStrideLengthMeters: session.averageStepLengthMm.map { $0 / 1000 },
            averageGroundContactMs: positive(session.averageStanceTimeMs),
            averageVerticalOscillationCm: session.averageVerticalOscillationMm.map { $0 / 10 },
            perceivedEffort: session.perceivedEffortOutOfTen,
            normalizedPowerWatts: positive(normalizedPower),
            decouplingPercent: decoupling,
            heartRateSeries: series.heartRate,
            speedSeries: series.speed,
            powerSeries: series.power,
            cadenceSeries: series.cadence,
            altitudeSeries: series.altitude,
            distanceSeries: series.distance,
            route: series.route,
            strength: strength,
            calendar: calendar
        )

        // Running cadence in FIT is one-leg revolutions per minute; runners think in total
        // steps per minute, so double it. Cycling rpm is already what a cyclist expects.
        if sport.discipline == .running, let cadence = workout.averageCadence, cadence > 0, cadence < 130 {
            workout.averageCadence = cadence * 2
        }

        return workout
    }

    /// Build the sample series, downsampled for storage.
    private static func buildSeries(
        records: [FITRecord],
        start: Date
    ) -> (heartRate: MetricSeries?, speed: MetricSeries?, power: MetricSeries?,
          cadence: MetricSeries?, altitude: MetricSeries?, distance: MetricSeries?,
          route: RouteSummary?) {

        var hrO: [Double] = [], hrV: [Double] = []
        var spO: [Double] = [], spV: [Double] = []
        var pwO: [Double] = [], pwV: [Double] = []
        var cdO: [Double] = [], cdV: [Double] = []
        var alO: [Double] = [], alV: [Double] = []
        var diO: [Double] = [], diV: [Double] = []
        var lats: [Double] = [], lons: [Double] = []

        for record in records {
            guard let timestamp = record.timestamp else { continue }
            let offset = timestamp.timeIntervalSince(start)
            // Records before the session start belong to a previous leg.
            guard offset >= 0 else { continue }

            if let value = plausibleHeartRate(record.heartRate) { hrO.append(offset); hrV.append(value) }
            // A speed of exactly zero is a real reading (stopped), so it is kept: the
            // rolling maths for normalized power depends on the zeros being there.
            if let value = record.speedMps, value >= 0, value < 40 { spO.append(offset); spV.append(value) }
            if let value = record.powerWatts, value >= 0, value < 3000 { pwO.append(offset); pwV.append(value) }
            if let value = record.cadence, value >= 0, value < 300 { cdO.append(offset); cdV.append(value) }
            if let value = record.altitudeMeters, value > -500, value < 9000 { alO.append(offset); alV.append(value) }
            if let value = record.distanceMeters, value >= 0 { diO.append(offset); diV.append(value) }
            if let lat = record.latitude, let lon = record.longitude {
                lats.append(lat)
                lons.append(lon)
            }
        }

        func series(_ offsets: [Double], _ values: [Double]) -> MetricSeries? {
            guard values.count >= 3 else { return nil }
            return Downsampler.reduce(MetricSeries(offsets: offsets, values: values))
        }

        return (
            heartRate: series(hrO, hrV),
            speed: series(spO, spV),
            power: series(pwO, pwV),
            cadence: series(cdO, cdV),
            altitude: series(alO, alV),
            distance: series(diO, diV),
            route: Downsampler.reduceRoute(latitudes: lats, longitudes: lons)
        )
    }

    /// Build a strength session from FIT `set` messages.
    ///
    /// A Garmin watch records rest periods as their own set, and does NOT group sets into
    /// exercises: it emits a flat stream with an exercise `category`. So sets are grouped
    /// into exercises by consecutive runs of the same category, which is how they were
    /// actually performed.
    private static func buildStrength(sets: [FITSet]) -> StrengthSession? {
        let active = sets.filter(\.isActive)
        guard !active.isEmpty else { return nil }

        var exercises: [StrengthExercise] = []
        var currentCategory: Double?
        var currentSets: [StrengthSet] = []
        var exerciseIndex = 0

        func flush() {
            guard !currentSets.isEmpty else { return }
            let name = FITExerciseCategory.name(for: currentCategory)
            let matched = ExerciseLibrary.shared.match(name: name)
            exercises.append(StrengthExercise(
                index: exerciseIndex,
                name: matched?.name ?? name,
                templateID: currentCategory.map { "garmin-cat-\(Int($0))" },
                libraryExerciseID: matched?.id,
                measurement: .weightReps,
                primaryTargets: (matched?.primary ?? []).map { MuscleTarget.muscle($0) },
                secondaryTargets: (matched?.secondary ?? []).map { MuscleTarget.muscle($0) },
                equipment: matched?.equipment ?? .other,
                sets: currentSets
            ))
            exerciseIndex += 1
            currentSets = []
        }

        for set in active {
            let category = set.categories?.first
            if category != currentCategory, !currentSets.isEmpty {
                flush()
            }
            currentCategory = category
            currentSets.append(StrengthSet(
                index: currentSets.count,
                type: .normal,
                weightKg: (set.weightKg ?? 0) > 0 ? set.weightKg : nil,
                reps: (set.repetitions ?? 0) > 0 ? set.repetitions : nil,
                durationSeconds: set.durationSeconds
            ))
        }
        flush()

        return exercises.isEmpty ? nil : StrengthSession(exercises: exercises)
    }

    // MARK: - Wellness

    /// Assemble daily wellness from a monitoring or sleep file.
    private static func buildSnapshots(_ file: FITFile, calendar: Calendar) -> [DailySnapshot] {
        /// Accumulators per day.
        struct Accumulator {
            var hrvValues: [Double] = []
            var hrvOvernightAverage: Double?
            var bodyBattery: [Double] = []
            var stress: [Double] = []
            var spo2: [Double] = []
            var respiration: [Double] = []
            var vo2Max: Double?
            var bodyMassKg: Double?
            var bodyFatPercent: Double?
            var leanBodyMassKg: Double?
        }
        var byDay: [Date: Accumulator] = [:]

        func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

        // Sleep, reconstructed from stage-transition messages.
        let stageMessages = file.all(FITMesg.sleepLevel).map(FITSleepLevel.init)
        let nights = buildSleepNights(from: stageMessages, calendar: calendar)

        // HRV status: Garmin's overnight RMSSD average, which is exactly the figure the
        // recovery analysis wants and which never reaches Apple Health.
        for message in file.all(FITMesg.hrvStatusSummary) {
            let summary = FITHRVStatusSummary(message)
            guard let timestamp = summary.timestamp else { continue }
            var accumulator = byDay[day(timestamp)] ?? Accumulator()
            if let value = summary.lastNightAverageMs, value > 1, value < 400 {
                accumulator.hrvOvernightAverage = value
            }
            byDay[day(timestamp)] = accumulator
        }
        for message in file.all(FITMesg.hrvValue) {
            let value = FITHRVValue(message)
            guard let timestamp = value.timestamp, let ms = value.valueMs, ms > 1, ms < 400 else { continue }
            byDay[day(timestamp), default: Accumulator()].hrvValues.append(ms)
        }

        // Body Battery and stress arrive as interval arrays.
        for message in file.all(FITMesg.hsaBodyBatteryData) {
            for sample in FITBodyBattery(message).samples() {
                byDay[day(sample.date), default: Accumulator()].bodyBattery.append(sample.level)
            }
        }
        for message in file.all(FITMesg.hsaStressData) {
            for sample in FITStressData(message).samples() {
                byDay[day(sample.date), default: Accumulator()].stress.append(sample.level)
            }
        }
        for message in file.all(FITMesg.stressLevel) {
            let reading = FITStressLevel(message)
            guard reading.isValid, let value = reading.value, let time = reading.time else { continue }
            byDay[day(time), default: Accumulator()].stress.append(value)
        }

        for message in file.all(FITMesg.spo2Data) {
            let reading = FITSpo2(message)
            guard let timestamp = reading.timestamp, let percent = reading.percent,
                  percent > 50, percent <= 100 else { continue }
            byDay[day(timestamp), default: Accumulator()].spo2.append(percent)
        }
        for message in file.all(FITMesg.respirationRate) {
            let reading = FITRespirationRate(message)
            guard reading.isValid, let timestamp = reading.timestamp,
                  let rate = reading.breathsPerMinute, rate > 3, rate < 60 else { continue }
            byDay[day(timestamp), default: Accumulator()].respiration.append(rate)
        }
        for message in file.all(FITMesg.maxMetData) {
            let reading = FITMaxMetData(message)
            guard let timestamp = reading.updateTime, let value = reading.vo2Max,
                  value > 10, value < 100 else { continue }
            byDay[day(timestamp), default: Accumulator()].vo2Max = value
        }
        for message in file.all(FITMesg.weightScale) {
            let reading = FITWeightScale(message)
            guard let timestamp = reading.timestamp else { continue }
            var accumulator = byDay[day(timestamp)] ?? Accumulator()
            if let value = reading.weightKg, value > 25, value < 350 { accumulator.bodyMassKg = value }
            if let value = reading.percentFat, value > 2, value < 70 { accumulator.bodyFatPercent = value }
            if let value = reading.muscleMassKg, value > 10, value < 200 { accumulator.leanBodyMassKg = value }
            byDay[day(timestamp)] = accumulator
        }

        // Fold the nights in so a night with no other wellness still produces a snapshot.
        var days = Set(byDay.keys)
        for night in nights { days.insert(night.date) }

        return days.sorted().compactMap { date -> DailySnapshot? in
            let accumulator = byDay[date] ?? Accumulator()
            let night = nights.first { $0.date == date }

            // Garmin reports HRV as RMSSD. Apple Health stores SDNN. They measure related
            // but DIFFERENT things and there is no valid conversion between them, so the
            // RMSSD value is kept in its own field and never mixed into the SDNN history.
            let hrv = accumulator.hrvOvernightAverage ?? Stats.median(accumulator.hrvValues)

            let snapshot = DailySnapshot(
                date: date,
                sleep: night,
                respiratoryRate: Stats.median(accumulator.respiration),
                oxygenSaturationPercent: Stats.median(accumulator.spo2),
                vo2Max: accumulator.vo2Max,
                bodyMassKg: accumulator.bodyMassKg,
                bodyFatPercent: accumulator.bodyFatPercent,
                leanBodyMassKg: accumulator.leanBodyMassKg,
                bodyBattery: accumulator.bodyBattery.last,
                stressAverage: Stats.mean(accumulator.stress),
                garminHrvRmssdMs: hrv,
                contributingSources: [.garmin]
            )
            return snapshot.isEmpty ? nil : snapshot
        }
    }

    /// Reconstruct nights from stage-transition messages.
    ///
    /// Each `sleep_level` message marks the instant a stage BEGAN, so a stage's duration is
    /// the gap to the next message. That means the last stage in a run has no end and is
    /// dropped rather than guessed at.
    private static func buildSleepNights(
        from stages: [FITSleepLevel],
        calendar: Calendar
    ) -> [SleepNight] {
        let ordered = stages
            .compactMap { stage -> (date: Date, stage: SleepStage)? in
                guard let date = stage.timestamp, let mapped = stage.sleepStage else { return nil }
                return (date, mapped)
            }
            .sorted { $0.date < $1.date }
        guard ordered.count >= 2 else { return [] }

        var intervals: [SleepAssembler.Interval] = []
        for (index, entry) in ordered.enumerated() where index + 1 < ordered.count {
            let next = ordered[index + 1]
            let duration = next.date.timeIntervalSince(entry.date)
            // A gap over four hours is not a sleep stage, it is the end of the record.
            guard duration > 0, duration < 4 * 3600 else { continue }
            guard entry.stage != .unspecified else { continue }
            intervals.append(SleepAssembler.Interval(
                start: entry.date,
                end: next.date,
                stage: entry.stage,
                source: .garmin
            ))
        }
        guard !intervals.isEmpty else { return [] }
        return SleepAssembler.assembleNights(intervals: intervals, calendar: calendar)
    }

    // MARK: - Helpers

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    /// Reject heart rates outside a physiological range. A dropped chest strap writes
    /// zeros and occasional wild spikes, and letting those through would corrupt the
    /// averages, the zone distribution and the observed maximum.
    private static func plausibleHeartRate(_ value: Double?) -> Double? {
        guard let value, value >= 25, value <= 240 else { return nil }
        return value
    }

    private static func title(for sport: WorkoutSport, start: Date, filename: String?) -> String {
        let hour = Calendar.current.component(.hour, from: start)
        let partOfDay: String
        switch hour {
        case 0..<5:   partOfDay = "Night"
        case 5..<12:  partOfDay = "Morning"
        case 12..<17: partOfDay = "Afternoon"
        case 17..<21: partOfDay = "Evening"
        default:      partOfDay = "Night"
        }
        return "\(partOfDay) \(sport.label)"
    }
}

// MARK: - Exercise categories

/// Names for the FIT `exercise_category` values a Garmin watch records during a strength
/// session. Only the families the watch actually uses are listed; anything else becomes a
/// neutral label rather than a wrong guess.
nonisolated enum FITExerciseCategory {
    static func name(for raw: Double?) -> String {
        guard let raw else { return "Exercise" }
        switch Int(raw) {
        case 0:  return "Bench Press"
        case 1:  return "Calf Raise"
        case 2:  return "Cardio"
        case 3:  return "Carry"
        case 4:  return "Chop"
        case 5:  return "Core"
        case 6:  return "Crunch"
        case 7:  return "Curl"
        case 8:  return "Deadlift"
        case 9:  return "Flye"
        case 10: return "Hip Raise"
        case 11: return "Hip Stability"
        case 12: return "Hip Swing"
        case 13: return "Hyperextension"
        case 14: return "Lateral Raise"
        case 15: return "Leg Curl"
        case 16: return "Leg Raise"
        case 17: return "Lunge"
        case 18: return "Olympic Lift"
        case 19: return "Plank"
        case 20: return "Plyo"
        case 21: return "Pull Up"
        case 22: return "Push Up"
        case 23: return "Row"
        case 24: return "Shoulder Press"
        case 25: return "Shoulder Stability"
        case 26: return "Shrug"
        case 27: return "Sit Up"
        case 28: return "Squat"
        case 29: return "Total Body"
        case 30: return "Triceps Extension"
        case 31: return "Warm Up"
        case 32: return "Run"
        case 65534: return "Exercise"
        default: return "Exercise"
        }
    }
}
