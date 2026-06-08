//
//  SupabaseConfig.swift
//  LYFESTYL
//
//  Reads the gitignored Secrets.plist and builds the single shared
//  SupabaseClient. Supabase is the ONLY external service (CLAUDE.md §4.2). If
//  the plist is missing or still has placeholder values, `isConfigured` is false
//  and the app shows a clear "configuration needed" state instead of crashing.
//
//  The client uses the PUBLISHABLE key (client-safe). The secret key is never
//  stored in the app.
//

import Foundation
import Supabase

enum SupabaseConfig {
    struct Secrets {
        let url: URL
        let key: String
    }

    /// Parsed secrets, or nil if not configured. `// TODO: user provides` —
    /// values come from LYFESTYLE/Secrets.plist (see Secrets.example.plist).
    static let secrets: Secrets? = {
        guard
            let path = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: path),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let urlString = (dict["SUPABASE_URL"] as? String)?.trimmingCharacters(in: .whitespaces),
            let key = (dict["SUPABASE_PUBLISHABLE_KEY"] as? String)?.trimmingCharacters(in: .whitespaces),
            !urlString.isEmpty, !key.isEmpty,
            !urlString.contains("YOUR-PROJECT"), !key.contains("REPLACE_ME"),
            let url = URL(string: urlString)
        else {
            return nil
        }
        return Secrets(url: url, key: key)
    }()

    static var isConfigured: Bool { secrets != nil }

    /// The one shared client for the app lifetime (the SDK is Sendable).
    static let client: SupabaseClient? = {
        guard let secrets else { return nil }
        return SupabaseClient(supabaseURL: secrets.url, supabaseKey: secrets.key)
    }()
}
