# GoTravel RD

**App móvil de transporte público para República Dominicana.** Calcula la mejor ruta entre paradas reales del Metro y la OMSA, la muestra en un mapa interactivo y guía al usuario en vivo durante el viaje con instrucciones de navegación y hora de llegada estimada (ETA).

Proyecto académico universitario. Interfaz en español (es-DO), tema oscuro y soporte de Android e iOS.

---

## Funcionalidades

- **Mapa interactivo** — Google Maps con las 490 paradas reales del Metro y la OMSA de Santo Domingo, con marcadores por tipo de transporte y polilínea de la ruta calculada.
- **Motor de rutas A→B (propio)** — Dijkstra multi-fuente en Dart puro sobre un grafo construido desde Firestore. Soporta transbordos, EAEs en Metro (Juan Pablo Duarte L1↔L2) y la preferencia de transporte del usuario.
- **Distancia máxima caminable** — configurable por el usuario (por defecto 1.5 km), con override autorizado en dos fases hasta 5 km.
- **Viaje en vivo** — seguimiento del GPS con *route matching* sobre la ruta, instrucciones paso a paso, barra de progreso y ETA recalculada en tiempo real.
- **Favoritos** — rutas y tipos de transporte guardados, con renombrar y eliminar.
- **Historial de viajes** — registro automático de los viajes iniciados, con fecha, costo y distancia.
- **Autenticación** — correo/contraseña y Google Sign-In (Firebase Auth).
- **Preferencias** — distancia máxima a pie y tipos de transporte favoritos, persistidas por usuario.
- **Extras** — geocodificación inversa bajo el pin, tema oscuro, localización es-DO, opción borde a borde (Android 15+).

## Tecnologías

| Área | Tecnología |
|---|---|
| Framework | **Flutter 3.44** / **Dart ^3.12** |
| Estado | **Riverpod 2** (providers + controladores) |
| Mapas | **google_maps_flutter**, **geocoding** |
| Ubicación | **geolocator**, **permission_handler** |
| Backend | **Firebase** — Firestore + Auth (`cloud_firestore`, `firebase_auth`, `google_sign_in`) |
| Cálculo en background | `compute()` (isolate separado) |
| i18n / formatos | `flutter_localizations`, `intl` (es, es-DO) |
| Testing | `flutter_test`, `flutter_lints` |

## Requisitos previos

- **Flutter SDK 3.44+** (estable) con Dart 3.12+.
- **Android**: Android Studio + Android SDK + JDK 17.
- **iOS** (opcional): macOS con Xcode y CocoaPods.
- **Cuenta de Firebase** con un proyecto propio (Firestore en modo producción y Authentication habilitada para email/Google).

## Cómo ejecutarlo

### 1. Dependencias

```bash
flutter pub get
```

### 2. Crear los archivos de configuración local

Estos archivos **no se versionan** (están en `.gitignore`); créalos a mano:

**a) Android — `android/local.properties`**

```properties
sdk.dir=/ruta/a/tu/Android/Sdk
MAPS_API_KEY=tu_api_key_de_Maps_SDK_for_Android
```

**b) Web (opcional, para `flutter run -d chrome`) — `web/maps_config.js`**

Copia la plantilla y pega tu key:

```bash
cp web/maps_config.example.js web/maps_config.js
```

> La key de web es del producto **Maps JavaScript API** (distinto del *Maps SDK for Android*) y debe restringirse por referente HTTP (`http://localhost:*`).

**c) iOS (opcional) — `GOOGLE_MAPS_API_KEY`**

Edítalo en `ios/Flutter/Release.xcconfig` (y `Debug.xcconfig`). ⚠️ Ese archivo **está versionado**: si vas a poner una key real, muévela a un `ios/Flutter/Secrets.xcconfig` ignorado por git e `#include`alo desde los `.xcconfig` de Flutter.

### 3. Firebase

- `android/app/google-services.json` y `lib/firebase_options.dart` ya vienen incluidos para el proyecto de ejemplo. Para usar **tu propio** proyecto, regenera la config con:
  ```bash
  dart pub global activate flutterfire_cli
  flutterfire configure
  ```
- Las colecciones esperadas son `routes` (14 documentos), `stations` (490) y `users`.

### 4. Correr

```bash
flutter run                 # Android/iOS
flutter run -d chrome       # web (requiere web/maps_config.js)
```

### 5. Pruebas

```bash
flutter analyze   # sin issues
flutter test      # 122 tests
```

## Estructura del proyecto

```
lib/
  application/   # Riverpod: providers y controladores (planner, live trip)
  core/          # tema oscuro (AppTheme/AppColors), formatters, motion
  data/          # datos estáticos del PoC (metro_stations)
  domain/        # lógica pura sin Flutter, testeable sin dispositivo
    geo/         # GeoPoint y distancias (Haversine)
    models/      # TripPlan, TripProgress, instrucciones, modos de transporte
    routing/     # motor A→B (station_graph, route_engine)
    tracking/    # TripTracker, ETA, route matcher, geometría
  features/
    live_trip/   # pantalla de viaje activo + widgets
    shared/      # puente dominio→UI (iconos, colores)
  models/        # AppUser, Station, Route, TripHistoryEntry
  screens/       # main_shell, home, map, profile, login, trip_history
  services/      # auth, firestore, estaciones, rutas, geocoding, user_route
  widgets/       # search_box
```

La capa `domain/` no depende de Flutter ni de Firebase: el motor de rutas y el tracker se prueban como lógica pura.

## Datos

- Las paradas y rutas se cargan a Firestore con un **script de importación aparte** (Node.js + `firebase-admin`), no desde la app. Ese script usa el Admin SDK, que ignora las Security Rules.
- Fuentes: Metro (39 estaciones) y corredores troncales de la OMSA (Kennedy, 27 de Febrero, Charles de Gaulle), con datos de INTRANT.
- ⚠️ **Las tarifas y frecuencias son estimaciones del equipo**, no datos oficiales de INTRANT/Metro/OMSA.

## Seguridad y claves

Las API keys de Firebase de este repo son **claves de cliente** por diseño (viajan dentro del APK de todas formas); la protección de los datos está en las **Firestore Security Rules** (`firestore.rules`):

- `routes` y `stations`: lectura pública, **escritura bloqueada** (solo el Admin SDK escribe).
- `users/{uid}` y `users/{uid}/favorites/*`: lectura/escritura solo por el propietario (`request.auth.uid == uid`).

Para un despliegue propio, **restringe cada API key** en Google Cloud Console:

| Key | Restringir por |
|---|---|
| Android (`google-services.json`) | Android apps → package `com.unapec.gotravelrd` + SHA-1 del keystore |
| Web (`firebase_options.dart`) | Referentes HTTP (dominio / `localhost`) |
| iOS (`firebase_options.dart`) | iOS apps → bundle ID |

Nunca subas `android/local.properties`, `web/maps_config.js` ni un keystore — ya están ignorados por `.gitignore`.

## Licencia

Proyecto académico, sin licencia explícita. Todo el código es propiedad de sus autores y se comparte con fines educativos.