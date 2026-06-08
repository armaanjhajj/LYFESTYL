# CLAUDE.md — LYFESTYL

You are building **LYFESTYL**, a native iOS health-journaling app. This file is law for UI and platform decisions. For product logic and architecture you have latitude — figure things out, make good decisions, keep building. But the UI rules below are **non-negotiable** and the most common way you fail. Read them, internalize them, and self-check against them on every commit.

---

## 0. THE ONE RULE

**This app must be indistinguishable from a native, first-party Apple app.** Every pixel should look like Apple shipped it. If a user could tell this was a third-party app from the UI alone, you have failed.

You achieve this NOT by recreating Apple's look, but by using Apple's actual native components so the look comes for free. You are assembling Apple's parts, not imitating them. The reference bar for readability and layout is **Apple Health** and **Fitness** — clean, calm, lots of breathing room, system materials, no clutter.

---

## 1. WHAT THE APP IS (so your decisions stay coherent)

LYFESTYL lets a user track their lifestyle with **ridiculously easy input**. The thesis: the user dumps vague, unstructured thoughts — typed or spoken — and the app does the work of turning that into structured, trackable health data using Apple's **on-device Foundation Models** framework. Fully offline, free, private, no API keys.

Two surfaces, that's it:

1. **JOURNAL (entry surface)** — Open the app, and you can immediately start writing or tap a voice button and talk like a voice memo. Multiple entries per day, all auto-stamped to the current day. Zero friction. The whole point is the user types/says something like *"woke up sore in my back, went to the gym for an hour and ran a mile, ate like shit — had a donut and pizza"* and never has to fill in a single structured field.

2. **LOG / HISTORY (insight surface)** — Where the user sees what the model produced: each entry broken down into structured components, plus trends over time. Readable and clean like Apple Health.

### The pipeline (the heart of the app)
Every entry (text or transcribed voice) is processed **on-device** by the **Foundation Models** framework (`import FoundationModels`), Apple's ~3B-parameter on-device LLM. It runs fully offline, costs nothing, requires no API key, and keeps all data private. The model breaks each entry into these four categories:

- **NUTRITION**
- **ACTIVITY**
- **SLEEP**
- **HEALTH**

For each relevant category, the model returns tangible, modular, trackable insights: caloric/macro estimates, durations, distances, a qualitative rank on a **5-point scale (EXCELLENT / GOOD / OKAY / BAD / AWFUL)**, and any specifics worth logging. A single entry can populate multiple categories. Vague input is expected — the model estimates and infers. Design the schema and prompt so consistent journaling produces meaningful trends over time.

**Use Guided Generation, not string parsing.** Define your output as `@Generable` Swift structs with `@Guide` annotations so the model returns typed Swift values directly — no JSON parsing, no fragile prompt formatting. This is the entire reason to use this framework; do not have it emit raw JSON and parse it yourself.

```swift
import FoundationModels

@Generable
struct EntryBreakdown {
    @Guide(description: "Categories this entry touches")
    let categories: [CategoryInsight]
}

@Generable
struct CategoryInsight {
    @Guide(.anyOf(["NUTRITION", "ACTIVITY", "SLEEP", "HEALTH"]))
    let category: String
    @Guide(.anyOf(["EXCELLENT", "GOOD", "OKAY", "BAD", "AWFUL"]))
    let rank: String
    @Guide(description: "Short human-readable summary of what was logged")
    let summary: String
    // add typed estimate fields as you design them: calories, durationMinutes, distanceMiles, etc.
}
```

Run it through `SystemLanguageModel` + a `LanguageModelSession`, using `respond(generating:)` for the typed result (and optionally `streamResponse`/`PartiallyGenerated` to animate insights into the UI as they generate). Check `SystemLanguageModel.default.availability` first and handle the unavailable case gracefully (device without Apple Intelligence, model still downloading) — show a clear state, never crash, never lose the raw entry. The ~3B model is tuned for focused tasks like classification and extraction, not world trivia, so keep prompts focused; this app's use case fits it well.

You own the design of this proprietary scoring/estimation system. Make it sensible, consistent, and trend-friendly. Version your schema so future entries stay comparable.

---

## 2. NATIVE-ONLY UI — NON-NEGOTIABLE

### 2.1 Use the real component. Never rebuild it.
Before building ANY UI element, check whether SwiftUI already provides it. It almost always does. Use the native one. Things you must NEVER hand-roll:

