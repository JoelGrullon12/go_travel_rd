import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/trip_plan.dart';
import '../domain/routing/route_preferences.dart';
import '../models/route.dart';
import '../models/transport_type.dart';
import '../models/trip_history_entry.dart';
import '../models/user.dart';
import '../models/user_route.dart';
import '../services/auth_service.dart';
import '../services/route_service.dart';
import '../services/transport_type_service.dart';
import '../services/trip_history_service.dart';
import '../services/user_route_service.dart';

/// Distancia máxima a pie por defecto (1500 m ≈ 18 min caminando) cuando el
/// usuario no tiene la preferencia guardada. Es la única fuente del valor por
/// defecto: [AppUser.maxWalkDistance] usa el mismo número.
const double kDefaultMaxWalkMeters = 1500;

/// Tope de caminata de la **fase 1** del cálculo con distancia superada.
///
/// Cuando el usuario acepta planificar pese a exceder su distancia máxima
/// ([PlannerController.plan] con `overrideMaxWalk`), primero se busca con esta
/// cota acotada (5 km): acota los candidatos de abordaje/bajada y mantiene el
/// cálculo liviano. Solo si ni así hay estaciones alcanzables, la fase 2 suelta
/// la distancia infinita.
const double kOverrideWalkCapMeters = 5000;

/// Rutas disponibles para el motor de cálculo A→B.
final FutureProvider<List<Route>> routesProvider =
    FutureProvider<List<Route>>((ref) => RouteService().getActiveRoutes());

/// Distancia máxima a pie del usuario, leída de `users/{uid}.maxWalkDistance`.
/// Sin sesión o sin preferencia guardada, se usa [kDefaultMaxWalkMeters].
final FutureProvider<double> maxWalkDistanceProvider =
    FutureProvider<double>((ref) async {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final User? firebaseUser = auth.currentUser;
  if (firebaseUser == null) return kDefaultMaxWalkMeters;
  final AppUser? user = await AuthService().getUserData(firebaseUser.uid);
  return user?.maxWalkDistance ?? kDefaultMaxWalkMeters;
});

/// Preferencias de viaje del usuario (preferencia de ruta + tipo de transporte
/// favorito) para el motor A→B. Sin sesión o sin datos, usa los defaults
/// (`speed`, sin tipo favorito) que reproducen exactamente el motor original.
final FutureProvider<RoutePreferences> userPreferencesProvider =
    FutureProvider<RoutePreferences>((ref) async {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final User? firebaseUser = auth.currentUser;
  if (firebaseUser == null) return const RoutePreferences();
  final AppUser? user = await AuthService().getUserData(firebaseUser.uid);
  return RoutePreferences(
    routePreference: user?.routePreference ?? 'speed',
    favoriteTransportTypeId: user?.favoriteTransportTypeId,
  );
});

/// Rutas personalizadas del usuario actual (Hito 5). Vacío sin sesión o sin
/// rutas guardadas.
final FutureProvider<List<UserRoute>> userRoutesProvider =
    FutureProvider<List<UserRoute>>(
  (ref) => UserRouteService().getUserRoutes(),
);

/// Historial de viajes del usuario actual (Hito 5). Vacío sin sesión o sin
/// viajes iniciados.
final FutureProvider<List<TripHistoryEntry>> tripHistoryProvider =
    FutureProvider<List<TripHistoryEntry>>(
  (ref) => TripHistoryService().getTripHistory(),
);

/// Catálogo de tipos de transporte (`transportTypes`) para la UI de
/// preferencias. Vacío si la colección no tiene documentos.
final FutureProvider<List<TransportType>> transportTypesProvider =
    FutureProvider<List<TransportType>>(
  (ref) => TransportTypeService().getTransportTypes(),
);

/// Último viaje terminado, para el widget "Viaje terminado" de la pantalla
/// principal. `LiveTripScreen` lo publica al cerrar (llegada o finalización
/// manual) y la tarjeta lo limpia con "Cerrar".
final StateProvider<TripPlan?> finishedTripProvider =
    StateProvider<TripPlan?>((ref) => null);
