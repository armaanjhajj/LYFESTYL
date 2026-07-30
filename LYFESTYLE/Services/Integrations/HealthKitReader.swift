//
//  HealthKitReader.swift
//  LYFESTYL
//
//  Reads Apple Health into the app's canonical types. This is the automatic half of the
//  aggregation: whatever the iPhone, an Apple Watch, or the Garmin Connect app writes into
//  HealthKit shows up here with no setup from the user.
//
//  What this can and cannot get, stated plainly because it shapes the whole feature:
//
//    APPLE WATCH sessions arrive complete. Heart rate, distance, energy, power, cadence,
//    running dynamics and the GPS route are all associated with the workout, so the full
//    sample series is available and every analysis applies.
//
//    GARMIN sessions arrive as ENVELOPES. Garmin writes the workout (type, duration,
//    distance, energy) but explicitly does not write the GPS track or the per-workout
//    heart-rate series, so decoupling, normalized power and zone occupancy cannot be
//    computed from HealthKit for a Garmin ride. Those need the .FIT file. The app says so
//    rather than showing a blank chart.
//
//  Two HealthKit subtleties that are easy to get wrong and are handled deliberately:
//
//    1. READ PERMISSION IS UNKNOWABLE. HealthKit deliberately never reveals whether a read
//       was granted, to avoid leaking that the user declined. An empty result is therefore
//       ambiguous between "denied" and "no data". Nothing here gates on
//       `authorizationStatus(for:)` for a read type, and an empty store is treated as a
//       normal, fully supported state.
//
//    2. CUMULATIVE VERSUS DISCRETE. Asking for a `.discreteAverage` of step count returns
//       nil rather than an error, and vice versa, so a mismatch shows up as a silently
//       empty chart. Each type's aggregation style is read from HealthKit itself rather
//       than assumed.
//
//  All queries use the modern async descriptors, verified against the iOS 26 SDK.
//

import Foundation
import HealthKit
import CoreLocation

// MARK: - Reader

