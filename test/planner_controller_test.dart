import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:go_travel_rd/application/data_providers.dart';
import 'package:go_travel_rd/application/planner_controller.dart';
import 'package:go_travel_rd/domain/geo/geo_point.dart';
import 'package:go_travel_rd/domain/models/trip_plan.dart';
import 'package:go_travel_rd/domain/routing/route_engine.dart';
import 'package:go_travel_rd/models/route.dart';

import 'support/test_plans.dart';

/// Línea recta con N estaciones sobre un mismo paralelo.
Route _line(String id, List<(GeoPoint, String)> points) => Route(
      id: id,
      name: id,
      transportTypeId: 'metro',
      province: 'Distrito Nacional',
      price: 20,
      active: true,
      hasFixedStations: true,
      stations: <RouteStation>[
        for (int i = 0; i < points.length; i++)
          RouteStation(
            stationId: '$id-$i',
            order: i,
            name: points[i].$2,
            location: fs.GeoPoint(points[i].$1.lat, points[i].$1.lng),
          ),
      ],
    );

void main() {
  late ProviderContainer container;
  late List<Route> routes;

  setUp(() {
    routes = <Route>[];
    container = ProviderContainer(
      overrides: <Override>[
        routesProvider.overrideWith((ref) async => routes),
        maxWalkDistanceProvider.overrideWith(
          (ref) async => kDefaultMaxWalkMeters,
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  PlannerController controller() =>
      container.read(plannerControllerProvider.notifier);

  PlannerState state() => container.read(plannerControllerProvider);

  group('PlannerController (override de distancia a pie en dos fases)', () {
    test('sin override usa la distancia del usuario: 3 km > 1500 m → fallo',
        () async {
      final GeoPoint a1 = GeoPoint(18.5000, -69.9000);
      final GeoPoint a2 = eastOf(a1, 1000);
      routes = <Route>[_line('m1', <(GeoPoint, String)>[(a1, 'A1'), (a2, 'A2')])];

      await controller().plan(
        origin: eastOf(a1, -3000),
        destination: eastOf(a2, 3000),
      );

      expect(state().plan, isNull);
      expect(state().failure, RoutePlanFailure.noStationsNearOrigin);
      expect(state().isComputing, isFalse);
    });

    test('fase 1 (cap 5 km) resuelve cuando la estación queda a ~3 km',
        () async {
      final GeoPoint a1 = GeoPoint(18.5000, -69.9000);
      final GeoPoint a2 = eastOf(a1, 1000);
      routes = <Route>[_line('m1', <(GeoPoint, String)>[(a1, 'A1'), (a2, 'A2')])];

      await controller().plan(
        origin: eastOf(a1, -3000),
        destination: eastOf(a2, 3000),
        overrideMaxWalk: true,
      );

      expect(state().failure, isNull);
      final TripPlan? plan = state().plan;
      expect(plan, isNotNull);
      expect(plan!.legs[0].distanceMeters, closeTo(3000, 50));
      expect(plan.legs[1].stops.first.id, 'm1-0');
      expect(plan.legs[1].stops.last.id, 'm1-1');
    });

    test('fase 2 (∞) alcanza una estación a ~8 km (supera el cap de 5 km)',
        () async {
      final GeoPoint a1 = GeoPoint(18.5000, -69.9000);
      final GeoPoint a2 = eastOf(a1, 1000);
      routes = <Route>[_line('m1', <(GeoPoint, String)>[(a1, 'A1'), (a2, 'A2')])];

      await controller().plan(
        origin: eastOf(a1, -8000),
        destination: eastOf(a2, 8000),
        overrideMaxWalk: true,
      );

      expect(state().failure, isNull);
      final TripPlan? plan = state().plan;
      expect(plan, isNotNull);
      expect(plan!.legs[0].distanceMeters, closeTo(8000, 80));
    });

    test('redes desconectadas con override: baja en la estación alcanzable y '
        'camina el resto, sin aplicar el límite del usuario', () async {
      final GeoPoint a1 = GeoPoint(18.5000, -69.9000);
      final GeoPoint a2 = eastOf(a1, 1000);
      final GeoPoint b1 = eastOf(a2, 2000); // >400 m de separación: sin enlace
      final GeoPoint b2 = eastOf(b1, 1000);
      routes = <Route>[
        _line('m1', <(GeoPoint, String)>[(a1, 'A1'), (a2, 'A2')]),
        _line('m2', <(GeoPoint, String)>[(b1, 'B1'), (b2, 'B2')]),
      ];

      await controller().plan(
        origin: a1,
        destination: eastOf(b2, 200),
        overrideMaxWalk: true,
      );

      expect(state().failure, isNull);
      final TripPlan? plan = state().plan;
      expect(plan, isNotNull);
      // El destino cae cerca de una red inalcanzable: el plan baja en la única
      // estación alcanzable (a2) y completa el resto a pie. La caminata final
      // supera los 1500 m del usuario porque el override quitó el límite.
      expect(plan!.legs[1].stops.last.id, 'm1-1');
      expect(plan.legs.last.mode.isWalking, isTrue);
      expect(plan.legs.last.distanceMeters, greaterThan(1500));
    });

    test('cancel() descarta el resultado pendiente y vuelve a idle', () async {
      final GeoPoint a1 = GeoPoint(18.5000, -69.9000);
      final GeoPoint a2 = eastOf(a1, 1000);
      routes = <Route>[_line('m1', <(GeoPoint, String)>[(a1, 'A1'), (a2, 'A2')])];

      final Future<void> pending = controller().plan(
        origin: eastOf(a1, -3000),
        destination: eastOf(a2, 3000),
        overrideMaxWalk: true,
      );
      expect(state().isComputing, isTrue);

      controller().cancel();
      expect(state().isComputing, isFalse);

      await pending;
      expect(state().plan, isNull);
      expect(state().failure, isNull);
      expect(state().isComputing, isFalse);
    });
  });
}
