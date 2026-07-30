# LYFESTYL

A native iOS 26 health-journaling app. Log a thought — typed or spoken — and the
app helps you **organize** it: pick what you're logging (Nutrition, Activity,
Sleep, Health, Mind, Social) and answer a couple of quick, tappable questions, or
just free-write and let Apple's **on-device Foundation Models** quietly file it
under one category behind the scenes. No grades, no scores, no guessed numbers —
the app reflects what you logged, it doesn't judge it. Fully offline AI, no API
keys, no cost, private by design. Your history syncs through your own private
**iCloud** account (Apple CloudKit) so you can watch your activity build, no
third-party server involved.

```
LYFE
STYL
```

---

## Screens

| Onboarding | Journal | Log |
| --- | --- | --- |
| ![Onboarding](Screenshots/01-onboarding.png) | ![Journal](Screenshots/02-journal.png) | ![Log](Screenshots/03-log.png) |

| Entry detail | Trends |
| --- | --- |
| ![Entry detail](Screenshots/04-entry-detail.png) | ![Trends](Screenshots/05-trends.png) |

---

## What it does

- **Journal** — tap **+** and pick what you're logging from a fluid category menu,
  or choose **Free write**. Picking a category opens a short, **skippable** guided
  flow: a couple of tappable questions (with a free-text option) that help you
  organize the entry. Or drop into a calm, full-screen **voice mode**: a living orb
  pulses in time with your voice while it transcribes. Multiple frictionless entries
  per day, auto-stamped to today. Transcription is **entirely on-device**
  (`SpeechTranscriber`); nothing is sent anywhere.