nonisolated struct HealthKitReader: Sendable {

    private let store: HKHealthStore

    init(store: HKHealthStore) {
        self.store = store
    }

    // MARK: Types

    /// Quantity types read for daily wellness, paired with the metric they feed.
    static let dailyQuantityTypes: [(WellnessMetric, HKQuantityTypeIdentifier)] = [
        (.restingHeartRate,     .restingHeartRate),
        (.heartRateVariability, .heartRateVariabilitySDNN),
        (.respiratoryRate,      .respiratoryRate),
        (.oxygenSaturation,     .oxygenSaturation),
        (.wristTemperature,     .appleSleepingWristTemperature),
        (.walkingHeartRate,     .walkingHeartRateAverage),
        (.heartRateRecovery,    .heartRateRecoveryOneMinute),
        (.steps,                .stepCount),
        (.activeEnergy,         .activeEnergyBurned),
        (.exerciseMinutes,      .appleExerciseTime),
        (.standHours,           .appleStandTime),
        (.flightsClimbed,       .flightsClimbed),
        (.timeInDaylight,       .timeInDaylight),
        (.vo2Max,               .vo2Max),
        (.bodyMass,             .bodyMass),
        (.bodyFat,              .bodyFatPercentage),
        (.leanBodyMass,         .leanBodyMass),
    ]

    /// Everything the app asks permission to read.
    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKCategoryType(.sleepAnalysis),
            HKCategoryType(.mindfulSession),
            // Route data needs its OWN authorization. Without it, route queries silently
            // return nothing rather than failing, which is a confusing bug to chase.
            HKSeriesType.workoutRoute(),
        ]
        for (_, identifier) in dailyQuantityTypes { types.insert(HKQuantityType(identifier)) }
        // Series types read inside a workout.
        for identifier in workoutSeriesTypes { types.insert(HKQuantityType(identifier)) }
        types.insert(HKQuantityType(.basalEnergyBurned))
        types.insert(HKQuantityType(.distanceWalkingRunning))
        types.insert(HKQuantityType(.cyclingFunctionalThresholdPower))
        types.insert(HKQuantityType(.appleSleepingBreathingDisturbances))
        return types
    }

    /// Quantity types sampled across a workout to build its series.
    static let workoutSeriesTypes: [HKQuantityTypeIdentifier] = [
        .heartRate, .runningSpeed, .cyclingSpeed, .runningPower, .cyclingPower,
        .cyclingCadence, .distanceWalkingRunning, .distanceCycling,
        .runningStrideLength, .runningGroundContactTime, .runningVerticalOscillation,
    ]

    // MARK: Units

    static func unit(for identifier: HKQuantityTypeIdentifier) -> HKUnit {
        switch identifier {
        case .stepCount, .flightsClimbed:            .count()
        case .activeEnergyBurned, .basalEnergyBurned: .kilocalorie()
        case .appleExerciseTime, .appleStandTime, .timeInDaylight: .minute()
        case .distanceWalkingRunning, .distanceCycling, .runningStrideLength: .meter()
        case .restingHeartRate, .walkingHeartRateAverage, .heartRate, .heartRateRecoveryOneMinute,
             .respiratoryRate:
            HKUnit.count().unitDivided(by: .minute())
        case .heartRateVariabilitySDNN:              .secondUnit(with: .milli)
        case .oxygenSaturation, .bodyFatPercentage:  .percent()
        case .appleSleepingWristTemperature:         .degreeCelsius()
        case .vo2Max:
            // mL/(kg*min), the standard VO2 max unit.
            HKUnit.literUnit(with: .milli)
                .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        case .bodyMass, .leanBodyMass:               .gramUnit(with: .kilo)
        case .runningSpeed, .cyclingSpeed:           HKUnit.meter().unitDivided(by: .second())
        case .runningPower, .cyclingPower, .cyclingFunctionalThresholdPower: .watt()
        case .cyclingCadence:                        HKUnit.count().unitDivided(by: .minute())
        case .runningGroundContactTime:              .secondUnit(with: .milli)
        case .runningVerticalOscillation:            .meterUnit(with: .centi)
        case .appleSleepingBreathingDisturbances:    .count()
        default:                                     .count()
        }
    }

    // MARK: - Authorization

    /// Present the system permission sheet. HealthKit never reports whether READ access was
    /// granted, so a non-throwing call is treated as "asked" and an empty store afterwards
    /// is a normal outcome.
    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    // MARK: - Sources

    /// Classify a sample's writer.
    static func dataSource(for revision: HKSourceRevision?) -> DataSource {
        let bundle = (revision?.source.bundleIdentifier ?? "").lowercased()
        let name = (revision?.source.name ?? "").lowercased()
        if bundle.contains("garmin") || name.contains("garmin") { return .garmin }
        if bundle.contains("hevy") || name.contains("hevy") { return .hevy }
        return .appleHealth
    }

    // MARK: - Workouts

    /// Read workouts in a window and convert them, including their sample series and route.
    ///
    /// `includeSeries` is expensive (one query per metric per workout), so a first full
    /// backfill can skip it and fill series in later for recent sessions only.
    func workouts(
        from start: Date,
        to end: Date = Date(),
        includeSeries: Bool = true,
        seriesLimit: Int = 60,
        calendar: Calendar = .current
    ) async -> [UnifiedWorkout] {
        let predicate = HKSamplePredicate.workout(
            HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }

        var results: [UnifiedWorkout] = []
        results.reserveCapacity(samples.count)

        for (index, workout) in samples.enumerated() {
            // Series only for the most recent sessions, newest first.
            let wantSeries = includeSeries && index < seriesLimit
            if let converted = await convert(workout, includeSeries: wantSeries, calendar: calendar) {
                results.append(converted)
            }
        }
        return results
    }

    /// Convert one `HKWorkout`.
    func convert(
        _ workout: HKWorkout,
        includeSeries: Bool,
        calendar: Calendar = .current
    ) async -> UnifiedWorkout? {
        let duration = workout.duration
        guard duration > 10 else { return nil }

        let source = Self.dataSource(for: workout.sourceRevision)
        let sport = Self.sport(for: workout.workoutActivityType, metadata: workout.metadata)

        // `HKWorkout.statistics(for:)` supersedes the deprecated `totalEnergyBurned` and
        // friends, and is the only way to reach per-type aggregates on iOS 18 and later.
        let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())

        let distance = Self.distance(for: workout, sport: sport)

        let heartRateStats = workout.statistics(for: HKQuantityType(.heartRate))
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let averageHeartRate = heartRateStats?.averageQuantity()?.doubleValue(for: bpm)
        let maxHeartRate = heartRateStats?.maximumQuantity()?.doubleValue(for: bpm)

        let powerType: HKQuantityTypeIdentifier = sport.discipline == .cycling ? .cyclingPower : .runningPower
        let powerStats = workout.statistics(for: HKQuantityType(powerType))
        let averagePower = powerStats?.averageQuantity()?.doubleValue(for: .watt())
        let maxPower = powerStats?.maximumQuantity()?.doubleValue(for: .watt())

        let cadenceType: HKQuantityTypeIdentifier? = sport.discipline == .cycling ? .cyclingCadence : nil
        let averageCadence = cadenceType.flatMap {
            workout.statistics(for: HKQuantityType($0))?.averageQuantity()?.doubleValue(for: bpm)
        }

        // Metadata carries elevation and the indoor flag when the writer set them.
        let elevationGain = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
            .doubleValue(for: .meter())
        let elevationLoss = (workout.metadata?[HKMetadataKeyElevationDescended] as? HKQuantity)?
            .doubleValue(for: .meter())
        let indoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool

        // Apple's own effort score, either the watch's estimate or the user's rating.
        let effort = workout.statistics(for: HKQuantityType(.workoutEffortScore))?
            .mostRecentQuantity()?.doubleValue(for: .appleEffortScore())
            ?? workout.statistics(for: HKQuantityType(.estimatedWorkoutEffortScore))?
                .mostRecentQuantity()?.doubleValue(for: .appleEffortScore())

        var series: WorkoutSeries = .empty
        var route: RouteSummary?
        if includeSeries {
            series = await self.series(for: workout, sport: sport)
            route = await self.route(for: workout)
        }

        let origin = SourceRef(
            source: source,
            foreignID: workout.uuid.uuidString,
            updatedAt: workout.endDate
        )

        let normalizedPower = series.power.flatMap { TrainingLoad.normalizedPower($0) }
        let decoupling = TrainingLoad.aerobicDecoupling(
            heartRateSeries: series.heartRate,
            powerSeries: series.power,
            speedSeries: series.speed
        )

        return UnifiedWorkout(
            id: origin.uniqueKey,
            origin: origin,
            sport: sport,
            title: Self.title(for: sport, start: workout.startDate, metadata: workout.metadata),
            notes: nil,
            start: workout.startDate,
            end: workout.endDate,
            movingSeconds: duration,
            isIndoor: indoor ?? sport.isIndoorByNature,
            distanceMeters: positive(distance),
            activeEnergyKcal: positive(energy),
            elevationGainMeters: positive(elevationGain),
            elevationLossMeters: positive(elevationLoss),
            averageHeartRate: plausibleHeartRate(averageHeartRate),
            maxHeartRate: plausibleHeartRate(maxHeartRate),
            averageSpeedMps: nil,   // derived from distance and time by the model
            maxSpeedMps: series.speed?.maximum,
            averagePowerWatts: positive(averagePower),
            maxPowerWatts: positive(maxPower),
            averageCadence: positive(averageCadence),
            averageStrideLengthMeters: series.strideLength?.mean,
            averageGroundContactMs: series.groundContact?.mean,
            averageVerticalOscillationCm: series.verticalOscillation?.mean,
            workoutEffortScore: effort,
            normalizedPowerWatts: positive(normalizedPower),
            decouplingPercent: decoupling,
            heartRateSeries: series.heartRate,
            speedSeries: series.speed,
            powerSeries: series.power,
            cadenceSeries: series.cadence,
            altitudeSeries: nil,   // HealthKit exposes no altitude series
            distanceSeries: series.distance,
            route: route,
            strength: nil,
            calendar: calendar
        )
    }

    /// The sample series bundle for one workout.
    struct WorkoutSeries: Sendable {
        var heartRate: MetricSeries?
        var speed: MetricSeries?
        var power: MetricSeries?
        var cadence: MetricSeries?
        var distance: MetricSeries?
        var strideLength: MetricSeries?
        var groundContact: MetricSeries?
        var verticalOscillation: MetricSeries?

        static let empty = WorkoutSeries()

        var isEmpty: Bool { heartRate == nil && speed == nil && power == nil }
    }

    /// Read the sample series associated with a workout.
    ///
    /// `predicateForObjects(from:)` only matches samples the writer EXPLICITLY associated
    /// with the workout. Apple Watch does; Garmin does not. So when the association
    /// returns nothing, this falls back to a time-window query narrowed to the same source,
    /// which is the best available and is honest about being coarser.
    func series(for workout: HKWorkout, sport: WorkoutSport) async -> WorkoutSeries {
        var result = WorkoutSeries()
        let bpm = HKUnit.count().unitDivided(by: .minute())

        result.heartRate = await samples(.heartRate, unit: bpm, workout: workout)

        let speedType: HKQuantityTypeIdentifier = sport.discipline == .cycling ? .cyclingSpeed : .runningSpeed
        result.speed = await samples(speedType, unit: HKUnit.meter().unitDivided(by: .second()), workout: workout)

        let powerType: HKQuantityTypeIdentifier = sport.discipline == .cycling ? .cyclingPower : .runningPower
        result.power = await samples(powerType, unit: .watt(), workout: workout)

        if sport.discipline == .cycling {
            result.cadence = await samples(.cyclingCadence, unit: bpm, workout: workout)
        }

        let distanceType: HKQuantityTypeIdentifier = sport.discipline == .cycling
            ? .distanceCycling : .distanceWalkingRunning
        // Distance samples are cumulative per interval, so they are integrated into a
        // running total, which is what grade adjustment and pace curves need.
        result.distance = await cumulativeSeries(distanceType, unit: .meter(), workout: workout)

        if sport.discipline == .running {
            result.strideLength = await samples(.runningStrideLength, unit: .meter(), workout: workout)
            result.groundContact = await samples(.runningGroundContactTime, unit: .secondUnit(with: .milli), workout: workout)
            result.verticalOscillation = await samples(.runningVerticalOscillation, unit: .meterUnit(with: .centi), workout: workout)
        }
        return result
    }

    /// Read one quantity type across a workout as an instantaneous series.
    private func samples(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        workout: HKWorkout
    ) async -> MetricSeries? {
        let type = HKQuantityType(identifier)

        // First try samples the writer explicitly associated with the workout.
        var predicate = HKSamplePredicate.quantitySample(
            type: type,
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        var values = await fetch(predicate: predicate, unit: unit, workout: workout)

        if values == nil {
            // Fall back to a time window, narrowed to the same writer so another device's
            // all-day samples cannot contaminate this session.
            var conditions: [NSPredicate] = [
                HKQuery.predicateForSamples(
                    withStart: workout.startDate,
                    end: workout.endDate,
                    options: [.strictStartDate, .strictEndDate]
                )
            ]
            conditions.append(HKQuery.predicateForObjects(from: Set([workout.sourceRevision])))
            predicate = HKSamplePredicate.quantitySample(
                type: type,
                predicate: NSCompoundPredicate(andPredicateWithSubpredicates: conditions)
            )
            values = await fetch(predicate: predicate, unit: unit, workout: workout)
        }
        return values
    }

    private func fetch(
        predicate: HKSamplePredicate<HKQuantitySample>,
        unit: HKUnit,
        workout: HKWorkout
    ) async -> MetricSeries? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store), samples.count >= 3 else {
            return nil
        }
        var offsets: [Double] = []
        var values: [Double] = []
        offsets.reserveCapacity(samples.count)
        values.reserveCapacity(samples.count)
        for sample in samples {
            // Use the sample's midpoint: a heart-rate sample covering ten seconds is best
            // placed at its centre, not its leading edge.
            let midpoint = sample.startDate.addingTimeInterval(
                sample.endDate.timeIntervalSince(sample.startDate) / 2
            )
            let offset = midpoint.timeIntervalSince(workout.startDate)
            guard offset >= 0 else { continue }
            let value = sample.quantity.doubleValue(for: unit)
            guard value.isFinite else { continue }
            offsets.append(offset)
            values.append(value)
        }
        guard values.count >= 3 else { return nil }
        return Downsampler.reduce(MetricSeries(offsets: offsets, values: values))
    }

    /// Integrate a cumulative type (distance) into a running total.
    private func cumulativeSeries(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        workout: HKWorkout
    ) async -> MetricSeries? {
        let type = HKQuantityType(identifier)
        let predicate = HKSamplePredicate.quantitySample(
            type: type,
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store), samples.count >= 3 else {
            return nil
        }
        var offsets: [Double] = []
        var values: [Double] = []
        var total = 0.0
        for sample in samples {
            total += sample.quantity.doubleValue(for: unit)
            let offset = sample.endDate.timeIntervalSince(workout.startDate)
            guard offset >= 0 else { continue }
            offsets.append(offset)
            values.append(total)
        }
        guard values.count >= 3 else { return nil }
        return Downsampler.reduce(MetricSeries(offsets: offsets, values: values))
    }

    /// Read the GPS track for a workout.
    ///
    /// Routes are a SERIES type needing their own authorization, and route samples are
    /// mutable, which is why Apple's documented pattern uses an anchored query.
    func route(for workout: HKWorkout) async -> RouteSummary? {
        let predicate = HKSamplePredicate.workoutRoute(HKQuery.predicateForObjects(from: workout))
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [predicate], anchor: nil)
        guard let result = try? await descriptor.result(for: store) else { return nil }
        guard let routeSample = result.addedSamples.first else { return nil }

        var latitudes: [Double] = []
        var longitudes: [Double] = []
        let locations = HKWorkoutRouteQueryDescriptor(routeSample).results(for: store)
        do {
            for try await location in locations {
                // Reject implausible fixes so one bad point cannot blow out the bounds.
                guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 100 else {
                    continue
                }
                latitudes.append(location.coordinate.latitude)
                longitudes.append(location.coordinate.longitude)
            }
        } catch {
            // A partial track is still worth drawing.
        }
        guard latitudes.count >= 2 else { return nil }
        return Downsampler.reduceRoute(latitudes: latitudes, longitudes: longitudes)
    }

    // MARK: - Daily wellness

    /// Build one snapshot per day across a window.
    func dailySnapshots(
        from start: Date,
        to end: Date = Date(),
        calendar: Calendar = .current
    ) async -> [DailySnapshot] {
        let anchor = calendar.startOfDay(for: start)
        let finish = calendar.startOfDay(for: end).addingTimeInterval(24 * 3600)

        // One statistics-collection query per metric covers the whole window in a single
        // pass, which is far cheaper than a query per day.
        var perMetric: [WellnessMetric: [Date: Double]] = [:]
        for (metric, identifier) in Self.dailyQuantityTypes {
            perMetric[metric] = await dailyValues(
                identifier,
                from: anchor, to: finish, calendar: calendar
            )
        }
        let basal = await dailyValues(.basalEnergyBurned, from: anchor, to: finish, calendar: calendar)
        let walkRun = await dailyValues(.distanceWalkingRunning, from: anchor, to: finish, calendar: calendar)
        let disturbances = await dailyValues(.appleSleepingBreathingDisturbances, from: anchor, to: finish, calendar: calendar)
        let mindful = await mindfulMinutesByDay(from: anchor, to: finish, calendar: calendar)
        let nights = await sleepNights(from: anchor.addingTimeInterval(-24 * 3600), to: finish, calendar: calendar)
        let nightsByDay = Dictionary(nights.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })

        // Every day that any source touched.
        var days = Set<Date>()
        for values in perMetric.values { days.formUnion(values.keys) }
        days.formUnion(basal.keys)
        days.formUnion(walkRun.keys)
        days.formUnion(mindful.keys)
        days.formUnion(nightsByDay.keys)

        return days.sorted().compactMap { day -> DailySnapshot? in
            func value(_ metric: WellnessMetric) -> Double? { perMetric[metric]?[day] }

            var oxygen = value(.oxygenSaturation)
            // HealthKit stores oxygen saturation as a fraction where 1.0 is 100 percent.
            if let raw = oxygen, raw <= 1.5 { oxygen = raw * 100 }
            var fat = value(.bodyFat)
            if let raw = fat, raw <= 1.5 { fat = raw * 100 }

            let snapshot = DailySnapshot(
                date: day,
                sleep: nightsByDay[day],
                restingHeartRate: value(.restingHeartRate),
                heartRateVariabilityMs: value(.heartRateVariability),
                respiratoryRate: value(.respiratoryRate),
                oxygenSaturationPercent: oxygen,
                wristTemperatureDeltaC: value(.wristTemperature),
                walkingHeartRateAverage: value(.walkingHeartRate),
                heartRateRecoveryOneMinute: value(.heartRateRecovery),
                breathingDisturbances: disturbances[day],
                steps: value(.steps),
                activeEnergyKcal: value(.activeEnergy),
                basalEnergyKcal: basal[day],
                exerciseMinutes: value(.exerciseMinutes),
                // Apple stores stand time in minutes; the app shows stand HOURS.
                standHours: value(.standHours).map { $0 / 60 },
                flightsClimbed: value(.flightsClimbed),
                distanceWalkingRunningMeters: walkRun[day],
                timeInDaylightMinutes: value(.timeInDaylight),
                vo2Max: value(.vo2Max),
                bodyMassKg: value(.bodyMass),
                bodyFatPercent: fat,
                leanBodyMassKg: value(.leanBodyMass),
                mindfulMinutes: mindful[day],
                contributingSources: [.appleHealth]
            )
            return snapshot.isEmpty ? nil : snapshot
        }
    }

    /// One value per day for a quantity type, using the right statistic for its
    /// aggregation style.
    private func dailyValues(
        _ identifier: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) async -> [Date: Double] {
        let type = HKQuantityType(identifier)
        let cumulative = type.aggregationStyle == .cumulative
        let unit = Self.unit(for: identifier)

        let predicate = HKSamplePredicate.quantitySample(
            type: type,
            predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        )
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate,
            // Using the wrong option for the style returns nil rather than erroring, so the
            // style is read from HealthKit itself.
            options: cumulative ? .cumulativeSum : .discreteAverage,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [:] }

        var result: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            let quantity = cumulative ? statistics.sumQuantity() : statistics.averageQuantity()
            guard let quantity else { return }
            let value = quantity.doubleValue(for: unit)
            guard value.isFinite, value != 0 else { return }
            result[calendar.startOfDay(for: statistics.startDate)] = value
        }
        return result
    }

    private func mindfulMinutesByDay(
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) async -> [Date: Double] {
        let predicate = HKSamplePredicate.categorySample(
            type: HKCategoryType(.mindfulSession),
            predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [:] }
        var result: [Date: Double] = [:]
        for sample in samples {
            let minutes = sample.endDate.timeIntervalSince(sample.startDate) / 60
            guard minutes > 0 else { continue }
            result[calendar.startOfDay(for: sample.startDate), default: 0] += minutes
        }
        return result
    }

    // MARK: - Sleep

    /// Read sleep and assemble it into nights.
    ///
    /// Sleep samples OVERLAP: a coarse "asleep" block and its staged Core/Deep/REM
    /// breakdown cover the same minutes, and two devices can both describe one night.
    /// Every duration therefore comes from interval union arithmetic in `SleepAssembler`,
    /// never from summing sample durations, which would report eight hours of deep sleep.
    func sleepNights(
        from start: Date,
        to end: Date = Date(),
        calendar: Calendar = .current
    ) async -> [SleepNight] {
        let predicate = HKSamplePredicate.categorySample(
            type: HKCategoryType(.sleepAnalysis),
            predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else {
            return []
        }

        let intervals: [SleepAssembler.Interval] = samples.compactMap { sample in
            guard let stage = Self.sleepStage(for: sample.value) else { return nil }
            guard sample.endDate > sample.startDate else { return nil }
            return SleepAssembler.Interval(
                start: sample.startDate,
                end: sample.endDate,
                stage: stage,
                source: Self.dataSource(for: sample.sourceRevision)
            )
        }
        guard !intervals.isEmpty else { return [] }
        return SleepAssembler.assembleNights(intervals: intervals, calendar: calendar)
    }

    /// Map a HealthKit sleep value onto a stage.
    ///
    /// Note that `.asleep` (deprecated in iOS 16) and `.asleepUnspecified` share raw value
    /// 1, so a switch cannot list both without a duplicate-case error. `.inBed` is mapped
    /// to nil here and handled by the assembler through the union of all reported
    /// intervals, which is what makes sleep efficiency computable.
    static func sleepStage(for value: Int) -> SleepStage? {
        switch value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:              nil
        case HKCategoryValueSleepAnalysis.awake.rawValue:              .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:         .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:         .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:          .rem
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:  .unspecified
        default:                                                       nil
        }
    }

    // MARK: - Profile anchors

    /// Read anchors the store can supply: functional threshold power (written by bike
    /// computers), the highest heart rate ever recorded, and body mass.
    func profileAnchors(lookbackDays: Int = 365) async -> (maxHeartRate: Double?, ftp: Double?, bodyMassKg: Double?) {
        let start = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date())

        async let maxHR = mostExtreme(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()),
                                      from: start, ascending: false)
        async let ftp = mostRecent(.cyclingFunctionalThresholdPower, unit: .watt(), from: start)
        async let mass = mostRecent(.bodyMass, unit: .gramUnit(with: .kilo), from: start)

        let heartRate = await maxHR
        return (
            maxHeartRate: heartRate.flatMap { ProfileSnapshot.plausibleMaxHeartRate.contains($0) ? $0 : nil },
            ftp: await ftp,
            bodyMassKg: await mass
        )
    }

    private func mostRecent(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date?
    ) async -> Double? {
        let predicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(identifier),
            predicate: HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        let value = sample.quantity.doubleValue(for: unit)
        return value.isFinite ? value : nil
    }

    private func mostExtreme(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date?,
        ascending: Bool
    ) async -> Double? {
        let type = HKQuantityType(identifier)
        let predicate = HKSamplePredicate.quantitySample(
            type: type,
            predicate: HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: predicate,
            options: ascending ? .discreteMin : .discreteMax
        )
        guard let statistics = try? await descriptor.result(for: store) else { return nil }
        let quantity = ascending ? statistics.minimumQuantity() : statistics.maximumQuantity()
        guard let value = quantity?.doubleValue(for: unit), value.isFinite else { return nil }
        return value
    }

    // MARK: - Mapping helpers

    /// Distance for a workout, using the type appropriate to the sport.
    private static func distance(for workout: HKWorkout, sport: WorkoutSport) -> Double? {
        let identifiers: [HKQuantityTypeIdentifier]
        switch sport.discipline {
        case .cycling:  identifiers = [.distanceCycling]
        case .swimming: identifiers = [.distanceSwimming]
        case .rowing:   identifiers = [.distanceRowing]
        default:        identifiers = [.distanceWalkingRunning, .distanceCycling]
        }
        for identifier in identifiers {
            if let value = workout.statistics(for: HKQuantityType(identifier))?
                .sumQuantity()?.doubleValue(for: .meter()), value > 0 {
                return value
            }
        }
        return nil
    }

    /// Map an `HKWorkoutActivityType` onto the app's sport vocabulary.
    ///
    /// Note there is no `.strengthTraining` case in HealthKit: Apple splits it into
    /// traditional and functional, and Garmin's generic "Strength" arrives as traditional.
    static func sport(for type: HKWorkoutActivityType, metadata: [String: Any]?) -> WorkoutSport {
        let indoor = metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false
        switch type {
        case .running:                      return indoor ? .treadmillRun : .run
        case .walking:                      return .walk
        case .hiking:                       return .hike
        case .cycling:                      return indoor ? .indoorRide : .ride
        case .handCycling:                  return .handCycle
        case .swimming:                     return .poolSwim
        case .rowing:                       return indoor ? .indoorRow : .row
        case .paddleSports:                 return .paddle
        case .surfingSports:                return .surf
        case .elliptical:                   return .elliptical
        case .stairClimbing, .stairs:       return .stairClimber
        case .jumpRope:                     return .jumpRope
        case .traditionalStrengthTraining:  return .strengthTraining
        case .functionalStrengthTraining:   return .functionalStrength
        case .coreTraining:                 return .coreTraining
        case .highIntensityIntervalTraining: return .hiit
        case .crossTraining, .mixedCardio:  return .crossTraining
        case .boxing, .kickboxing:          return .boxing
        case .martialArts, .wrestling:      return .martialArts
        case .climbing:                     return .climbing
        case .basketball, .soccer, .americanFootball, .australianFootball, .rugby,
             .hockey, .volleyball, .baseball, .softball, .lacrosse, .cricket, .handball,
             .waterPolo:
            return .teamSport
        case .tennis, .badminton, .squash, .racquetball, .tableTennis, .pickleball:
            return .racquetSport
        case .downhillSkiing, .crossCountrySkiing, .snowboarding, .snowSports:
            return .snowSport
        case .skatingSports:                return .skateSport
        case .golf:                         return .golf
        case .cardioDance, .socialDance, .barre:  return .dance
        case .yoga:                         return .yoga
        case .pilates:                      return .pilates
        case .flexibility, .preparationAndRecovery: return .flexibility
        case .mindAndBody, .taiChi:         return .mindAndBody
        case .cooldown:                     return .cooldown
        case .trackAndField:                return .track
        case .stepTraining, .fitnessGaming, .play, .discSports, .bowling, .archery,
             .fishing, .hunting, .sailing, .equestrianSports, .curling, .fencing,
             .gymnastics, .waterFitness, .waterSports, .underwaterDiving, .swimBikeRun,
             .transition:
            return .other
        default:                            return .other
        }
    }

    private static func title(for sport: WorkoutSport, start: Date, metadata: [String: Any]?) -> String {
        // A named session (a Fitness+ class, or a brand-named workout) keeps its name.
        if let brand = metadata?[HKMetadataKeyWorkoutBrandName] as? String,
           !brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return brand
        }
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

    private func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private func plausibleHeartRate(_ value: Double?) -> Double? {
        guard let value, value >= 25, value <= 240 else { return nil }
        return value
    }
}
