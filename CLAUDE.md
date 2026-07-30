# CLAUDE.md — LYFESTYL

LYFESTYL is a native iOS health-journaling app. The user dumps vague thoughts (typed or voice) and the app turns them into structured life data (NUTRITION / ACTIVITY / SLEEP / HEALTH / MIND / SOCIAL, ranked EXCELLENT to AWFUL; SOCIAL carries the specific relationship as a subtag) using Apple's on-device Foundation Models framework. Two surfaces: a zero-friction journal for input and a clean log/history for insights and trends. You have wide latitude on everything else, just follow these rules:

1. **Look first-party Apple.** The reference bar is Apple Health and Fitness. Achieve this by using real native SwiftUI components, never by rebuilding them (`.searchable`, `NavigationStack`, `TabView`, `.sheet`, native buttons, `List`, `.refreshable`, Swift Charts, `SignInWithAppleButton`, etc).

2. **Never hallucinate APIs.** If you aren't certain a symbol exists in the iOS 26 SDK, stop and verify or use a known-good documented alternative. There is no `.liquidGlass()` or `LiquidGlassView`, the real APIs are `.glassEffect()`, `GlassEffectContainer`, `.glassEffectID()` and the `.glass`/`.glassProminent` button styles. Glass goes on chrome, not content.

3. **Foundation Models, Guided Generation.** Process every entry on-device with `@Generable` structs and `@Guide` annotations via `LanguageModelSession.respond(generating:)`. No JSON parsing. Check `SystemLanguageModel.default.availability` and handle unavailability gracefully without losing the raw entry.

4. **CloudKit is the backend**, the source of truth for all persistent data (Apple's CloudKit private database, first-party, auto scoped to the user's iCloud account). No external services, no secrets. Local cache is fine but CloudKit stays authoritative.

5. **Sign in with Apple only**, via the native button, gating a CloudKit-backed app (the signed-in iCloud account owns the private database).

6. **Voice input:** record with AVFoundation, transcribe on-device (`SpeechAnalyzer`/`SpeechTranscriber`, or `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` if unsure), then feed the same pipeline as typed entries. Add the required Info.plist permission keys.

7. **Color Scheme only**, defined once and referenced everywhere. No raw system colors.

8. **SF Pro only** (not Rounded, not Mono). Titles and headers and the logo are ALL CAPS black weight.

9. **Native-first dependencies.** Target iOS 26, Swift 6, `@Observable`, async/await. No third-party packages unless truly necessary. Never commit secrets; use a gitignored config with a committed example template.

10. **Ship quality, stay in scope.** Build the two surfaces and the pipeline well (empty states, errors, polish).Keep the build green, commit in logical increments, document setup and the CloudKit record schema in the README.

11. **NO EM DASHES**