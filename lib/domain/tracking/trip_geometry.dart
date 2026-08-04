import '../geo/geo_math.dart';
import '../geo/geo_point.dart';
import '../models/trip_plan.dart';

/// Índice lineal precalculado del viaje completo.
///
/// Convierte los tramos del [TripPlan] en **una sola polilínea con distancias
/// acumuladas**. A partir de ahí, "dónde va el usuario" deja de ser un problema
/// de 2 dimensiones y pasa a ser un número: cuántos metros lleva recorridos.
/// Todo lo demás (ETA, próxima parada, progreso, instrucciones) se deriva de
/// ese número, que es lo que hace barato recalcular en cada muestra del GPS.
///
/// Se construye una sola vez por viaje.
class TripGeometry {
  TripGeometry._({
    required this.plan,
    required this.points,
    required this.cumulative,
    required this.segmentLeg,
    required this.legStartMeters,
    required this.legEndMeters,
    required this.stopMeters,
  });

  factory TripGeometry.from(TripPlan plan) {
    final List<GeoPoint> points = <GeoPoint>[];
    final List<double> cumulative = <double>[];
    final List<int> segmentLeg = <int>[];
    final List<double> legStart = List<double>.filled(plan.legs.length, 0);
    final List<double> legEnd = List<double>.filled(plan.legs.length, 0);

    for (int legIndex = 0; legIndex < plan.legs.length; legIndex++) {
      final TripLeg leg = plan.legs[legIndex];
      legStart[legIndex] = cumulative.isEmpty ? 0 : cumulative.last;

      for (int i = 0; i < leg.path.length; i++) {
        final GeoPoint p = leg.path[i];
        if (points.isEmpty) {
          points.add(p);
          cumulative.add(0);
          continue;
        }
        // Si el primer punto del tramo coincide con el último del anterior,
        // no lo duplicamos (los planes bien formados encadenan así). Si NO
        // coincide, dejamos el segmento conector: representa un hueco real del
        // plan y es mejor verlo que esconderlo.
        if (i == 0 && points.last == p) continue;

        final double d = distanceMeters(points.last, p);
        points.add(p);
        cumulative.add(cumulative.last + d);
        segmentLeg.add(legIndex);
      }
      legEnd[legIndex] = cumulative.last;
    }

    // Distancia acumulada de cada parada, proyectándola sobre su propio tramo.
    final List<List<double>> stopMeters = <List<double>>[];
    for (int legIndex = 0; legIndex < plan.legs.length; legIndex++) {
      final TripLeg leg = plan.legs[legIndex];
      final List<double> perStop = <double>[];
      for (final TripStop stop in leg.stops) {
        perStop.add(
          _distanceAlongWithinLeg(
            stop.position,
            legIndex,
            points,
            cumulative,
            segmentLeg,
          ),
        );
      }
      stopMeters.add(List<double>.unmodifiable(perStop));
    }

    return TripGeometry._(
      plan: plan,
      points: List<GeoPoint>.unmodifiable(points),
      cumulative: List<double>.unmodifiable(cumulative),
      segmentLeg: List<int>.unmodifiable(segmentLeg),
      legStartMeters: List<double>.unmodifiable(legStart),
      legEndMeters: List<double>.unmodifiable(legEnd),
      stopMeters: List<List<double>>.unmodifiable(stopMeters),
    );
  }

  final TripPlan plan;

  /// Vértices del viaje completo, en orden.
  final List<GeoPoint> points;

  /// `cumulative[i]` = metros desde el inicio del viaje hasta `points[i]`.
  final List<double> cumulative;

  /// `segmentLeg[i]` = índice del tramo al que pertenece el segmento
  /// `points[i] → points[i + 1]`.
  final List<int> segmentLeg;

  final List<double> legStartMeters;
  final List<double> legEndMeters;

  /// `stopMeters[legIndex][stopIndex]` = distancia acumulada de esa parada.
  final List<List<double>> stopMeters;

