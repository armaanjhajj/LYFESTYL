# DECISIONS.md — LYFESTYL

Architecture & product decisions, with rationale, so the morning review is fast. UI rules in `CLAUDE.md` are law; everything here lives within them.

---

## 1. Platform / toolchain
- **Target:** iOS 26.0+ (built & verified against the iOS 26.5 SDK, Xcode 26.5, Swift 6.3).
- **Language version:** the project ships `SWIFT_VERSION = 5.0` with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` + `SWIFT_APPROACHABLE_CONCURRENCY = YES`. We keep these (MainActor-by-default is exactly what a SwiftUI app wants) and write modern Swift 6-style code (`@Observable`, async/await, actors) on top. We did **not** force `-swift-version 6` strict-concurrency because the Supabase SDK + our actors compile clean under approachable concurrency and flipping it risks churn for no user-visible gain.
- **Force dark mode app-wide** (`.preferredColorScheme(.dark)` at the root). Solarized Dark is the only palette; there is no light variant.

## 2. Why these APIs (all verified against the on-disk SDK before use)
The single biggest failure mode called out in `CLAUDE.md` is hallucinated iOS 26 symbols. Before writing any code we read the actual `.swiftinterface` files in the iOS 26.5 SDK and pinned exact signatures:
- **FoundationModels** — `SystemLanguageModel.default.availability`, `LanguageModelSession(model:tools:instructions:)`, `respond(to:generating:options:)`, `streamResponse(to:generating:)`, `@Generable`, `@Guide`, `GenerationGuide.anyOf/.range/...`, `GenerationOptions(sampling:temperature:)`. Verified.
- **Speech** — `SpeechTranscriber(locale:preset:)`, `SpeechAnalyzer(modules:)`, `AnalyzerInput(buffer:)`, `analyzer.start(inputSequence:)`, `transcriber.results` (AsyncSequence of `Result` with `.text: AttributedString`), `AssetInventory` for model download. Verified.
- **Liquid Glass** — `.glassEffect(_:in:)`, `Glass.regular/.clear` + `.tint/.interactive`, `GlassEffectContainer`, `.glassEffectID(_:in:)`, and the `.glass` / `.glassProminent` button styles. Verified (in SwiftUICore).
- **Sign in with Apple** — `SignInWithAppleButton(_:onRequest:onCompletion:)` + `.signInWithAppleButtonStyle`, `ASAuthorizationAppleIDCredential.identityToken/email/fullName/user`. Verified.
- **Swift Charts** — present in SDK; standard `Chart { ... }` marks.
- **Supabase Swift SDK** — the only off-device dependency; verified against official docs (see README) rather than the SDK (not on disk until resolved).

## 3. The on-device pipeline (the heart)
- **Guided Generation, never JSON parsing.** Output is a `@Generable struct EntryBreakdown` containing `[CategoryInsight]`. The model returns typed Swift values directly via `session.respond(to:generating: EntryBreakdown.self)`.
- **Determinism for trend comparability.** We call the model with `GenerationOptions(sampling: .greedy)` so the same entry yields stable estimates — important because LYFESTYL's value is *trends over time*.
- **Availability handling.** `SystemLanguageModel.default.availability` is checked up front and surfaced as a real UI state: `available`, `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady` (downloading). We **never** lose the raw entry — it is saved first, then enriched. If the model is unavailable the entry is stored raw with `status = pending` and re-processed automatically when the model becomes available.
- **Focused prompt.** The ~3B model is tuned for extraction/classification, not trivia, so instructions are tight: "You are a health-journaling analyst. Break the entry into the categories actually present. Estimate tangible numbers. Rank each category." Full text in `InsightEngine.swift`.

### Scoring / estimation system (proprietary, versioned: `schemaVersion = 1`)
- **Four categories:** `NUTRITION`, `ACTIVITY`, `SLEEP`, `HEALTH`. One entry can populate several; only categories actually mentioned are emitted.
- **5-point rank:** `EXCELLENT > GOOD > OKAY > BAD > AWFUL`, mapped to a numeric `rankScore` 5→1 for trend math, and to palette colors per `CLAUDE.md` (EXCELLENT→green, GOOD→cyan, OKAY→yellow, BAD→orange, AWFUL→red).
- **Tangible estimates** are modeled as *optional typed fields* on `CategoryInsight` rather than free-form key/value pairs. Free-form labels ("kcal" vs "calories" vs "energy") destroy trendability; fixed columns guarantee a clean time series. Fields: `calories, proteinGrams, carbsGrams, fatGrams, waterOunces` (nutrition), `activeMinutes, distanceMiles` (activity), `sleepHours` (sleep). HEALTH is qualitative (rank + detail). All optional — the model fills only what's relevant.
- **Rank rubric** is spelled out in the prompt so ranks mean the same thing across entries and over time (e.g. SLEEP: EXCELLENT ≈ 7.5–9h restful; AWFUL ≈ <4h or badly disrupted). This is what makes consistent journaling produce a meaningful trend line.

## 4. Data model & storage
- **Supabase is authoritative.** Three tables: `profiles`, `entries`, `insights` (one entry → many insights, one per category). Insights are stored relationally with metric **columns** so trend queries are trivial `select` + group-by. Full SQL is in `README.md` and `supabase/schema.sql`.
- **Local cache for offline/optimistic UI** (allowed by `CLAUDE.md` §4.2). A file-based JSON store (`LocalStore`, actor-guarded) in Application Support mirrors entries+insights for instant, offline-capable rendering and is reconciled against Supabase on launch/refresh. We deliberately did **not** use SwiftData/Core Data as a source of truth.
- **Offline-safe entry handling.** Submit flow: (1) write entry to local cache immediately (never lost), (2) enqueue a sync+process job, (3) push raw entry to Supabase, (4) run the on-device breakdown, (5) push insights + mark processed. Any step can fail (no network, model busy/unavailable) without data loss; the `EntryQueue` actor persists pending jobs and retries on app-foreground, connectivity return, and model-availability change.

## 5. Auth
- **Sign in with Apple only**, native `SignInWithAppleButton`, wired to Supabase via `auth.signInWithIdToken(.init(provider: .apple, idToken:, nonce:))`.
- **Nonce flow (security-critical):** generate a random raw nonce → SHA256 → set the **hashed** nonce on the Apple request → pass the **raw** nonce to Supabase. This binds the Apple assertion to our request and is required for Supabase to validate the token.
- Session persisted by the SDK; app is gated behind auth; sign-out and token refresh handled by the SDK's auth state stream.

## 6. Secrets
- `LYFESTYLE/Secrets.plist` (gitignored, bundled) holds `SUPABASE_URL` + `SUPABASE_PUBLISHABLE_KEY`. Committed template: `Secrets.example.plist`.
- The **publishable** key is client-safe and intentionally the only key in the app. The **secret** key is never stored in the app (server-only). If the plist is missing, the app shows a clear "configuration needed" state instead of crashing (`// TODO: user provides`).

## 7. Open forks resolved by default (flag if you disagree)
- **Metrics as fixed columns, not free-form pairs** — chosen for trendability (see §3). Reversible: schema is versioned.
- **File-based cache over SwiftData** — chosen for an unambiguous "Supabase is the source of truth" story and zero model duplication.
- **Two tabs (Journal, Log)** via `TabView`, Journal first — matches the "open → type immediately" thesis.
- **Determinism (`.greedy`) over creative variety** — chosen because this is a measurement tool, not a chat toy.
- **New publishable/secret key format** assumed accepted by `SupabaseClient(supabaseKey:)` (it is sent as the `apikey`/bearer header exactly like the legacy anon key). Verified via the Supabase Swift verification pass.
