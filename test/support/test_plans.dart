import 'package:go_travel_rd/domain/geo/geo_point.dart';
import 'package:go_travel_rd/domain/models/transport_mode.dart';
import 'package:go_travel_rd/domain/models/trip_plan.dart';
import 'package:go_travel_rd/domain/tracking/route_matcher.dart';
import 'package:go_travel_rd/domain/tracking/trip_geometry.dart';

/// Construye un emparejamiento sintético a X metros del inicio, como si el
/// usuario estuviera justo ahí y perfectamente sobre la ruta. Permite probar
/// ETA e instrucciones sin tener que simular el GPS.
RouteMatch matchAt(
  TripGeometry geometry,
  double meters, {
  double offRouteM = 0,
}) =>
    RouteMatch(
      snapped: geometry.pointAt(meters),
      distanceFromRouteMeters: offRouteM,
      traveledMeters: meters,
      legIndex: geometry.legIndexAt(meters),
      segmentIndex: 0,
    );

/// Planes sintéticos con distancias conocidas de antemano.
///
/// Se usan geometrías "de laboratorio" (tramos rectos sobre un mismo paralelo)
/// en lugar de los planes reales, para poder afirmar en las pruebas cosas como
/// "a los 1000 m debe decir «prepárate»" sin depender de coordenadas reales.
/// Los planes reales se prueban aparte, en trip_tracker_test.dart.

/// A la latitud 18.48°, un grado de longitud mide ~105 580 m.
const double kMetersPerLngDegree = 105580;

GeoPoint eastOf(GeoPoint origin, double meters) =>
    GeoPoint(origin.lat, origin.lng + meters / kMetersPerLngDegree);

/// Plan recto de 3 tramos: caminar 200 m → metro 1489 m (4 paradas) →
/// caminar 200 m. Total ≈ 1889 m.
TripPlan straightTestPlan() {
  const GeoPoint start = GeoPoint(18.4800, -69.9200);
  final GeoPoint board = eastOf(start, 200);
  final GeoPoint stopB = eastOf(board, 500);
  final GeoPoint stopC = eastOf(board, 1000);
  final GeoPoint alight = eastOf(board, 1489);
  final GeoPoint destination = eastOf(alight, 200);

  return TripPlan(
    id: 'test-straight',
    originName: 'Origen',
    destinationName: 'Destino',
    legs: <TripLeg>[
      TripLeg(
        id: 'w1',
        mode: TransportMode.walk,
        path: <GeoPoint>[start, board],
      ),
      TripLeg(
        id: 'm1',
        mode: TransportMode.metro,
        lineName: 'Línea 1',
        headsign: 'Este',
        path: <GeoPoint>[board, stopB, stopC, alight],
        stops: <TripStop>[
          TripStop(id: 'a', name: 'Parada A', position: board),
          TripStop(id: 'b', name: 'Parada B', position: stopB),
          TripStop(id: 'c', name: 'Parada C', position: stopC),
          TripStop(id: 'd', name: 'Parada D', position: alight),
        ],
        fareDop: 20,
      ),
      TripLeg(
        id: 'w2',
        mode: TransportMode.walk,
        path: <GeoPoint>[alight, destination],
      ),
    ],
  );
}

/// Plan que **se dobla sobre sí mismo**: va 1000 m al este y vuelve 1000 m al
/// oeste por una línea paralela a solo 30 m.
///
/// Reproduce en pequeño el problema real del Metro en Juan Pablo Duarte, donde
/// la ruta se cruza consigo misma y una búsqueda global del punto más cercano
/// se equivoca de tramo.
TripPlan doublingBackPlan() {
  const GeoPoint a = GeoPoint(18.4800, -69.9200);
  final GeoPoint b = eastOf(a, 1000);
  const GeoPoint c = GeoPoint(18.48027, -69.9105); // 30 m al norte de b
  final GeoPoint d = GeoPoint(c.lat, a.lng);

  return TripPlan(
    id: 'test-doubling',
    originName: 'Ida',
    destinationName: 'Vuelta',
    legs: <TripLeg>[
      TripLeg(id: 'out', mode: TransportMode.walk, path: <GeoPoint>[a, b]),
      TripLeg(id: 'back', mode: TransportMode.walk, path: <GeoPoint>[c, d]),
    ],
  );
}