  double get totalMeters => cumulative.isEmpty ? 0 : cumulative.last;
  int get segmentCount => segmentLeg.length;

  /// Punto del viaje a `meters` del inicio.
  GeoPoint pointAt(double meters) {
    if (points.isEmpty) return const GeoPoint(0, 0);
    final double m = meters.clamp(0.0, totalMeters);
    final int i = _segmentIndexAt(m);
    final double segStart = cumulative[i];
    final double segLength = cumulative[i + 1] - segStart;
    final double t = segLength == 0 ? 0 : (m - segStart) / segLength;
    return interpolate(points[i], points[i + 1], t);
  }

  /// Índice del tramo (leg) en el que se está a `meters` del inicio.
  int legIndexAt(double meters) {
    if (segmentLeg.isEmpty) return 0;
    return segmentLeg[_segmentIndexAt(meters.clamp(0.0, totalMeters))];
  }

  /// Rumbo del recorrido en ese punto, para orientar la cámara del mapa.
  double headingAt(double meters) {
    if (points.length < 2) return 0;
    final int i = _segmentIndexAt(meters.clamp(0.0, totalMeters));
    return bearingDegrees(points[i], points[i + 1]);
  }

  /// Porción de la polilínea **ya recorrida** (0 → `meters`).
  List<GeoPoint> sliceUpTo(double meters) => _slice(0, meters);

  /// Porción de la polilínea **que falta** (`meters` → final).
  List<GeoPoint> sliceFrom(double meters) => _slice(meters, totalMeters);

  /// Paradas del tramo `legIndex` que aún no se han pasado, dado el avance.
  ///
  /// El margen de 40 m evita que una parada "parpadee" entre pasada y
  /// pendiente por el ruido del GPS cuando el usuario está justo encima.
  List<TripStop> upcomingStopsOfLeg(int legIndex, double traveledMeters) {
    if (legIndex < 0 || legIndex >= plan.legs.length) return const <TripStop>[];
    final TripLeg leg = plan.legs[legIndex];
    final List<double> meters = stopMeters[legIndex];
    final List<TripStop> result = <TripStop>[];
    for (int i = 0; i < leg.stops.length; i++) {
      if (meters[i] > traveledMeters + 40) result.add(leg.stops[i]);
    }
    return result;
  }

  /// Distancia acumulada de una parada concreta.
  double meterOfStop(int legIndex, int stopIndex) => stopMeters[legIndex][stopIndex];

  /// Búsqueda binaria del segmento que contiene la distancia `m`.
  int _segmentIndexAt(double m) {
    int low = 0;
    int high = points.length - 2;
    if (high < 0) return 0;
    while (low < high) {
      final int mid = (low + high + 1) >> 1;
      if (cumulative[mid] <= m) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  List<GeoPoint> _slice(double fromMeters, double toMeters) {
    if (points.length < 2) return List<GeoPoint>.from(points);
    final double from = fromMeters.clamp(0.0, totalMeters);
    final double to = toMeters.clamp(0.0, totalMeters);
    if (to <= from) return <GeoPoint>[pointAt(from)];

    final List<GeoPoint> result = <GeoPoint>[pointAt(from)];
    for (int i = 0; i < points.length; i++) {
      if (cumulative[i] > from && cumulative[i] < to) result.add(points[i]);
    }
    result.add(pointAt(to));
    return result;
  }

  static double _distanceAlongWithinLeg(
    GeoPoint stop,
    int legIndex,
    List<GeoPoint> points,
    List<double> cumulative,
    List<int> segmentLeg,
  ) {
    double best = double.infinity;
    double bestMeters = 0;
    for (int i = 0; i < segmentLeg.length; i++) {
      if (segmentLeg[i] != legIndex) continue;
      final SegmentProjection proj =
          projectOnSegment(stop, points[i], points[i + 1]);
      if (proj.distanceMeters < best) {
        best = proj.distanceMeters;
        bestMeters =
            cumulative[i] + (cumulative[i + 1] - cumulative[i]) * proj.t;
      }
    }
    return bestMeters;
  }
}
