import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/data/metro_stations.dart';
import 'package:go_travel_rd/domain/geo/geo_point.dart';
import 'package:go_travel_rd/domain/models/transport_mode.dart';
import 'package:go_travel_rd/domain/models/trip_plan.dart';
import 'package:go_travel_rd/domain/routing/route_engine.dart';
import 'package:go_travel_rd/models/route.dart';

import 'support/test_plans.dart';

/// Convierte una lista de [MetroStation] en una [Route] de Firestore con las
/// mismas coordenadas (las estaciones del fixture imitan el backend real).
Route _metroRoute({
  required String id,
  required String name,
  required List<MetroStation> stations,
  double price = 20,
  double avgMinutesPerKm = 1.5,
}) {
  return Route(
    id: id,
    name: name,
    transportTypeId: 'metro',
    province: 'Distrito Nacional',
    price: price,
    avgMinutesPerKm: avgMinutesPerKm,
    active: true,
    hasFixedStations: true,
    stations: <RouteStation>[
      for (int i = 0; i < stations.length; i++)
        RouteStation(
          stationId: stations[i].id,
          order: i,
          name: stations[i].name,
          location: fs.GeoPoint(
            stations[i].position.lat,
            stations[i].position.lng,
          ),
        ),
    ],
  );
}

/// L2 con la estación de transbordo usando el MISMO id que L1 (en Firestore la
/// estación Juan Pablo Duarte es un solo documento compartido por ambas líneas).
List<MetroStation> _l2SharedTransfer() => <MetroStation>[
  for (final MetroStation s in kMetroLine2)
    s.id == 'l2-13'
        ? MetroStation('l1-10', s.name, s.position, s.line, isTransfer: true)
        : s,
];

List<Route> _metroNetwork() => <Route>[
  _metroRoute(id: 'metro-line-1', name: 'Metro Línea 1', stations: kMetroLine1),
  _metroRoute(
    id: 'metro-line-2',
    name: 'Metro Línea 2',
    stations: _l2SharedTransfer(),
  ),
];

RoutePlanOutcome _plan(
  GeoPoint origin,
  GeoPoint destination, {
  List<Route> routes = const <Route>[],
  double maxWalkMeters = 1500,
}) => const RouteEngine().plan(
  origin: origin,
  destination: destination,
  routes: routes.isEmpty ? _metroNetwork() : routes,
  maxWalkMeters: maxWalkMeters,
);

