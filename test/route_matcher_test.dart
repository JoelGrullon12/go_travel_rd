import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/domain/geo/geo_math.dart';
import 'package:go_travel_rd/domain/geo/geo_point.dart';
import 'package:go_travel_rd/domain/tracking/route_matcher.dart';
import 'package:go_travel_rd/domain/tracking/trip_geometry.dart';

import 'support/test_plans.dart';

void main() {
  group('RouteMatcher en un recorrido simple', () {
    final TripGeometry geometry = TripGeometry.from(straightTestPlan());
    final RouteMatcher matcher = RouteMatcher(geometry);

    test('un punto exactamente sobre la ruta reporta desviación ~0', () {
      final GeoPoint onRoute = geometry.pointAt(600);
      final RouteMatch match = matcher.match(onRoute);
      expect(match.distanceFromRouteMeters, closeTo(0, 1));
      expect(match.traveledMeters, closeTo(600, 2));
    });

    test('un punto desplazado lateralmente conserva el avance', () {
      final GeoPoint offRoute = offsetMeters(geometry.pointAt(600), 40, 0);
      final RouteMatch match = matcher.match(offRoute);
      expect(match.distanceFromRouteMeters, closeTo(40, 3));
      expect(match.traveledMeters, closeTo(600, 5));
    });

    test('identifica el tramo en el que va el usuario', () {
      expect(matcher.match(geometry.pointAt(100)).legIndex, 0);
      expect(matcher.match(geometry.pointAt(900)).legIndex, 1);
      expect(
        matcher.match(geometry.pointAt(geometry.totalMeters - 60)).legIndex,
        2,
      );
    });

    test('nunca devuelve un avance fuera del recorrido', () {
      final RouteMatch far =
          matcher.match(offsetMeters(geometry.pointAt(0), 5000, 180));
      expect(far.traveledMeters, greaterThanOrEqualTo(0));
      expect(far.traveledMeters, lessThanOrEqualTo(geometry.totalMeters));
    });
  });

  group('RouteMatcher cuando la ruta se cruza consigo misma', () {
    // Este es el caso que rompe un emparejador ingenuo: el tramo de ida y el de
    // vuelta pasan a 30 m uno del otro. Sin ventana de búsqueda, al usuario le
    // saltaría el progreso de golpe al pasar por ahí — que es justo lo que
    // ocurre en el Metro a la altura de Juan Pablo Duarte.
    final TripGeometry geometry = TripGeometry.from(doublingBackPlan());
    final RouteMatcher matcher = RouteMatcher(geometry);

    // Punto ambiguo: cerca de la ida, pero también de la vuelta.
    final GeoPoint ambiguous = geometry.pointAt(500);

    test('sin contexto previo elige el punto globalmente más cercano', () {
      final RouteMatch match = matcher.match(ambiguous);
      expect(match.traveledMeters, lessThan(700),
          reason: 'Debería resolver al tramo de ida');
    });

    test('con avance previo en la vuelta se queda en la vuelta', () {
      final RouteMatch match =
          matcher.match(ambiguous, previousTraveledMeters: 1500);
      expect(
        match.traveledMeters,
        greaterThan(1000),
        reason: 'La ventana de búsqueda debe impedir el salto al tramo de ida',
      );
    });

    test('avanzar de forma continua nunca hace retroceder el progreso', () {
      double? previous;
      double last = 0;
      for (double m = 0; m <= geometry.totalMeters; m += 25) {
        final RouteMatch match = matcher.match(
          geometry.pointAt(m),
          previousTraveledMeters: previous,
        );
        expect(
          match.traveledMeters,
          greaterThanOrEqualTo(last - 40),
          reason: 'Retroceso inesperado al llegar a $m m',
        );
        last = match.traveledMeters;
        previous = match.traveledMeters;
      }
      expect(last, closeTo(geometry.totalMeters, 30));
    });

  });

  test('si el usuario aparece muy lejos de la ventana, se rehace la búsqueda',
      () {
    // Simula reabrir la app tras un rato cerrada: el avance previo dice "casi
    // al final", pero la posición real está al principio del recorrido. La
    // ventana ya no describe la realidad y hay que descartarla.
    final TripGeometry geometry = TripGeometry.from(straightTestPlan());
    final RouteMatcher matcher = RouteMatcher(geometry);

    final RouteMatch match = matcher.match(
      geometry.pointAt(30),
      previousTraveledMeters: 1800,
    );
    expect(match.distanceFromRouteMeters, lessThan(50));
    expect(match.traveledMeters, lessThan(200));
  });
}
