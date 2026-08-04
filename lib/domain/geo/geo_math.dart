import 'dart:math' as math;

import 'geo_point.dart';

/// Radio medio de la Tierra (IUGG), en metros.
const double kEarthRadiusMeters = 6371008.8;

double _rad(double degrees) => degrees * math.pi / 180.0;
double _deg(double radians) => radians * 180.0 / math.pi;

/// Distancia sobre la esfera entre dos puntos, en metros (fórmula del haversine).
///
/// A escala urbana el error frente a un elipsoide (Vincenty) es < 0.3 %, muy por
/// debajo de la precisión del GPS de un celular (5–20 m). No vale la pena el
/// costo extra de cómputo en un loop que corre varias veces por segundo.
double distanceMeters(GeoPoint a, GeoPoint b) {
  final double dLat = _rad(b.lat - a.lat);
  final double dLng = _rad(b.lng - a.lng);
  final double lat1 = _rad(a.lat);
  final double lat2 = _rad(b.lat);

  final double h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * kEarthRadiusMeters * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Rumbo inicial de `from` hacia `to`, en grados [0, 360) donde 0 = Norte.
///
/// Se usa para orientar la cámara del mapa y la flecha del usuario.
double bearingDegrees(GeoPoint from, GeoPoint to) {
  final double lat1 = _rad(from.lat);
  final double lat2 = _rad(to.lat);
  final double dLng = _rad(to.lng - from.lng);

  final double y = math.sin(dLng) * math.cos(lat2);
  final double x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (_deg(math.atan2(y, x)) + 360.0) % 360.0;
}

/// Punto intermedio entre `a` y `b` para una fracción `t` en [0, 1].
///
/// Interpolación lineal en lat/lng. Es exacta para tramos cortos (< 1 km), que
/// es todo lo que hay entre dos vértices de una polilínea de transporte.
GeoPoint interpolate(GeoPoint a, GeoPoint b, double t) {
  final double clamped = t.clamp(0.0, 1.0);
  return GeoPoint(
    a.lat + (b.lat - a.lat) * clamped,
    a.lng + (b.lng - a.lng) * clamped,
  );
}

/// Desplaza un punto `distance` metros en el rumbo `bearing` (grados).
GeoPoint offsetMeters(GeoPoint origin, double distance, double bearing) {
  final double angular = distance / kEarthRadiusMeters;
  final double theta = _rad(bearing);
  final double lat1 = _rad(origin.lat);
  final double lng1 = _rad(origin.lng);

  final double lat2 = math.asin(
    math.sin(lat1) * math.cos(angular) +
        math.cos(lat1) * math.sin(angular) * math.cos(theta),
  );
  final double lng2 = lng1 +
      math.atan2(
        math.sin(theta) * math.sin(angular) * math.cos(lat1),
        math.cos(angular) - math.sin(lat1) * math.sin(lat2),
      );
  return GeoPoint(_deg(lat2), _deg(lng2));
}

/// Resultado de proyectar un punto sobre un segmento.
class SegmentProjection {
  const SegmentProjection({
    required this.point,
    required this.t,
    required this.distanceMeters,
  });

  /// El punto del segmento más cercano al original ("posición pegada a la ruta").
  final GeoPoint point;

  /// Posición dentro del segmento, 0 = inicio, 1 = final.
  final double t;

  /// Qué tan lejos estaba el punto original del segmento, en metros.
  final double distanceMeters;
}

/// Proyecta `p` sobre el segmento `a`→`b`.
///
/// Convierte a un plano local en metros (equirectangular centrado en `a`), que
/// a escala de un segmento de calle es indistinguible de la esfera, y resuelve
/// la proyección escalar clásica. Trabajar en grados directamente daría un
/// resultado sesgado, porque un grado de longitud mide menos que uno de latitud
/// (en RD, ~0.95 veces).
SegmentProjection projectOnSegment(GeoPoint p, GeoPoint a, GeoPoint b) {
  final double cosLat = math.cos(_rad(a.lat));

  double localX(GeoPoint q) => _rad(q.lng - a.lng) * cosLat * kEarthRadiusMeters;
  double localY(GeoPoint q) => _rad(q.lat - a.lat) * kEarthRadiusMeters;

  final double bx = localX(b);
  final double by = localY(b);
  final double px = localX(p);
  final double py = localY(p);

  final double segLenSq = bx * bx + by * by;
  if (segLenSq == 0) {
    // Segmento degenerado (a == b): no hay dirección, devolvemos el extremo.
    return SegmentProjection(point: a, t: 0, distanceMeters: distanceMeters(p, a));
  }

  final double t = ((px * bx + py * by) / segLenSq).clamp(0.0, 1.0);
  final GeoPoint snapped = interpolate(a, b, t);
  return SegmentProjection(
    point: snapped,
    t: t,
    distanceMeters: distanceMeters(p, snapped),
  );
}

/// Largo total de una polilínea en metros.
double polylineLengthMeters(List<GeoPoint> points) {
  double total = 0;
  for (int i = 0; i < points.length - 1; i++) {
    total += distanceMeters(points[i], points[i + 1]);
  }
  return total;
}
