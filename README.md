<img src="logo.png" width="96" alt="LYFESTYL icon">

# LYFESTYL

Calorie tracking from a photo. iOS, free, runs on device.

<p>
  <img src="Screenshots/01-onboarding.png" width="220" alt="Onboarding">
  <img src="Screenshots/02-review.png" width="220" alt="Review drawer">
  <img src="Screenshots/03-dashboard.png" width="220" alt="Dashboard">
</p>

## Features

- Snap a meal, get calories and macros per item
- Reads labels on packaged food
- Edit any item with sliders, then log
- Search, recent foods, or manual entry
- Dashboard with today, 7-day cards, charts, history
- iCloud sync, optional Apple Health
- Photos are never saved

## Built with

- SwiftUI, Swift 6, iOS 27
- Foundation Models (vision, guided generation)
- Vision (label text)
- AVFoundation
- SwiftData + CloudKit
- HealthKit
- No packages, no servers, no keys

## Run

- Xcode 27, iPhone with Apple Intelligence
- Open `LYFESTYL.xcodeproj`, set your team, run
- Simulator runs the UI; the model needs a macOS 27 host
- Before release, deploy the CloudKit schema to Production

## Data

CloudKit record `CD_MealEntry`

| Field | Type | |
| --- | --- | --- |
| `CD_id` | String | meal id |
| `CD_loggedAt` | Date | when logged |
| `CD_itemsData` | Bytes | foods, binary plist |

- Food keys: `n` name, `p` portion, `s` servings, `k` kcal, `r` protein, `c` carbs, `f` fat
- iCloud key-value: `goals.v1`, `bodyProfile.v1`, `profile.name`, `profile.photo` (256 px)
- Health: energy, protein, carbs, fat per meal, sync id `<meal id>.<macro>`

## Layout

```
LYFESTYL/
  App/  DesignSystem/  Models/  Services/
  Features/  Camera/  Review/  Dashboard/  Settings/  Onboarding/
Verification/
```

## Tests

```
Verification/run.sh
```

<sub>Product photo in screenshots from Open Food Facts, CC BY-SA.</sub>
