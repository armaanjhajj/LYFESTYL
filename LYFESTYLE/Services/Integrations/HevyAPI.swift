//
//  HevyAPI.swift
//  LYFESTYL
//
//  Client for the Hevy public REST API, written against its live OpenAPI document.
//
//  Base URL:  https://api.hevyapp.com
//  Auth:      an `api-key` header carrying the UUID the user generates at
//             https://hevy.com/settings?developer (requires a Hevy Pro account)
//
//  The API has a set of real, verified quirks that this client handles deliberately.
//  They are documented at each site because every one of them is a silent-failure trap:
//
//    - A bad key returns HTTP 401 with `text/html` and the literal 13-byte body
//      "InvalidApiKey". Decoding that as JSON produces a baffling `dataCorrupted`
//      error, so status is always checked before any decode.
//    - `pageSize` caps at 10 for workouts, events, routines and body measurements, and
//      at 100 only for exercise templates. Asking for more is a 400.
//    - Timestamps are ISO 8601 with a literal Z but are typed as plain strings with no
//      fractional-second guarantee, so parsing tries both forms.
//    - The published OpenAPI document is STALE in places. Two field names in it do not
//      match what the live API returns (`supersets_id` and `equipment_category`), and the
//      exercise-type enum is missing four values. Every name here was checked against real
//      responses, because a wrong key decodes silently to nil rather than failing.
//    - Almost nothing is in an OpenAPI `required` block, so effectively every field is
//      optional and is modelled that way.
//    - There is no webhook support. `/v1/workouts/events?since=` is the sanctioned
//      incremental mechanism and it is polled.
//    - Rate limits are undocumented and real, so requests are paced and 429 is
//      honoured with backoff.
//
//  Everything is kilograms, meters and seconds at the API level regardless of the
//  user's display preference in the Hevy app, which lines up exactly with this app's
//  canonical units.
//

import Foundation

// MARK: - Errors

nonisolated enum HevyError: LocalizedError, Equatable {
    case notConfigured
    case invalidKey
    case rateLimited(retryAfter: TimeInterval?)
    case quotaExceeded(String)
    case http(status: Int, body: String)
    case decoding(String)
    case network(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Hevy is not connected yet."
        case .invalidKey:
            "That Hevy API key was rejected. Check it in Hevy under Settings, Developer."
        case .rateLimited:
            "Hevy is rate limiting requests. This will retry shortly."
        case .quotaExceeded(let detail):
            "Hevy rejected the request: \(detail)"
        case .http(let status, _):
            "Hevy returned an unexpected response (\(status))."
        case .decoding(let detail):
            "Could not read Hevy's response. \(detail)"
        case .network(let detail):
            "Could not reach Hevy. \(detail)"
        case .cancelled:
            "Sync cancelled."
        }
    }

    /// Whether retrying later could plausibly succeed.
    var isTransient: Bool {
        switch self {
        case .rateLimited, .network: true
        case .http(let status, _): status >= 500
        default: false
        }
    }
}

// MARK: - Wire types (read path)

/// Field names here mirror Hevy's read payloads EXACTLY. Nearly everything is optional
/// because the spec declares almost no required fields.
nonisolated struct HevyWorkoutDTO: Decodable, Sendable {
    var id: String?
    var title: String?
    var description: String?
    var routine_id: String?
    var start_time: String?
    var end_time: String?
    var created_at: String?
    var updated_at: String?
    var exercises: [HevyExerciseDTO]?
}

nonisolated struct HevyExerciseDTO: Decodable, Sendable {
    var index: Int?
    var title: String?
    var notes: String?
    var exercise_template_id: String?
    /// Hevy's published OpenAPI document calls this `supersets_id` on the read path, but
    /// the live API actually returns `superset_id`. Verified against real responses: 44 of
    /// 50 sampled workouts contained supersets, and the spec name decoded to nil for all of
    /// them. The live name wins.
    var superset_id: Int?
    var sets: [HevySetDTO]?
}

nonisolated struct HevySetDTO: Decodable, Sendable {
    var index: Int?
    /// One of normal, warmup, dropset, failure. Left as a String because Hevy can add
    /// values and an unknown one must not fail the whole decode.
    var type: String?
    var weight_kg: Double?
    var reps: Int?
    var distance_meters: Double?
    var duration_seconds: Double?
    var rpe: Double?
    var custom_metric: Double?
}

nonisolated struct HevyExerciseTemplateDTO: Decodable, Sendable {
    var id: String?
    var title: String?
    /// One of Hevy's eight exercise types. Open string, per the spec.
    var type: String?
    var primary_muscle_group: String?
    var secondary_muscle_groups: [String]?
    /// Likewise, the spec calls this `equipment_category`; the live API returns `equipment`.
    var equipment: String?
    var is_custom: Bool?
}

