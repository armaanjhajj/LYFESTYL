# CLAUDE.md - LYFESTYL

LYFESTYL is a free, native iOS calorie tracker that runs entirely on device. The whole app is one camera screen: snap a meal, Apple's on-device Foundation Models itemizes every food with calories, macros and a confidence level, and a drawer lets you fix anything and log it. Top left is account and settings, top right is the dashboard (daily totals, history, habit flags). Speed and ease beat precision. You have wide latitude on everything else, just follow these rules:

1. **Look first-party Apple.** The reference bar is Apple Health, Fitness and Camera. Achieve this by using real native SwiftUI components, never by rebuilding them (`NavigationStack`, `.sheet` with detents, `.searchable`, `List`/`Form`, native buttons, Swift Charts, `PhotosPicker`, `ShareLink`, etc).

2. **Never hallucinate APIs.** If you aren't certain a symbol exists in the iOS 27 SDK, stop and verify it in the SDK's `.swiftinterface` or use a known-good documented alternative. There is no `.liquidGlass()` or `LiquidGlassView`; the real APIs are `.glassEffect()`, `GlassEffectContainer`, `.glassEffectID()` and the `.glass`/`.glassProminent` button styles. Glass goes on chrome, not content.

3. **Foundation Models, Guided Generation.** Photos go to `SystemLanguageModel.default` as an `Attachment` (iOS 27) and come back through `@Generable` structs with `@Guide` annotations via `LanguageModelSession.streamResponse/respond(generating:)`. No JSON parsing. Read printed text with Vision first: the product is identified behind the scenes but shown with a plain name ("Protein Shake"), and numbers on its label replace the model's estimate (`LabelFacts`). Check `availability` and `capabilities.contains(.vision)`, and when the model can't help, fall back to search and manual entry rather than blocking.

4. **No stored images, ever.** Frames live in memory from the shutter until log or dismiss. Nothing is written to disk or the photo library. Keep stored records as small as possible.

5. **Apple's kits are the backend.** Meals are SwiftData mirrored to the CloudKit private database (the source of truth across devices); goals sync through iCloud key-value storage; nutrition can be written to HealthKit. No external services, no accounts, no secrets. The iCloud account is the identity.

6. **Color Scheme only**, defined once in `SolarizedPalette.swift` and referenced everywhere. No raw system colors.

7. **SF Pro only** (not Rounded, not Mono). Titles and headers and the logo are ALL CAPS black weight (`sectionHeader()`, `NavHeaderTitle`, `capsNavigationTitle`).

8. **Native-first dependencies.** Target iOS 27, Swift 6, `@Observable`, async/await. No third-party packages unless truly necessary.

9. **Minimal text.** Logging is just a food. No meal types, no time pickers, no explanatory footers; record what can be recorded silently.

10. **Ship quality, stay in scope.** One camera, one drawer, one dashboard, one settings page, done well (empty states, errors, permissions, accessibility, haptics). Keep the build green and `Verification/run.sh` passing, commit in logical increments, keep the README's setup and CloudKit schema current.

11. **NO EM DASHES**