- **Quiet AI** — a free-written entry runs through Apple's on-device
  **Foundation Models** with **Guided Generation** (`@Generable` / `@Guide`), which
  returns a typed Swift struct (no JSON parsing). Its only job is to **file the
  entry under one category and give it a clean title** — no ranking, no judgment,
  no estimated numbers. Guided entries skip the model entirely (you already told it
  what you're logging).
- **Log** — a clean, Apple-Health-style history where each entry is colored and
  classed by its single category, with your organized answers laid out in detail,
  plus search and **Trends** over time (Swift Charts).
- **ACTIVITY workout tracker** — a searchable exercise library (~190 movements,
  each tagged with up to 2 primary + 2 accessory muscle groups). Log a workout by
  picking sets/reps/weight, by just naming the movement, or by free-writing the
  session and letting the on-device model parse it into structured exercises.
- **STYL — "what you've been logging"** — a calm activity surface: how often each
  category was logged, current streaks, recent entries, your measured Apple
  Health lane, a muscle-balance read of what's been trained recently and what's
  gone light, and an on-device "suggest a session" that fills the gaps. Neutral by
  design — no standings, no scores.
- **Apple Health (measured)** — connect HealthKit and your real, *measured*
  activity, heart, and sleep data appears in its own clearly-attributed lane on
  STYL — the only place an actual number is shown. An empty Health store (no watch,
  no data) is a normal state and the lane is simply omitted.

Nothing about the entry leaves the device until you've saved it. The on-device AI
needs no key, HealthKit is read on-device, and **there is no external service at
all**. Persistence and sync run entirely through your own private Apple CloudKit
database, gated by Sign in with Apple.

---

## Requirements

- **Xcode 26+** and the **iOS 26 SDK**.
- An iPhone (or simulator) on **iOS 26**. The on-device classification of
  free-written entries requires a device with **Apple Intelligence** enabled;
  without it the app still saves entries (and guided, category-picked entries work
  fully), filing free-writes automatically once the model is available.
- An **iCloud account** signed in on the device or simulator (for CloudKit sync).
  No third-party account, no server, and nothing to sign up for.

---

## Setup

There are **no secrets to configure**. Everything runs on first-party Apple
frameworks, so setup is entirely capabilities in Xcode.

### 1. Enable the app's capabilities

In Xcode, select the `LYFESTYLE` target → **Signing & Capabilities** and confirm
these are present (already declared in `LYFESTYLE/LYFESTYLE.entitlements`, but a
real device build needs your Apple Developer team enabled for each):

| Capability | Purpose |
| --- | --- |
| **iCloud → CloudKit** | container `iCloud.Moments.LYFESTYLE`, the private database that stores every entry |
| **Sign in with Apple** | gates the app; the signed-in iCloud account owns the data |
| **HealthKit** | read-only, powers the measured lane on STYL |

The Simulator runs CloudKit and Sign in with Apple without extra provisioning as
long as it's signed into an iCloud account.

### 2. The CloudKit schema

Nothing to create by hand. CloudKit auto-creates the `Entry` record type (and its
fields) in the **Development** environment the first time the app saves an entry.
See [CloudKit schema](#cloudkit-schema) below for the field list. When you're ready
to ship, deploy the schema from Development to Production in the
[CloudKit Console](https://icloud.developer.apple.com/dashboard/).

### 3. Build & run

Open `LYFESTYLE.xcodeproj` in Xcode and run on an iOS 26 simulator or device
signed into iCloud. There are no external Swift packages to resolve for
persistence, everything is `CloudKit`/`CloudKit.framework` from the SDK.

---

## Architecture

```
LYFESTYLE/
├── DesignSystem/      Solarized palette, type helpers, logo, InsightCategory, shared components
├── Models/            JournalEntry (+ EntryField), CategoryQuestionTemplate, Trends,
│                      Workout / Exercise models + @Generable EntryClassification
├── Services/          InsightEngine (Foundation Models), SpeechService (on-device voice),
│                      CloudKitService (CRUD against the private database),
│                      AuthManager (Sign in with Apple), LocalStore (offline cache),
│                      JournalStore (pipeline orchestrator)
└── Features/          Root · Auth · Journal · Log · Trends · Search · Settings
```

- **Quiet on-device AI** — `InsightEngine` checks `SystemLanguageModel.default.availability`
  and runs each free-written entry through a focused `LanguageModelSession` with
  greedy sampling. Its only output is the typed `EntryClassification` (one category
  + a clean title). Guided entries are organized by the user and skip the model.
  Free-written workout sessions get the same treatment: the model parses them into
  structured exercises against the on-device exercise library.
- **Offline-safe** — entries are saved locally the instant they're created and
  never lost. The pipeline (save → push raw → classify if needed → sync) retries on
  foreground, on reconnect, and when the model becomes available. The CloudKit
  private database stays authoritative; a file-based cache powers instant, offline
  rendering.
- **Native everything** — `NavigationStack`, `TabView`, `List` + `.searchable` +
  `.swipeActions` + `.refreshable`, `SignInWithAppleButton`, `CloudKit`, Swift
  Charts, and Liquid Glass (`.glassEffect` / `.glass` / `.glassProminent`) on
  chrome only.

See [`DECISIONS.md`](DECISIONS.md) for the rationale behind the schema, the scoring
system, and the architecture forks.

### Privacy

The microphone and speech transcription are used **only** while you record, and
transcription happens **entirely on-device**. The classification of free-written
entries, and the parsing of free-written workouts, is on-device too. Only your raw
text and organized entries sync, and they sync to your own **private CloudKit
database**, scoped automatically to your signed-in iCloud account. Apple has no
special access beyond standard iCloud infrastructure, and no other party (not even
us) can read it.

---

## CloudKit schema

> Historical reference is also kept at [`supabase/schema.sql`](supabase/schema.sql)
> (now just documentation, there is no SQL anymore).

There is no database to create by hand. CloudKit auto-creates the schema below in
the **Development** environment the first time the app saves a record, scoped to
the container `iCloud.Moments.LYFESTYLE`, **private database**. One record type,
`Entry`, one record per journal entry (its `recordName` is the entry's UUID):

| Field | Type | Notes |
| --- | --- | --- |
| `rawText` | String | the raw typed or transcribed text |
| `source` | String | `text` or `voice` |
| `status` | String | `pending` / `processing` / `processed` / `failed` |
| `schemaVersion` | Int | currently `6` |
| `category` | String, optional | `NUTRITION` / `ACTIVITY` / `SLEEP` / `HEALTH` / `MIND` / `SOCIAL`, or absent for a free thought with nothing trackable |
| `subtag` | String, optional | refinement of the category (e.g. SOCIAL's relationship, a meal type) |
| `title` | String, optional | clean, neutral display title |
| `entryDate` | Date | the day the entry belongs to |
| `createdAt` | Date | when the record was created |
| `userID` | String, optional | local tag only, CloudKit already scopes the private database to the signed-in iCloud account |
| `fields` | JSON blob | the user's organized answers |
| `workout` | JSON blob, optional | structured exercises/sets/reps/weight, ACTIVITY entries only |

No Row Level Security to configure, no indexes to create by hand, no
`profiles`/`insights`/`check_ins` tables. The private database is inherently
scoped to one iCloud account, so every record is already private to its owner.

---

## Tech

Swift 6 · SwiftUI · `@Observable` · Foundation Models · Speech (`SpeechAnalyzer`)
· AVFoundation · AuthenticationServices · CloudKit · Swift Charts · Liquid Glass.
No third-party dependencies.
