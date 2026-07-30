//
//  WorkoutMerge.swift
//  LYFESTYL
//
//  How the same real-world session, seen by more than one source, becomes one record.
//
//  This happens constantly. A lifting session recorded on a Garmin watch reaches Apple Health
//  AND, if the user also logged it, Hevy. A run appears both as an Apple Health workout and as
//  an imported .fit file. Counting either twice would double the week's volume and every load
//  figure derived from it.
//
//  Two distinct mechanisms live here, and they answer different questions:
//
//    SESSION MATCHING is pure TIME MATCHING, because that is all there is to go on: two
//    sources share no identifier. Two sessions are the same when they start within fifteen
//    minutes of each other, overlap by at least half the shorter one, and belong to the same
//    broad sport family. The family check is what stops a lift and a run that happen to start
//    together from collapsing into one.
//
//    DAILY MERGING is FIELD BY FIELD, because different sources fill different fields on the
//    same day: Apple Health has steps and SDNN, Garmin has Body Battery and RMSSD, Hevy has
//    body weight. Replacing the day wholesale would discard whichever arrived first.
//
//  Kept free of HealthKit, the keychain and CloudKit on purpose, so the policy is pure value
//  transformation and can be asserted on directly.
//

import Foundation

nonisolated enum WorkoutMerge {

    /// Combine two versions of one day, preferring whichever actually has a value.
    ///
    /// Where both have one, the newer wins for measured values, EXCEPT for sleep, where the
    /// staged version wins because a staged night carries strictly more information than an
    /// unstaged one covering the same hours.
    static func mergeSnapshot(_ a: DailySnapshot, _ b: DailySnapshot) -> DailySnapshot {
        var result = a

        func take(_ keyPath: WritableKeyPath<DailySnapshot, Double?>) {
            if let value = b[keyPath: keyPath] { result[keyPath: keyPath] = value }
        }
        take(\.restingHeartRate)
        take(\.heartRateVariabilityMs)
        take(\.respiratoryRate)
        take(\.oxygenSaturationPercent)
        take(\.wristTemperatureDeltaC)
        take(\.walkingHeartRateAverage)
        take(\.heartRateRecoveryOneMinute)
        take(\.breathingDisturbances)
        take(\.steps)
        take(\.activeEnergyKcal)
        take(\.basalEnergyKcal)
        take(\.exerciseMinutes)
        take(\.standHours)
        take(\.flightsClimbed)
        take(\.distanceWalkingRunningMeters)
        take(\.timeInDaylightMinutes)
        take(\.vo2Max)
        take(\.bodyMassKg)
        take(\.bodyFatPercent)
        take(\.leanBodyMassKg)
        take(\.mindfulMinutes)
        take(\.bodyBattery)
        take(\.stressAverage)
        take(\.trainingReadiness)
        take(\.garminHrvRmssdMs)

        // Sleep: prefer a staged night, then the longer one.
        switch (a.sleep, b.sleep) {
        case (nil, let new?):
            result.sleep = new
        case (let old?, let new?):
            if new.isStaged && !old.isStaged {
                result.sleep = new
            } else if new.isStaged == old.isStaged, new.asleepSeconds > old.asleepSeconds {
                result.sleep = new
            }
        default:
            break
        }

        result.contributingSources = Array(Set(a.contributingSources + b.contributingSources))
            .sorted { $0.fieldPriority > $1.fieldPriority }
        return result
    }

    /// Collapse sessions that describe the same real-world workout.
    ///
    /// Two sessions are the same when they overlap substantially in time and are the same broad
    /// family. That happens routinely: a Garmin strength session syncs to Apple Health while the
    /// user also logs it in Hevy, and counting both would double the week's volume and load.
    ///
    /// The winner is chosen by which source is authoritative FOR THAT KIND of session, not by a
    /// global ranking: Hevy owns sets and reps, a FIT import owns anything with a sample series.
    static func collapseDuplicates(_ workouts: [UnifiedWorkout]) -> [UnifiedWorkout] {
        let sorted = workouts.sorted { $0.start < $1.start }
        var result: [UnifiedWorkout] = []

        for workout in sorted {
            // Look back only at recent entries: sessions are sorted, so an overlap can only be
            // with something close by.
            if let index = result.lastIndex(where: { existing in
                overlaps(existing, workout) && existing.family == workout.family
            }) {
                result[index] = preferred(result[index], workout)
            } else {
                result.append(workout)
            }
        }
        return result
    }

    /// Whether two sessions describe the same workout: they start within fifteen minutes of
    /// each other, and overlap by at least half the shorter and a third of the longer.
    static func overlaps(_ a: UnifiedWorkout, _ b: UnifiedWorkout) -> Bool {
        guard abs(a.start.timeIntervalSince(b.start)) < 900 else { return false }
        let overlapStart = max(a.start, b.start)
        let overlapEnd = min(a.end, b.end)
        let overlap = overlapEnd.timeIntervalSince(overlapStart)
        guard overlap > 0 else { return false }
        let shorter = min(a.elapsedSeconds, b.elapsedSeconds)
        let longer = max(a.elapsedSeconds, b.elapsedSeconds)
        guard shorter > 0, longer > 0 else { return false }
        // Half the shorter AND a third of the longer. Testing showed the first alone is not
        // enough: an eight minute session sitting entirely inside a ninety minute one scores
        // a perfect 1.0 against the shorter, so a brief contained record would always collapse
        // into the long one. The looser bound on the longer accommodates the real case where
        // two sources disagree on duration, since Hevy times from opening to closing the app
        // including rests while a watch records only active time.
        return overlap / shorter >= 0.5 && overlap / longer >= 0.33
    }

    /// Pick the richer of two descriptions of the same session, keeping the other's provenance.
    static func preferred(_ a: UnifiedWorkout, _ b: UnifiedWorkout) -> UnifiedWorkout {
        func score(_ workout: UnifiedWorkout) -> Int {
            var points = 0
            // For lifting, the set-by-set record is what matters and only Hevy or a FIT file
            // has it.
            if workout.strength != nil { points += 100 }
            // A sample series unlocks every within-session analysis.
            if workout.heartRateSeries != nil { points += 60 }
            if workout.powerSeries != nil { points += 30 }
            if workout.route != nil { points += 20 }
            if workout.distanceMeters != nil { points += 10 }
            if workout.averageHeartRate != nil { points += 5 }
            points += workout.origin.source.fieldPriority
            return points
        }

        var winner = score(a) >= score(b) ? a : b
        let loser = score(a) >= score(b) ? b : a

        // Keep the loser's provenance so the UI can say both sources saw this.
        var merged = winner.mergedSources
        if !merged.contains(loser.origin), loser.origin.source != winner.origin.source {
            merged.append(loser.origin)
        }
        winner.mergedSources = merged

        // Fill any gap the winner has from the loser, so nothing measured is thrown away.
        if winner.distanceMeters == nil { winner.distanceMeters = loser.distanceMeters }
        if winner.activeEnergyKcal == nil { winner.activeEnergyKcal = loser.activeEnergyKcal }
        if winner.averageHeartRate == nil { winner.averageHeartRate = loser.averageHeartRate }
        if winner.maxHeartRate == nil { winner.maxHeartRate = loser.maxHeartRate }
        if winner.strength == nil { winner.strength = loser.strength }
        if winner.perceivedEffort == nil { winner.perceivedEffort = loser.perceivedEffort }
        if winner.notes == nil { winner.notes = loser.notes }
        if winner.elevationGainMeters == nil { winner.elevationGainMeters = loser.elevationGainMeters }
        if winner.averagePowerWatts == nil { winner.averagePowerWatts = loser.averagePowerWatts }
        if winner.averageCadence == nil { winner.averageCadence = loser.averageCadence }

        // The SAMPLE SERIES matter as much as the summary values, and are easy to lose here.
        // A Hevy lifting session wins on its set-by-set detail but carries no sensor data at
        // all, while the Apple Health copy of the same session has the heart-rate series from
        // the watch. Taking only the average would score the session but leave it with no zone
        // distribution and no decoupling, which are exactly the analyses the series exists for.
        if winner.heartRateSeries == nil { winner.heartRateSeries = loser.heartRateSeries }
        if winner.powerSeries == nil { winner.powerSeries = loser.powerSeries }
        if winner.speedSeries == nil { winner.speedSeries = loser.speedSeries }
        if winner.cadenceSeries == nil { winner.cadenceSeries = loser.cadenceSeries }
        if winner.altitudeSeries == nil { winner.altitudeSeries = loser.altitudeSeries }
        if winner.distanceSeries == nil { winner.distanceSeries = loser.distanceSeries }
        if winner.route == nil { winner.route = loser.route }

        // Cached sample-derived metrics follow the series they were computed from.
        if winner.normalizedPowerWatts == nil { winner.normalizedPowerWatts = loser.normalizedPowerWatts }
        if winner.decouplingPercent == nil { winner.decouplingPercent = loser.decouplingPercent }
        return winner
    }
}
