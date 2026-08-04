import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/domain/geo/geo_math.dart';
import 'package:go_travel_rd/domain/geo/geo_point.dart';

void main() {
  group('distanceMeters', () {
    test('devuelve 0 para el mismo punto', () {
      const GeoPoint p = GeoPoint(18.4800, -69.9200);
      expect(distanceMeters(p, p), 0);
    });

    test('mide correctamente entre dos estaciones reales del Metro', () {
      // Juan Pablo Duarte (L1) → Manuel Arturo Peña Batlle: ~515 m reales.
      const GeoPoint jpd = GeoPoint(18.481460, -69.914679);
      const GeoPoint batlle = GeoPoint(18.486087, -69.914369);
      expect(distanceMeters(jpd, batlle), closeTo(515, 15));
    });

    test('es simétrica', () {
      const GeoPoint a = GeoPoint(18.48, -69.92);
      const GeoPoint b = GeoPoint(18.51, -69.88);
      expect(distanceMeters(a, b), closeTo(distanceMeters(b, a), 0.001));
    });
  });

  group('offsetMeters', () {
    test('desplazar 100 m al norte aumenta la latitud lo esperado', () {
      const GeoPoint origin = GeoPoint(18.48, -69.92);
      final GeoPoint moved = offsetMeters(origin, 100, 0);
      expect(distanceMeters(origin, moved), closeTo(100, 0.5));
      expect(moved.lat, greaterThan(origin.lat));
      expect(moved.lng, closeTo(origin.lng, 0.0001));
    });

    test('desplazar al este aumenta la longitud', () {
      const GeoPoint origin = GeoPoint(18.48, -69.92);
      final GeoPoint moved = offsetMeters(origin, 250, 90);
      expect(distanceMeters(origin, moved), closeTo(250, 0.5));
      expect(moved.lng, greaterThan(origin.lng));
    });
  });

  group('projectOnSegment', () {
    const GeoPoint a = GeoPoint(18.4800, -69.9200);
    const GeoPoint b = GeoPoint(18.4800, -69.9100);

    test('un punto sobre el segmento se proyecta encima de sí mismo', () {
      const GeoPoint onLine = GeoPoint(18.4800, -69.9150);
      final SegmentProjection proj = projectOnSegment(onLine, a, b);
      expect(proj.distanceMeters, closeTo(0, 0.5));
      expect(proj.t, closeTo(0.5, 0.02));
    });

    test('un punto perpendicular reporta su distancia perpendicular', () {
      // ~55 m al norte del centro del segmento.
      const GeoPoint offLine = GeoPoint(18.48050, -69.9150);
      final SegmentProjection proj = projectOnSegment(offLine, a, b);
      expect(proj.distanceMeters, closeTo(55, 3));
      expect(proj.t, closeTo(0.5, 0.02));
    });

    test('un punto más allá del final se recorta al extremo (t = 1)', () {
      const GeoPoint beyond = GeoPoint(18.4800, -69.9000);
      final SegmentProjection proj = projectOnSegment(beyond, a, b);
      expect(proj.t, 1.0);
      expect(proj.point.lng, closeTo(b.lng, 1e-9));
    });

    test('un punto antes del inicio se recorta al extremo (t = 0)', () {
      const GeoPoint before = GeoPoint(18.4800, -69.9300);
      final SegmentProjection proj = projectOnSegment(before, a, b);
      expect(proj.t, 0.0);
    });

    test('no revienta con un segmento degenerado', () {
      final SegmentProjection proj =
          projectOnSegment(const GeoPoint(18.481, -69.92), a, a);
      expect(proj.t, 0);
      expect(proj.distanceMeters, greaterThan(0));
    });
  });

  test('polylineLengthMeters suma los segmentos', () {
    const List<GeoPoint> points = <GeoPoint>[
      GeoPoint(18.4800, -69.9200),
      GeoPoint(18.4800, -69.9100),
      GeoPoint(18.4800, -69.9000),
    ];
    final double total = polylineLengthMeters(points);
    expect(
      total,
      closeTo(
        distanceMeters(points[0], points[1]) +
            distanceMeters(points[1], points[2]),
        0.001,
      ),
    );
  });
}
