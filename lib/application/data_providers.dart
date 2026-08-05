import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/route.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/route_service.dart';

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
