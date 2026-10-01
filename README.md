# GoTravel RD

English | [Español](README.es.md)

**Public transit app for the Dominican Republic.** It computes the best route between real Metro and OMSA stops, shows it on an interactive map, and guides you live during the trip with turn-by-turn instructions and an estimated arrival time (ETA).

University academic project. Spanish (es-DO) interface, dark theme, and support for Android and iOS.

---

## Features

- **Interactive map** — Google Maps with the 490 real Metro and OMSA stops in Santo Domingo, with per-transport-type markers and a polyline for the computed route.
- **A→B routing engine (built from scratch)** — Multi-source Dijkstra in pure Dart over a graph built from Firestore. It supports transfers, in-station transfers (e.g. Juan Pablo Duarte L1↔L2) and the user's preferred transport mode.
- **Maximum walking distance** — user-configurable (1.5 km by default), with a two-phase override that allows up to 5 km.
- **Live trip** — GPS tracking with *route matching* against the route, step-by-step instructions, a progress bar and an ETA recomputed in real time.
- **Favorites** — saved routes and transport types, with rename and delete.
- **Trip history** — trips are recorded automatically, with date, cost and distance.
- **Authentication** — email/password and Google Sign-In (Firebase Auth).
- **Preferences** — maximum walking distance and favorite transport types, persisted per user.
- **Extras** — reverse geocoding under the pin, dark theme, es-DO localization, edge-to-edge support (Android 15+).

## Tech stack

| Area | Technology |
|---|---|
| Framework | **Flutter 3.44** / **Dart ^3.12** |
| State management | **Riverpod 2** (providers + controllers) |
| Maps | **google_maps_flutter**, **geocoding** |
| Location | **geolocator**, **permission_handler** |
| Backend | **Firebase** — Firestore + Auth (`cloud_firestore`, `firebase_auth`, `google_sign_in`) |
| Background compute | `compute()` (separate isolate) |
| i18n / formatting | `flutter_localizations`, `intl` (es, es-DO) |
| Testing | `flutter_test`, `flutter_lints` |

## Prerequisites

- **Flutter SDK 3.44+** (stable) with Dart 3.12+.
- **Android**: Android Studio + Android SDK + JDK 17.
- **iOS** (optional): macOS with Xcode and CocoaPods.
- **Firebase account** with your own project (Firestore in production mode and Authentication enabled for email/Google).

## Getting started

### 1. Dependencies

```bash
flutter pub get
```

### 2. Create the local config files

These files are **not versioned** (they are in `.gitignore`); create them by hand:

**a) Android — `android/local.properties`**

```properties
sdk.dir=/path/to/your/Android/Sdk
MAPS_API_KEY=your_Maps_SDK_for_Android_api_key
```

**b) Web (optional, for `flutter run -d chrome`) — `web/maps_config.js`**

Copy the template and paste your key:

```bash
cp web/maps_config.example.js web/maps_config.js
```

> The web key belongs to the **Maps JavaScript API** product (different from the *Maps SDK for Android*) and must be restricted by HTTP referrer (`http://localhost:*`).

**c) iOS (optional) — `GOOGLE_MAPS_API_KEY`**

Edit it in `ios/Flutter/Release.xcconfig` (and `Debug.xcconfig`). ⚠️ That file **is versioned**: if you are going to put a real key there, move it to a git-ignored `ios/Flutter/Secrets.xcconfig` and `#include` it from the Flutter `.xcconfig` files.

### 3. Firebase

- `android/app/google-services.json` and `lib/firebase_options.dart` are already included for the sample project. To use **your own** project, regenerate the config with:
  ```bash
  dart pub global activate flutterfire_cli
  flutterfire configure
  ```
- The expected collections are `routes` (14 documents), `stations` (490) and `users`.

### 4. Run

```bash
flutter run                 # Android/iOS
flutter run -d chrome       # web (requires web/maps_config.js)
```

### 5. Tests

```bash
flutter analyze   # no issues
flutter test      # 122 tests
```

## Project structure

```
lib/
  application/   # Riverpod: providers and controllers (planner, live trip)
  core/          # dark theme (AppTheme/AppColors), formatters, motion
  data/          # static PoC data (metro_stations)
  domain/        # pure logic with no Flutter dependency, testable without a device
    geo/         # GeoPoint and distances (Haversine)
    models/      # TripPlan, TripProgress, instructions, transport modes
    routing/     # A→B engine (station_graph, route_engine)
    tracking/    # TripTracker, ETA, route matcher, geometry
  features/
    live_trip/   # active trip screen + widgets
    shared/      # domain→UI bridge (icons, colors)
  models/        # AppUser, Station, Route, TripHistoryEntry
  screens/       # main_shell, home, map, profile, login, trip_history
  services/      # auth, firestore, stations, routes, geocoding, user_route
  widgets/       # search_box
```

The `domain/` layer depends on neither Flutter nor Firebase: the routing engine and the tracker are tested as pure logic.

## Data

- Stops and routes are loaded into Firestore with a **separate import script** (Node.js + `firebase-admin`), not from the app. That script uses the Admin SDK, which bypasses the Security Rules.
- Sources: Metro (39 stations) and OMSA trunk corridors (Kennedy, 27 de Febrero, Charles de Gaulle), with data from INTRANT.
- ⚠️ **Fares and frequencies are team estimates**, not official data from INTRANT/Metro/OMSA.

## Security and keys

The Firebase API keys in this repo are **client keys** by design (they ship inside the APK regardless); data protection lives in the **Firestore Security Rules** (`firestore.rules`):

- `routes` and `stations`: public read, **writes blocked** (only the Admin SDK writes).
- `users/{uid}` and `users/{uid}/favorites/*`: read/write only for the owner (`request.auth.uid == uid`).

For your own deployment, **restrict each API key** in the Google Cloud Console:

| Key | Restrict by |
|---|---|
| Android (`google-services.json`) | Android apps → package `com.unapec.gotravelrd` + keystore SHA-1 |
| Web (`firebase_options.dart`) | HTTP referrers (domain / `localhost`) |
| iOS (`firebase_options.dart`) | iOS apps → bundle ID |

Never commit `android/local.properties`, `web/maps_config.js` or a keystore — they are already ignored by `.gitignore`.

## License

Academic project, with no explicit license. All code is owned by its authors and is shared for educational purposes.