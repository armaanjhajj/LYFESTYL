//
//  WorkoutSport.swift
//  LYFESTYL
//
//  One closed vocabulary for "what kind of session was this," so a Garmin trail
//  run, an Apple Watch outdoor run and a manually logged run all land on the same
//  `.trailRun` / `.run` and can be compared over time.
//
//  Every sport declares a `family`, which is what the analysis actually branches
//  on: endurance sessions get load, decoupling and efficiency; strength sessions
//  get volume, e1RM and muscle balance. That keeps the analytics honest, we never
//  compute a running pace trend from a lifting session.
//

import SwiftUI

/// The broad kind of training, which decides which analyses apply.
nonisolated enum SportFamily: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    /// Continuous aerobic work with distance and heart rate: runs, rides, swims,
    /// rows. Gets training load, aerobic decoupling, efficiency factor, pace and
    /// power curves.
    case endurance
    /// Resistance training measured in sets, reps and load. Gets volume load,
    /// estimated 1RM, per-muscle weekly sets and balance.
    case strength
    /// Mixed or intermittent conditioning (HIIT, circuits, classes, court sports).
    /// Gets heart-rate based load but no pace or distance analysis.
    case mixed
    /// Low-intensity mobility and mind-body work. Counted for consistency and
    /// recovery context, deliberately excluded from load ramp calculations.
    case restorative

    var id: String { rawValue }

    var label: String {
        switch self {
        case .endurance:   "ENDURANCE"
        case .strength:    "STRENGTH"
        case .mixed:       "CONDITIONING"
        case .restorative: "RECOVERY"
        }
    }

    var accent: Color {
        switch self {
        case .endurance:   Solar.blue
        case .strength:    Solar.violet
        case .mixed:       Solar.orange
        case .restorative: Solar.cyan
        }
    }

    /// Whether pace, distance and grade analysis make sense here.
    var hasDistance: Bool { self == .endurance }
}