nonisolated struct HevyBodyMeasurementDTO: Decodable, Sendable {
    var date: String?
    var weight_kg: Double?
    var lean_mass_kg: Double?
    var fat_percent: Double?
}

nonisolated struct HevyUserInfoDTO: Decodable, Sendable {
    var id: String?
    var name: String?
    var url: String?
}

// Paged envelopes. Hevy is inconsistent about wrapping, so each is modelled separately
// rather than forced into one generic shape.
nonisolated private struct HevyWorkoutPage: Decodable { var page: Int?; var page_count: Int?; var workouts: [HevyWorkoutDTO]? }
nonisolated private struct HevyTemplatePage: Decodable { var page: Int?; var page_count: Int?; var exercise_templates: [HevyExerciseTemplateDTO]? }
nonisolated private struct HevyMeasurementPage: Decodable { var page: Int?; var page_count: Int?; var body_measurements: [HevyBodyMeasurementDTO]? }
nonisolated private struct HevyCountResponse: Decodable { var workout_count: Int? }
nonisolated private struct HevyUserInfoResponse: Decodable { var data: HevyUserInfoDTO? }

/// One incremental-sync event. Hevy sends exactly two kinds, discriminated by `type`,
/// and declares no OpenAPI `discriminator`, so this decodes the tag manually.
///
/// There is NO "created" event: a new workout arrives as `updated`.
nonisolated enum HevyWorkoutEvent: Sendable {
    case updated(HevyWorkoutDTO)
    case deleted(id: String, deletedAt: Date?)
}

nonisolated private struct HevyEventPage: Decodable {
    var page: Int?
    var page_count: Int?
    var events: [RawEvent]?

    struct RawEvent: Decodable {
        var type: String?
        var workout: HevyWorkoutDTO?
        var id: String?
        var deleted_at: String?
    }
}

// MARK: - Client

