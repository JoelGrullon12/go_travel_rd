import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/domain/geo/geo_math.dart';
import 'package:go_travel_rd/domain/geo/geo_point.dart';
import 'package:go_travel_rd/domain/models/trip_plan.dart';
import 'package:go_travel_rd/domain/tracking/trip_geometry.dart';

import 'support/demo_trip_plans.dart';
import 'support/test_plans.dart';

void main() {
  group('TripGeometry sobre un plan recto conocido', () {
    final TripPlan plan = straightTestPlan();
    final TripGeometry geometry = TripGeometry.from(plan);

    test('la distancia total es la suma de los tramos', () {
      expect(geometry.totalMeters, closeTo(1889, 12));
    });

    test('las distancias acumuladas son monótonas crecientes', () {
      for (int i = 1; i < geometry.cumulative.length; i++) {
        expect(geometry.cumulative[i], greaterThanOrEqualTo(geometry.cumulative[i - 1]));
      }
    });

    test('los límites de cada tramo encajan sin huecos', () {
      expect(geometry.legStartMeters[0], 0);
      for (int i = 1; i < plan.legs.length; i++) {
        expect(
          geometry.legStartMeters[i],
          closeTo(geometry.legEndMeters[i - 1], 0.001),
        );
      }
      expect(geometry.legEndMeters.last, closeTo(geometry.totalMeters, 0.001));
    });

    test('pointAt(0) es el origen y pointAt(total) el destino', () {
      expect(distanceMeters(geometry.pointAt(0), plan.origin), closeTo(0, 0.5));
      expect(
        distanceMeters(geometry.pointAt(geometry.totalMeters), plan.destination),
        closeTo(0, 0.5),
      );
    });

    test('pointAt avanza de forma consistente con la distancia pedida', () {
      final GeoPoint at500 = geometry.pointAt(500);
      final GeoPoint at900 = geometry.pointAt(900);
      expect(distanceMeters(at500, at900), closeTo(400, 5));
    });

    test('legIndexAt identifica el tramo correcto', () {
      expect(geometry.legIndexAt(50), 0); // caminata inicial
      expect(geometry.legIndexAt(800), 1); // metro
      expect(geometry.legIndexAt(geometry.totalMeters - 50), 2); // caminata final
    });

    test('las paradas caen en su distancia acumulada esperada', () {
      // Parada A al inicio del tramo de metro (200 m), D al final (~1689 m).
      expect(geometry.meterOfStop(1, 0), closeTo(200, 5));
      expect(geometry.meterOfStop(1, 1), closeTo(700, 8));
      expect(geometry.meterOfStop(1, 2), closeTo(1200, 8));
      expect(geometry.meterOfStop(1, 3), closeTo(1689, 12));
    });

    test('upcomingStopsOfLeg descarta las paradas ya pasadas', () {
      expect(geometry.upcomingStopsOfLeg(1, 210).length, 3); // faltan B, C, D
      expect(geometry.upcomingStopsOfLeg(1, 750).length, 2); // faltan C, D
      expect(geometry.upcomingStopsOfLeg(1, 1250).length, 1); // falta D
      expect(geometry.upcomingStopsOfLeg(1, 1800), isEmpty);
    });

    test('sliceUpTo y sliceFrom se reparten el recorrido sin perder largo', () {
      final double done = polylineLengthMeters(geometry.sliceUpTo(700));
      final double pending = polylineLengthMeters(geometry.sliceFrom(700));
      expect(done, closeTo(700, 2));
      expect(done + pending, closeTo(geometry.totalMeters, 3));
    });
  });

  group('TripGeometry sobre el plan real con transbordo', () {
    final TripPlan plan = DemoTripPlans.villaMellaLosMina();
    final TripGeometry geometry = TripGeometry.from(plan);

    test('el viaje completo mide lo razonable para Villa Mella → Los Mina', () {
      // ~11 km por vía: coherente con el recorrido real del Metro.
      expect(geometry.totalMeters, greaterThan(9000));
      expect(geometry.totalMeters, lessThan(16000));
    });

    test('todos los tramos tienen longitud positiva', () {
      for (int i = 0; i < plan.legs.length; i++) {
        expect(
          geometry.legEndMeters[i] - geometry.legStartMeters[i],
          greaterThan(0),
          reason: 'El tramo $i (${plan.legs[i].id}) quedó con longitud cero',
        );
      }
    });

    test('las paradas del metro están ordenadas a lo largo del recorrido', () {
      for (int legIndex = 0; legIndex < plan.legs.length; legIndex++) {
        final List<double> meters = geometry.stopMeters[legIndex];
        for (int i = 1; i < meters.length; i++) {
          expect(
            meters[i],
            greaterThan(meters[i - 1]),
            reason: 'Paradas desordenadas en el tramo $legIndex',
          );
        }
      }
    });
  });
}