/// The specific sport. Deliberately finite: unmapped source activities fall back
/// to `.other` rather than inventing a case, so nothing is silently mislabeled.
nonisolated enum WorkoutSport: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    // Running family
    case run
    case trailRun
    case treadmillRun
    case track
    case walk
    case hike

    // Cycling family
    case ride
    case indoorRide
    case gravelRide
    case mountainBike
    case handCycle

    // Water
    case poolSwim
    case openWaterSwim
    case row
    case indoorRow
    case paddle
    case surf

    // Gym machines
    case elliptical
    case stairClimber
    case jumpRope

    // Strength
    case strengthTraining
    case functionalStrength
    case coreTraining

    // Conditioning and sport
    case hiit
    case crossTraining
    case boxing
    case martialArts
    case climbing
    case teamSport
    case racquetSport
    case snowSport
    case skateSport
    case golf
    case dance

    // Restorative
    case yoga
    case pilates
    case flexibility
    case mindAndBody
    case cooldown

    case other

    var id: String { rawValue }

    var family: SportFamily {
        switch self {
        case .run, .trailRun, .treadmillRun, .track, .walk, .hike,
             .ride, .indoorRide, .gravelRide, .mountainBike, .handCycle,
             .poolSwim, .openWaterSwim, .row, .indoorRow, .paddle,
             .elliptical, .stairClimber:
            return .endurance
        case .strengthTraining, .functionalStrength, .coreTraining:
            return .strength
        case .hiit, .crossTraining, .boxing, .martialArts, .climbing,
             .teamSport, .racquetSport, .snowSport, .skateSport, .golf,
             .dance, .surf, .jumpRope, .other:
            return .mixed
        case .yoga, .pilates, .flexibility, .mindAndBody, .cooldown:
            return .restorative
        }
    }

    var label: String {
        switch self {
        case .run:                "Run"
        case .trailRun:           "Trail Run"
        case .treadmillRun:       "Treadmill Run"
        case .track:              "Track"
        case .walk:               "Walk"
        case .hike:               "Hike"
        case .ride:               "Ride"
        case .indoorRide:         "Indoor Ride"
        case .gravelRide:         "Gravel Ride"
        case .mountainBike:       "Mountain Bike"
        case .handCycle:          "Hand Cycle"
        case .poolSwim:           "Pool Swim"
        case .openWaterSwim:      "Open Water Swim"
        case .row:                "Row"
        case .indoorRow:          "Indoor Row"
        case .paddle:             "Paddle"
        case .surf:               "Surf"
        case .elliptical:         "Elliptical"
        case .stairClimber:       "Stair Climber"
        case .jumpRope:           "Jump Rope"
        case .strengthTraining:   "Strength"
        case .functionalStrength: "Functional Strength"
        case .coreTraining:       "Core"
        case .hiit:               "HIIT"
        case .crossTraining:      "Cross Training"
        case .boxing:             "Boxing"
        case .martialArts:        "Martial Arts"
        case .climbing:           "Climbing"
        case .teamSport:          "Team Sport"
        case .racquetSport:       "Racquet Sport"
        case .snowSport:          "Snow Sport"
        case .skateSport:         "Skating"
        case .golf:               "Golf"
        case .dance:              "Dance"
        case .yoga:               "Yoga"
        case .pilates:            "Pilates"
        case .flexibility:        "Flexibility"
        case .mindAndBody:        "Mind and Body"
        case .cooldown:           "Cooldown"
        case .other:              "Workout"
        }
    }

    var symbolName: String {
        switch self {
        case .run, .track:                    "figure.run"
        case .trailRun:                       "figure.run.circle"
        case .treadmillRun:                   "figure.run.treadmill"
        case .walk:                           "figure.walk"
        case .hike:                           "figure.hiking"
        case .ride, .gravelRide:              "figure.outdoor.cycle"
        case .indoorRide:                     "figure.indoor.cycle"
        case .mountainBike:                   "bicycle"
        case .handCycle:                      "figure.hand.cycling"
        case .poolSwim:                       "figure.pool.swim"
        case .openWaterSwim:                  "figure.open.water.swim"
        case .row:                            "figure.outdoor.rowing"
        case .indoorRow:                      "figure.indoor.rowing"
        case .paddle:                         "figure.water.fitness"
        case .surf:                           "figure.surfing"
        case .elliptical:                     "figure.elliptical"
        case .stairClimber:                   "figure.stair.stepper"
        case .jumpRope:                       "figure.jumprope"
        case .strengthTraining:               "figure.strengthtraining.traditional"
        case .functionalStrength:             "figure.strengthtraining.functional"
        case .coreTraining:                   "figure.core.training"
        case .hiit:                           "figure.highintensity.intervaltraining"
        case .crossTraining:                  "figure.cross.training"
        case .boxing:                         "figure.boxing"
        case .martialArts:                    "figure.martial.arts"
        case .climbing:                       "figure.climbing"
        case .teamSport:                      "figure.basketball"
        case .racquetSport:                   "figure.tennis"
        case .snowSport:                       "figure.skiing.downhill"
        case .skateSport:                     "figure.skating"
        case .golf:                           "figure.golf"
        case .dance:                          "figure.dance"
        case .yoga:                           "figure.yoga"
        case .pilates:                        "figure.pilates"
        case .flexibility:                    "figure.flexibility"
        case .mindAndBody:                    "figure.mind.and.body"
        case .cooldown:                       "figure.cooldown"
        case .other:                          "figure.mixed.cardio"
        }
    }

    var accent: Color { family.accent }

    /// Sessions that happen indoors have no usable GPS pace or grade, so the
    /// analysis skips speed-based work for them and leans on heart rate.
    var isIndoorByNature: Bool {
        switch self {
        case .treadmillRun, .indoorRide, .indoorRow, .elliptical, .stairClimber,
             .poolSwim, .jumpRope, .strengthTraining, .functionalStrength,
             .coreTraining, .yoga, .pilates, .flexibility, .mindAndBody:
            true
        default:
            false
        }
    }

    /// Which distance-bearing discipline this belongs to, for grouping personal
    /// bests and pace curves. Comparing a 5k run split against a bike split would
    /// be meaningless, so bests are always scoped to a discipline.
    enum Discipline: String, Codable, Hashable, Sendable {
        case running, cycling, swimming, rowing, walking, none
    }

    var discipline: Discipline {
        switch self {
        case .run, .trailRun, .treadmillRun, .track:                     .running
        case .walk, .hike:                                               .walking
        case .ride, .indoorRide, .gravelRide, .mountainBike, .handCycle: .cycling
        case .poolSwim, .openWaterSwim:                                  .swimming
        case .row, .indoorRow:                                           .rowing
        default:                                                         .none
        }
    }

    /// The life category this session files under in the journal, so a synced
    /// workout sits alongside hand-written entries.
    var insightCategory: InsightCategory { .activity }
}