void main() {
  group('RouteEngine', () {
    test('plan simple: caminar → metro → caminar, sin transbordos', () {
      final GeoPoint origin = eastOf(kMetroLine1.first.position, -200);
      final GeoPoint destination = eastOf(kMetroLine1[4].position, 200);

      final RoutePlanOutcome outcome = _plan(origin, destination);

      expect(outcome.failure, isNull);
      final TripPlan plan = outcome.plan!;
      expect(plan.transferCount, 0);
      expect(plan.legs.length, 3);
      expect(plan.legs[0].mode, TransportMode.walk);
      expect(plan.legs[1].mode, TransportMode.metro);
      expect(plan.legs[2].mode, TransportMode.walk);

      // Recorre L1 en su orden, de l1-01 a l1-05.
      expect(plan.legs[1].stops.first.id, 'l1-01');
      expect(plan.legs[1].stops.last.id, 'l1-05');
      expect(plan.legs[1].lineColorHex, kLine1Color);

      // Totales.
      expect(plan.totalFareDop, 20);
      expect(plan.legs[1].distanceMeters, greaterThan(3000));
      expect(plan.totalDistanceMeters, greaterThan(3000));

      // Sin geocodificación, la etiqueta usa la estación más cercana.
      expect(plan.originName, 'Cerca de Mamá Tingó');
    });

    test('sin estaciones a pie del origen → noStationsNearOrigin', () {
      const GeoPoint origin = GeoPoint(19.5, -70.5);
      final GeoPoint destination = eastOf(kMetroLine1.first.position, 200);

      final RoutePlanOutcome outcome = _plan(origin, destination);

      expect(outcome.plan, isNull);
      expect(outcome.failure, RoutePlanFailure.noStationsNearOrigin);
    });

    test('sin estaciones a pie del destino → noStationsNearDestination', () {
      final GeoPoint origin = eastOf(kMetroLine1.first.position, 200);
      const GeoPoint destination = GeoPoint(18.1, -69.5);

      final RoutePlanOutcome outcome = _plan(origin, destination);

      expect(outcome.plan, isNull);
      expect(outcome.failure, RoutePlanFailure.noStationsNearDestination);
    });

    test('transbordo L1 → L2 con pasillo a pie de 0 m', () {
      final GeoPoint origin = eastOf(kMetroLine1.first.position, -200);
      final GeoPoint destination = eastOf(kMetroLine2[18].position, 200);

      final RoutePlanOutcome outcome = _plan(origin, destination);

      expect(outcome.failure, isNull);
      final TripPlan plan = outcome.plan!;
      expect(plan.transferCount, 1);
      expect(plan.legs.length, 5);
      expect(plan.legs[1].lineName, 'Metro Línea 1');
      expect(plan.legs[3].lineName, 'Metro Línea 2');
      expect(plan.legs[2].mode, TransportMode.walk);
      expect(plan.legs[2].distanceMeters, lessThan(1));

      // El transbordo ocurre en la estación compartida (id l1-10).
      expect(plan.legs[1].stops.last.id, 'l1-10');
      expect(plan.legs[3].stops.first.id, 'l1-10');
      expect(plan.legs[1].stops.last.isTransfer, isTrue);
      expect(plan.legs[3].stops.first.isTransfer, isTrue);
      expect(plan.legs[3].lineColorHex, kLine2Color);
      expect(plan.totalFareDop, 40);
    });

    test(
      'recorre la línea en ambos sentidos (order se recorre hacia atrás)',
      () {
        final GeoPoint origin = eastOf(kMetroLine1.last.position, 200);
        final GeoPoint destination = eastOf(kMetroLine1.first.position, 200);

        final RoutePlanOutcome outcome = _plan(origin, destination);

        expect(outcome.failure, isNull);
        final TripPlan plan = outcome.plan!;
        expect(plan.legs[1].stops.first.id, 'l1-16');
        expect(plan.legs[1].stops.last.id, 'l1-01');
      },
    );

    test('elige los candidatos más cercanos (objetivo: menor tiempo)', () {
      final GeoPoint origin = kMetroLine1[1].position; // justo en l1-02
      final GeoPoint destination = eastOf(kMetroLine1[3].position, 200);

      final RoutePlanOutcome outcome = _plan(origin, destination);

      expect(outcome.failure, isNull);
      final TripPlan plan = outcome.plan!;
      expect(plan.legs[1].stops.first.id, 'l1-02');
      expect(plan.legs[1].stops.last.id, 'l1-04');
    });

    test('origen y destino cerca → plan solo a pie', () {
      // En el hueco entre l1-02 y l1-03 (~1.1 km), a ~600 m de cada estación.
      final GeoPoint mid = GeoPoint(18.5345, -69.9064);
      final GeoPoint origin = eastOf(mid, -50);
      final GeoPoint destination = eastOf(mid, 50);

      final RoutePlanOutcome outcome = _plan(origin, destination);

      expect(outcome.failure, isNull);
      final TripPlan plan = outcome.plan!;
      expect(plan.legs.length, 1);
      expect(plan.legs.single.mode, TransportMode.walk);
      expect(plan.transferCount, 0);
      expect(plan.totalDistanceMeters, closeTo(100, 5));
    });

    test('redes desconectadas → noRoute', () {
      Route miniRoute(String id, List<(GeoPoint, String)> points) => Route(
        id: id,
        name: id,
        transportTypeId: 'omsa',
        province: 'Distrito Nacional',
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

      final List<Route> disjoint = <Route>[
        miniRoute('r1', <(GeoPoint, String)>[
          (GeoPoint(18.5000, -69.9000), 'S1'),
          (GeoPoint(18.5000, -69.8950), 'S2'),
        ]),
        miniRoute('r2', <(GeoPoint, String)>[
          (GeoPoint(18.4000, -70.0000), 'S3'),
          (GeoPoint(18.4000, -70.0050), 'S4'),
        ]),
      ];

      final RoutePlanOutcome outcome = _plan(
        const GeoPoint(18.5000, -69.9000),
        const GeoPoint(18.4000, -70.0050),
        routes: disjoint,
      );

      expect(outcome.plan, isNull);
      expect(outcome.failure, RoutePlanFailure.noRoute);
    });

    test('una ruta desactivada o sin paradas no entra al grafo', () {
      final Route inactive = Route(
        id: 'metro-line-1',
        name: 'Metro Línea 1',
        transportTypeId: 'metro',
        province: 'Distrito Nacional',
        price: 20,
        avgMinutesPerKm: 1.5,
        active: false,
        hasFixedStations: true,
        stations: <RouteStation>[
          for (int i = 0; i < kMetroLine1.length; i++)
            RouteStation(
              stationId: kMetroLine1[i].id,
              order: i,
              name: kMetroLine1[i].name,
              location: fs.GeoPoint(
                kMetroLine1[i].position.lat,
                kMetroLine1[i].position.lng,
              ),
            ),
        ],
      );
      final Route withoutStops = Route(
        id: 'solo',
        name: 'Sin paradas',
        transportTypeId: 'omsa',
        province: 'Distrito Nacional',
        active: true,
        hasFixedStations: false,
      );

      final RoutePlanOutcome outcome = _plan(
        eastOf(kMetroLine1.first.position, -200),
        eastOf(kMetroLine1[4].position, 200),
        routes: <Route>[inactive, withoutStops],
      );

      // Sin rutas válidas, no hay nada que calcular.
      expect(outcome.plan, isNull);
      expect(outcome.failure, RoutePlanFailure.noRoute);
    });

    test('transbordo a pie entre rutas distintas (≤400 m) suma dos tarifas', () {
      Route line(
        String id,
        String type,
        double price,
        List<(GeoPoint, String)> points,
      ) => Route(
        id: id,
        name: id,
        transportTypeId: type,
        province: 'Distrito Nacional',
        price: price,
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

      // Ruta A (metro): A1 → A2. Ruta B (omsa): B1 → B2. A2 y B1 quedan a
      // ~200 m: el motor conecta los dos sistemas caminando (kTransferWalkMeters).
      final GeoPoint a1 = GeoPoint(18.5000, -69.9000);
      final GeoPoint a2 = eastOf(a1, 1000);
      final GeoPoint b1 = eastOf(a2, 200);
      final GeoPoint b2 = eastOf(b1, 1000);

      final RoutePlanOutcome outcome = _plan(
        eastOf(a1, -200),
        eastOf(b2, 200),
        routes: <Route>[
          line('metro-a', 'metro', 20, <(GeoPoint, String)>[
            (a1, 'A1'),
            (a2, 'A2'),
          ]),
          line('omsa-b', 'omsa', 25, <(GeoPoint, String)>[
            (b1, 'B1'),
            (b2, 'B2'),
          ]),
        ],
      );

      expect(outcome.failure, isNull);
      final TripPlan plan = outcome.plan!;
      expect(plan.transferCount, 1);
      expect(plan.legs.length, 5);
      expect(plan.legs[1].lineName, 'metro-a');
      expect(plan.legs[3].lineName, 'omsa-b');

      // El tramo de transbordo camina de A2 a B1 con distancia real, no 0 m.
      final TripLeg transfer = plan.legs[2];
      expect(transfer.mode, TransportMode.walk);
      expect(transfer.distanceMeters, closeTo(200, 5));

      // Las paradas limítrofes se marcan como transbordo para el badge de la UI.
      expect(plan.legs[1].stops.last.isTransfer, isTrue);
      expect(plan.legs[3].stops.first.isTransfer, isTrue);

      // Cada sistema cobra su pasaje por separado.
      expect(plan.totalFareDop, 45);
    });

    test('estaciones a >400 m entre sistemas → no hay conexión (noRoute)', () {
      Route line(String id, String type, List<(GeoPoint, String)> points) =>
          Route(
            id: id,
            name: id,
            transportTypeId: type,
            province: 'Distrito Nacional',
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

      final GeoPoint a1 = GeoPoint(18.5000, -69.9000);
      final GeoPoint a2 = eastOf(a1, 1000);
      final GeoPoint b1 = eastOf(a2, 500); // fuera de los 400 m de transbordo
      final GeoPoint b2 = eastOf(b1, 1000);

      final RoutePlanOutcome outcome = _plan(
        eastOf(a1, -200),
        eastOf(b2, 200),
        routes: <Route>[
          line('metro-a', 'metro', <(GeoPoint, String)>[
            (a1, 'A1'),
            (a2, 'A2'),
          ]),
          line('omsa-b', 'omsa', <(GeoPoint, String)>[(b1, 'B1'), (b2, 'B2')]),
        ],
      );

      expect(outcome.plan, isNull);
      expect(outcome.failure, RoutePlanFailure.noRoute);
    });

    test('override: sin límite a pie se encuentra una estación lejana', () {
      // La estación más cercana queda a ~2.2 km al norte del origen: con el
      // límite por defecto (1500 m) no hay candidatos; con override (∞) el
      // motor llega caminando a la estación más cercana (l1-01, la del extremo
      // norte de la línea).
      final GeoPoint origin = GeoPoint(
        kMetroLine1.first.position.lat + 0.02,
        kMetroLine1.first.position.lng,
      );
      final GeoPoint destination = eastOf(kMetroLine1[4].position, 200);

      final RoutePlanOutcome blocked = _plan(origin, destination);
      expect(blocked.plan, isNull);
      expect(blocked.failure, RoutePlanFailure.noStationsNearOrigin);

      final RoutePlanOutcome overridden = _plan(
        origin,
        destination,
        maxWalkMeters: double.infinity,
      );
      expect(overridden.failure, isNull);
      final TripPlan plan = overridden.plan!;
      expect(plan.legs[1].stops.first.id, 'l1-01');
      // La caminata de acceso ya no está limitada a la distancia del usuario.
      expect(plan.legs[0].distanceMeters, greaterThan(1500));
    });

    test('override con transbordo entre sistemas resuelve en una sola pasada',
        () {
      Route line(String id, String type, double price,
              List<(GeoPoint, String)> points) =>
          Route(
            id: id,
            name: id,
            transportTypeId: type,
            province: 'Distrito Nacional',
            price: price,
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

      // Puntos remotos: la estación más cercana queda a ~6 km (el usuario
      // aceptó planificar superando su distancia). Con ∞, todos los nodos son
      // candidatos y además hay un transbordo a pie Metro→OMSA a 200 m. Es el
      // caso que con el doble bucle de Dijkstras disparaba B×A ejecuciones.
      final GeoPoint a1 = GeoPoint(18.5000, -69.9000);
      final GeoPoint a2 = eastOf(a1, 1000);
      final GeoPoint b1 = eastOf(a2, 200);
      final GeoPoint b2 = eastOf(b1, 1000);
      final GeoPoint origin = eastOf(a1, -6000);
      final GeoPoint destination = eastOf(b2, 6000);

      final RoutePlanOutcome outcome = _plan(
        origin,
        destination,
        maxWalkMeters: double.infinity,
        routes: <Route>[
          line('metro-a', 'metro', 20, <(GeoPoint, String)>[(a1, 'A1'), (a2, 'A2')]),
          line('omsa-b', 'omsa', 25, <(GeoPoint, String)>[(b1, 'B1'), (b2, 'B2')]),
        ],
      );

      expect(outcome.failure, isNull);
      final TripPlan plan = outcome.plan!;
      expect(plan.transferCount, 1);
      expect(plan.legs.length, 5);
      expect(plan.legs[1].stops.first.id, 'metro-a-0');
      expect(plan.legs[3].stops.last.id, 'omsa-b-1');
      // La caminata de acceso supera la distancia máxima del usuario (1500 m).
      expect(plan.legs[0].distanceMeters, greaterThan(5000));
      expect(plan.legs[2].distanceMeters, closeTo(200, 5));
      expect(plan.totalFareDop, 45);
    });

    test('no pide una estación lejana cuando la cercana conecta (selección de '
        'abordaje por menor tiempo)', () {
      // Con el mismo override (∞) pero estaciones cercanas, el motor elige la
      // estación más rápida, no la más lejana: aborda l1-01 a ~2.2 km en vez
      // de caminar hasta otra estación con un trayecto más largo.
      final GeoPoint origin = GeoPoint(
        kMetroLine1.first.position.lat + 0.02,
        kMetroLine1.first.position.lng,
      );
      final GeoPoint destination = eastOf(kMetroLine1[4].position, 200);

      final RoutePlanOutcome outcome =
          _plan(origin, destination, maxWalkMeters: double.infinity);
      expect(outcome.failure, isNull);
      expect(outcome.plan!.legs[1].stops.first.id, 'l1-01');
    });
  });
}