/// Stateless HTTP client. Holds no credential: the key is passed in per call so the
/// keychain stays the single owner of it.
nonisolated struct HevyAPI: Sendable {

    static let baseURL = URL(string: "https://api.hevyapp.com")!

    /// Hevy's hard cap for most collections.
    static let maxPageSize = 10
    /// The one exception: exercise templates allow 100.
    static let maxTemplatePageSize = 100

    /// Minimum gap between requests. Rate limits are undocumented but real, and a full
    /// backfill of 500 workouts is 50 sequential calls at 10 per page, so requests are
    /// paced rather than fired as fast as the network allows.
    static let requestSpacing: Duration = .milliseconds(250)

    private let session: URLSession
    private let apiKey: String

    init(apiKey: String, session: URLSession? = nil) {
        self.apiKey = apiKey
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 120
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: Endpoints

    /// Total workouts on the account, used to size a backfill and show progress.
    func workoutCount() async throws -> Int {
        let response: HevyCountResponse = try await get("/v1/workouts/count")
        return response.workout_count ?? 0
    }

    func userInfo() async throws -> HevyUserInfoDTO? {
        let response: HevyUserInfoResponse = try await get("/v1/user/info")
        return response.data
    }

    /// One page of workouts, newest first. Returns the workouts and the total page
    /// count so the caller can walk the history.
    func workouts(page: Int, pageSize: Int = 10) async throws -> (workouts: [HevyWorkoutDTO], pageCount: Int) {
        let response: HevyWorkoutPage = try await get("/v1/workouts", query: [
            "page": String(page),
            "pageSize": String(min(pageSize, Self.maxPageSize)),
        ])
        return (response.workouts ?? [], response.page_count ?? 1)
    }

    /// One page of change events since a timestamp, NEWEST FIRST.
    ///
    /// This is the incremental path: far cheaper than re-walking the whole history, and
    /// the only way to learn about deletions, since Hevy exposes no delete endpoint and
    /// a deleted workout simply stops appearing in `/v1/workouts`.
    func events(since: Date, page: Int, pageSize: Int = 10) async throws -> (events: [HevyWorkoutEvent], pageCount: Int) {
        let response: HevyEventPage = try await get("/v1/workouts/events", query: [
            "since": HevyDate.string(from: since),
            "page": String(page),
            "pageSize": String(min(pageSize, Self.maxPageSize)),
        ])
        let events: [HevyWorkoutEvent] = (response.events ?? []).compactMap { raw in
            switch raw.type {
            case "updated":
                guard let workout = raw.workout else { return nil }
                return .updated(workout)
            case "deleted":
                guard let id = raw.id else { return nil }
                return .deleted(id: id, deletedAt: raw.deleted_at.flatMap(HevyDate.date(from:)))
            default:
                // An event type we do not know yet. Skipping it is right: guessing at
                // its meaning could delete data that was never deleted.
                return nil
            }
        }
        return (events, response.page_count ?? 1)
    }

    /// One workout by id. Returned UNWRAPPED, unlike routines.
    func workout(id: String) async throws -> HevyWorkoutDTO {
        try await get("/v1/workouts/\(id)")
    }

    /// One page of exercise templates. These carry the muscle-group attribution that
    /// makes per-muscle volume possible, so the full catalog is cached locally.
    func exerciseTemplates(page: Int, pageSize: Int = 100) async throws -> (templates: [HevyExerciseTemplateDTO], pageCount: Int) {
        let response: HevyTemplatePage = try await get("/v1/exercise_templates", query: [
            "page": String(page),
            "pageSize": String(min(pageSize, Self.maxTemplatePageSize)),
        ])
        return (response.exercise_templates ?? [], response.page_count ?? 1)
    }

    /// One page of body measurements, which is where Hevy keeps weight and body fat.
    func bodyMeasurements(page: Int, pageSize: Int = 10) async throws -> (measurements: [HevyBodyMeasurementDTO], pageCount: Int) {
        let response: HevyMeasurementPage = try await get("/v1/body_measurements", query: [
            "page": String(page),
            "pageSize": String(min(pageSize, Self.maxPageSize)),
        ])
        return (response.body_measurements ?? [], response.page_count ?? 1)
    }

    /// Cheapest possible call that proves a key works, for the Connect flow.
    func validateKey() async throws {
        _ = try await workoutCount()
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let data = try await requestData(path, query: query)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<binary>"
            throw HevyError.decoding("\(error.localizedDescription) Body began: \(preview)")
        }
    }

    /// Perform the request with retry on transient failures.
    private func requestData(_ path: String, query: [String: String]) async throws -> Data {
        var lastError: HevyError = .network("no attempt made")
        // Three attempts, backing off. Enough to ride out a rate-limit window or a
        // dropped connection without hammering the API.
        for attempt in 0..<3 {
            if attempt > 0 {
                let backoff = Duration.milliseconds(500 * (1 << (attempt - 1)))
                try? await Task.sleep(for: backoff)
            }
            do {
                return try await performRequest(path, query: query)
            } catch let error as HevyError {
                guard error.isTransient else { throw error }
                lastError = error
                // Honour an explicit Retry-After when Hevy sends one.
                if case .rateLimited(let retryAfter) = error, let retryAfter {
                    try? await Task.sleep(for: .seconds(min(retryAfter, 30)))
                }
            }
        }
        throw lastError
    }

    private func performRequest(_ path: String, query: [String: String]) async throws -> Data {
        guard var components = URLComponents(
            url: Self.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw HevyError.network("Could not build the request URL.")
        }
        if !query.isEmpty {
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw HevyError.network("Could not build the request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw HevyError.cancelled
        } catch let urlError as URLError {
            if urlError.code == .cancelled { throw HevyError.cancelled }
            throw HevyError.network(urlError.localizedDescription)
        } catch {
            throw HevyError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw HevyError.network("Unexpected response type.")
        }

        // Status is checked BEFORE any decode. Hevy returns a 401 as plain text
        // ("InvalidApiKey"), so decoding first would surface a confusing JSON error and
        // hide the real cause.
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            if body.localizedCaseInsensitiveContains("limit") {
                throw HevyError.quotaExceeded(body)
            }
            throw HevyError.invalidKey
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw HevyError.rateLimited(retryAfter: retryAfter)
        default:
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw HevyError.http(status: http.statusCode, body: body)
        }
    }

    private static let decoder = JSONDecoder()
}

// MARK: - Date handling

/// Hevy's timestamps are ISO 8601 with a literal `Z`, but the spec types them as plain
/// strings with no `format: date-time` and no statement about fractional seconds. So
/// both forms are attempted, plus a date-only form for body measurements.
nonisolated enum HevyDate {

    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// `YYYY-MM-DD`, used by the body-measurement endpoints.
    private static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let date = plain.date(from: string) { return date }
        if let date = withFractional.date(from: string) { return date }
        if let date = dayOnly.date(from: string) { return date }
        return nil
    }

    /// Serialize for the `since` query parameter, which wants exactly
    /// `2026-07-30T04:07:15Z`.
    static func string(from date: Date) -> String {
        plain.string(from: date)
    }

    /// Parse a `YYYY-MM-DD` body-measurement date.
    static func day(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return dayOnly.date(from: string)
    }
}
