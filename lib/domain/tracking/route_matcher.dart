import '../geo/geo_math.dart';
import '../geo/geo_point.dart';
import 'trip_geometry.dart';

/// Posición del usuario "pegada" a la ruta planificada.
class RouteMatch {
  const RouteMatch({
    required this.snapped,
    required this.distanceFromRouteMeters,
    required this.traveledMeters,
    required this.legIndex,
    required this.segmentIndex,
  });

  /// Punto sobre la ruta más cercano a la posición real del GPS.
  final GeoPoint snapped;

  /// Cuánto se desvió el GPS de la ruta. Es la señal de "me fui por otro lado".
  final double distanceFromRouteMeters;

  /// Metros recorridos desde el inicio del viaje (referencia lineal).
  final double traveledMeters;

  final int legIndex;
  final int segmentIndex;
}

/// Emparejador de posición GPS con la ruta planificada (*map matching*).
///
/// El problema real que resuelve: la ruta del Metro **se cruza consigo misma**
/// en Juan Pablo Duarte (transbordo L1↔L2). Buscar globalmente el punto más
/// cercano haría que, al pasar por el cruce, el sistema creyera que el usuario
/// está en el otro tramo y el progreso saltara hacia atrás o hacia adelante.
///
/// Por eso el emparejamiento es **incremental**: solo se buscan los segmentos
/// dentro de una ventana alrededor del avance anterior. Se abre a búsqueda
/// global únicamente al iniciar el viaje o cuando el usuario se salió tanto de
/// la ventana que ya no tiene sentido (salto de GPS, app reabierta, se montó en
/// otro punto de la ruta).
class RouteMatcher {
  RouteMatcher(
    this.geometry, {
    this.backWindowMeters = 120,
    this.forwardWindowMeters = 1200,
    this.windowEscapeMeters = 180,
  });

  final TripGeometry geometry;

  /// Cuánto se permite "retroceder" respecto al avance previo. Un poco de
  /// retroceso es normal (ruido del GPS); mucho, no.
  final double backWindowMeters;

  /// Cuánto se permite avanzar de una muestra a otra. A 32 km/h (metro) y
  /// muestras cada 1–2 s sobran; el margen absorbe pausas de la app.
  final double forwardWindowMeters;

  /// Si dentro de la ventana lo más cercano queda más lejos que esto, la
  /// ventana perdió validez y se reintenta con búsqueda global.
  final double windowEscapeMeters;

  RouteMatch match(GeoPoint position, {double? previousTraveledMeters}) {
    if (geometry.segmentCount == 0) {
      return RouteMatch(
        snapped: position,
        distanceFromRouteMeters: 0,
        traveledMeters: 0,
        legIndex: 0,
        segmentIndex: 0,
      );
    }

    if (previousTraveledMeters == null) {
      return _search(position, 0, geometry.totalMeters);
    }

    final double from = previousTraveledMeters - backWindowMeters;
    final double to = previousTraveledMeters + forwardWindowMeters;
    final RouteMatch windowed = _search(position, from, to);
    if (windowed.distanceFromRouteMeters <= windowEscapeMeters) return windowed;

    // La ventana ya no describe dónde está el usuario: reintento global.
    return _search(position, 0, geometry.totalMeters);
  }

  RouteMatch _search(GeoPoint position, double fromMeters, double toMeters) {
    double bestDistance = double.infinity;
    double bestTraveled = 0;
    GeoPoint bestPoint = position;
    int bestSegment = 0;

    for (int i = 0; i < geometry.segmentCount; i++) {
      final double segStart = geometry.cumulative[i];
      final double segEnd = geometry.cumulative[i + 1];
      // Descarta segmentos completamente fuera de la ventana.
      if (segEnd < fromMeters || segStart > toMeters) continue;

      final SegmentProjection proj = projectOnSegment(
        position,
        geometry.points[i],
        geometry.points[i + 1],
      );
      if (proj.distanceMeters < bestDistance) {
        bestDistance = proj.distanceMeters;
        bestPoint = proj.point;
        bestTraveled = segStart + (segEnd - segStart) * proj.t;
        bestSegment = i;
      }
    }

    if (bestDistance == double.infinity) {
      // Ventana vacía (puede pasar con planes de un solo segmento y ventanas
      // raras): caemos al inicio de la ventana en vez de reventar.
      final double m = fromMeters.clamp(0.0, geometry.totalMeters);
      return RouteMatch(
        snapped: geometry.pointAt(m),
        distanceFromRouteMeters: distanceMeters(position, geometry.pointAt(m)),
        traveledMeters: m,
        legIndex: geometry.legIndexAt(m),
        segmentIndex: 0,
      );
    }

    return RouteMatch(
      snapped: bestPoint,
      distanceFromRouteMeters: bestDistance,
      traveledMeters: bestTraveled,
      legIndex: geometry.segmentLeg[bestSegment],
      segmentIndex: bestSegment,
    );
  }
}