- **Search bars** → `.searchable(text:)` on a `List`/`ScrollView`/`NavigationStack`. NEVER build a custom `TextField` styled to look like a search bar. NEVER fake the magnifying glass, the gray capsule, the cancel button, or the scroll-to-reveal behavior. Native `.searchable` does all of this and gets Liquid Glass automatically.
- **Navigation bars / titles** → `NavigationStack` + `.navigationTitle()` + `.toolbar { }`. Never build a custom top bar with an HStack.
- **Tab bars** → `TabView`. Never build a custom bottom bar.
- **Sheets / modals** → `.sheet()`, `.fullScreenCover()`, `.presentationDetents()`. Never build a custom slide-up panel.
- **Buttons** → `Button` with native styles (`.borderedProminent`, `.bordered`, `.glass`, `.glassProminent`). Never build a `Rectangle` + `.onTapGesture`.
- **Lists / grids** → `List`, `LazyVGrid`, `LazyVStack`. Native swipe actions, section headers, separators.
- **Pull to refresh** → `.refreshable { }`. Never a custom spinner-on-drag.
- **Context menus** → `.contextMenu { }`. **Alerts/confirmations** → `.alert()`, `.confirmationDialog()`.
- **Pickers, toggles, steppers, sliders, date pickers, menus** → the native ones, always.
- **Charts / trends** → use **Swift Charts** (`import Charts`). Never hand-draw graphs with `Path`/`Canvas` for standard chart types.
- **Sign in with Apple** → native `SignInWithAppleButton` from `AuthenticationServices`. Never a custom black button with an Apple logo.

### 2.2 Liquid Glass — use it, don't invent it
Glass goes on **chrome** (navigation, toolbars, floating controls, the voice button), never on **content**. The real API is `.glassEffect()`, `GlassEffectContainer`, `.glassEffectID()`, and the `.glass` / `.glassProminent` button styles. That's it.

### 2.3 Don't hallucinate glass
There is no "frosted glass view," no custom `LiquidGlassView`, no `.liquidGlass()` modifier. If you reach for anything by that name, you are hallucinating — STOP. Use `.glassEffect()`, `GlassEffectContainer`, `.glassEffectID()`, `.glass`/`.glassProminent`. Don't stack glass on glass; wrap multiple glass elements in a `GlassEffectContainer`.

### 2.4 If an API might not exist, STOP
If you are not certain an API, modifier, type, or initializer exists in the iOS 26 SDK, do not invent it. Stop, and either verify against the real SDK/Apple docs or pick a known-good native alternative. Hallucinated APIs are a top failure mode — a hallucinated symbol that compiles wrong wastes a whole build cycle. Prefer the boring, documented path.

---

## 3. DESIGN TOKENS — EXACT, DO NOT DEVIATE

### 3.1 Color — Dark Solarized ONLY
The entire app uses the **Solarized Dark** palette. Define these once in an `Asset Catalog` color set (or a single `Color` extension) and reference everywhere. Never use raw `Color.blue`, system grays for fills, or off-palette hexes.

```
Base / backgrounds
  base03  #002B36   ← primary background
  base02  #073642   ← elevated surfaces / cards / grouped sections
Content / text
  base01  #586E75   ← secondary / muted text, separators
  base00  #657B83   ← body text (lower emphasis)
  base0   #839496   ← primary body text
  base1   #93A1A1   ← emphasized text
Accents (use sparingly, semantically)
  yellow  #B58900
  orange  #CB4B16
  red     #DC322F   ← AWFUL / BAD signals
  magenta #D33682
  violet  #6C71C4
  blue    #268BD2   ← primary accent / interactive tint
  cyan    #2AA198   ← GOOD / positive signals
  green   #859900   ← EXCELLENT / positive signals
```

Map the 5-point scale to palette accents consistently (suggested: EXCELLENT→green, GOOD→cyan, OKAY→yellow, BAD→orange, AWFUL→red) and reuse that mapping everywhere a rank appears. Set the app's accent/tint to `blue #268BD2`. Force dark mode app-wide — there is no light variant.

### 3.2 Type — SF Pro ONLY
- **SF Pro** (the standard, normally-spaced system font). **NOT** SF Pro Rounded, **NOT** SF Mono, **NOT** any condensed/expanded width. Just the default system font — which in SwiftUI means using `.font(.title)`, `.font(.body)`, etc. on the default font. Do not load custom fonts. Do not set a custom letter-spacing/tracking except where ALL-CAPS headers benefit from slight positive tracking (optional, subtle).
- **Titles, logo, headers, section headers, category labels** → **ALL CAPS**, **black weight** (`.fontWeight(.black)`). e.g. `Text("NUTRITION").font(.title2).fontWeight(.black)` with `.textCase(.uppercase)`.
- **Everything else** (body, entry text, captions, values) → normal SF Pro, regular/medium weight, normal casing.

### 3.3 The logo
A square, two-line stacked block of four-letter words, **black weight SF Pro, all caps**, tightly stacked so it reads as a square block:

```
LYFE
STYL
```

Build it as a reusable SwiftUI view: two `Text` lines, `.fontWeight(.black)`, `.textCase(.uppercase)`, tight `lineSpacing`/negative vertical padding so the two rows hug into a block. Monospaced-looking alignment should come from the block layout, NOT from using a mono font — the font stays normal SF Pro.

