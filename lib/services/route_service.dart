import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/route.dart';
import 'firebase_config.dart';

/// Lee las rutas del backend para el motor de cálculo A→B (Hito 2).
class RouteService {
  final FirebaseFirestore _firestore = firestore;

  /// Rutas activas con paradas fijas y un recorrido cargado, listas para el
  /// motor. El filtro por `active`/`hasFixedStations` se hace acá y el motor
  /// lo re-valida por robustez (un plan nunca debe construirse sobre una ruta
  /// desactivada o sin estaciones).
  Future<List<Route>> getActiveRoutes() async {
    final snapshot = await _firestore
        .collection('routes')
        .get(const GetOptions(source: Source.server));
    final List<Route> routes =
        snapshot.docs.map(Route.fromSnapshot).toList(growable: false);
    return routes
        .where((Route r) =>
            r.active &&
            r.hasFixedStations &&
            (r.stations?.length ?? 0) >= 2)
        .toList(growable: false);
  }
}
