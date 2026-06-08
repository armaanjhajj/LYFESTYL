//
//  LocalStore.swift
//  LYFESTYL
//
//  Local, offline-safe cache of entries (CLAUDE.md §4.2/§4 polish). Supabase
//  stays authoritative; this is the safety net so an entry is NEVER lost if the
//  model or network fails, and so the Log renders instantly and offline.
//
//  A file-based JSON store (one source of truth on disk), guarded by an actor.
//

import Foundation

actor LocalStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "lyfestyl_entries.json") {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(filename)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [JournalEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([JournalEntry].self, from: data)) ?? []
    }

    func save(_ entries: [JournalEntry]) {
        guard let data = try? encoder.encode(entries) else { return }
        // Atomic write so a crash mid-write can't corrupt the cache.
        try? data.write(to: fileURL, options: [.atomic])
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