---

## 4. ARCHITECTURE & DEPENDENCIES

### 4.1 Native-first, always
Use Apple native frameworks instead of third-party libraries wherever one exists. SwiftUI, Swift Charts, AuthenticationServices, AVFoundation, the Speech framework, etc. Add a third-party Swift package ONLY if there is genuinely no native option and it's essential — and prefer the official Supabase Swift SDK for Supabase access.

### 4.2 The ONLY external service
The user will provide credentials for exactly one thing: **Supabase**. Everything else — including the entire AI breakdown pipeline — is Apple-native and on-device.

1. **Supabase** — ALL persistent storage. User data, journal entries, the model's structured breakdowns, trends. Use the official `supabase-swift` SDK. Design a clean schema (e.g. `entries`, `insights`/`breakdowns`, per-category metrics) that supports trend queries. Do NOT use Core Data / SwiftData as the source of truth — Supabase is the backend. A local cache for offline/optimistic UI is fine if you keep Supabase authoritative.
2. **Foundation Models** — the entry-breakdown engine, fully on-device (see Section 1). No key, no network, no cost. This is NOT an external service; it ships with iOS 26.

### 4.3 Auth
**Sign in with Apple** only, via native `SignInWithAppleButton`. Wire it to Supabase Auth (Supabase supports Apple as an OAuth/identity provider). Persist session; gate the app behind auth; handle sign-out and token refresh.

### 4.4 Secrets & config
No secret (Supabase keys) is ever committed. Use a gitignored config file (e.g. `Secrets.xcconfig` or a `Secrets.plist` excluded via `.gitignore`) and read at runtime, OR document clearly where the user pastes them. Create a `Secrets.example.*` template with placeholder values that IS committed, so setup is obvious. Add a clear `// TODO: user provides` marker anywhere a credential is required. (There is no AI key — Foundation Models needs none.)

### 4.5 Voice input
Use the iOS 26 **`SpeechAnalyzer` + `SpeechTranscriber`** APIs (the modern, on-device, async/await successor to `SFSpeechRecognizer`) for transcription. Record with AVFoundation, transcribe on-device, then feed the resulting text through the same Foundation Models pipeline as typed entries. Add the required `Info.plist` keys (`NSSpeechRecognitionUsageDescription`, `NSMicrophoneUsageDescription`). If you cannot verify a `SpeechAnalyzer` symbol, fall back to documented `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` rather than inventing API. The voice button itself is a native glass button — do not build a custom mic UI from primitives; a simple recording state with native controls is enough. (Note: the whole app is now fully on-device end to end — transcription and breakdown both — so a voice entry never leaves the phone except to sync to Supabase.)

### 4.6 Project hygiene
- Target **iOS 26**. Swift 6, `@Observable`, async/await, actor-based concurrency where it fits.
- Keep a sane structure (Features/, Models/, Services/, DesignSystem/). One source of truth for design tokens.
- Commit in logical increments with clear messages. Keep the build green; if something won't compile, fix it before moving on.
- Write a `README.md` documenting setup (where to paste Supabase creds, how to run; note the AI runs on-device with no key) and the Supabase schema (provide the SQL).
- If you make a meaningful product/architecture decision, note it briefly in a `DECISIONS.md` so it's reviewable.

---

## 5. SCOPE & AUTONOMY

You have wide latitude on everything not pinned down above: schema design, the exact insight model, trend visualizations, the scoring math, edge cases, empty states, onboarding, error handling, micro-interactions. Use good judgment, build it well, and don't stop at "good enough" — polish it to shippable quality. When the UI rules and your own preferences conflict, the UI rules win.

Do NOT, however, expand scope into things not asked for (no social features, no extra integrations, no accounts beyond Sign in with Apple). Build the two surfaces and the pipeline, beautifully and completely.

---

## 6. SELF-CHECK BEFORE EVERY UI COMMIT

Ask yourself, in order:
1. Does a native SwiftUI component already do this? (If yes, I must use it.)
2. Am I styling a primitive to look like a system control? (If yes, STOP — find the native control.)
3. Am I applying glass to content instead of chrome? (If yes, remove it.)
4. Am I stacking glass on glass? (If yes, use a `GlassEffectContainer`.)
5. Is every color from the Solarized Dark palette? (No raw system colors, no off-palette hexes.)
6. Is the font default SF Pro — not Rounded, not Mono? Are titles/headers/logo ALL CAPS + black weight?
7. Does this still work with Reduce Transparency + Reduce Motion on? (Must be yes.)
8. Am I about to use an API I'm not certain exists? (If yes, STOP and verify or pick a known-good native alternative.)

If any answer is wrong, do not write the code. Fix the approach first.