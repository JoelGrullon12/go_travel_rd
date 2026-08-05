import '../../data/metro_stations.dart'
    show kConchoColor, kLine1Color, kLine2Color, kWalkColor;
import '../../models/route.dart';
import '../geo/geo_math.dart';
import '../geo/geo_point.dart';
import '../models/transport_mode.dart';
import '../models/trip_plan.dart';
import 'station_graph.dart';

/// Color por defecto de las líneas de buses (OMSA/corredores/teleférico).
///
/// Firestore no trae el color de cada ruta, así que las líneas del Metro usan
/// su color oficial ([kLine1Color]/[kLine2Color]) y el resto cae aquí. Es una
/// aproximación del equipo hasta que el color viva en el dato.
const int kBusRouteColor = 0xFF2FA8A0;

/// Color de la polilínea de una ruta.
int lineColorForRoute(Route route) {
  if (route.id == 'metro-line-1') return kLine1Color;
  if (route.id == 'metro-line-2') return kLine2Color;
  return switch (route.transportTypeId) {
    'metro' => kLine1Color,
    'omsa' || 'corredor' || 'teleferico' => kBusRouteColor,
    _ => kConchoColor,
  };
}

/// Motivos por los que el motor no pudo producir un plan.
enum RoutePlanFailure {
  /// No hay ninguna estación alcanzable a pie desde el origen.
  noStationsNearOrigin,

  /// No hay ninguna estación alcanzable a pie desde el destino.
  noStationsNearDestination,

  /// Hay estaciones cerca de ambos extremos, pero ninguna ruta conecta esos
  /// puntos (ej. OMSA↔Metro, que hoy no comparten estación).
  noRoute,
}

/// Resultado del cálculo A→B: un plan listo para el Hito 4, o el motivo de
/// fallo para mostrarlo en la UI.
class RoutePlanOutcome {
  const RoutePlanOutcome.success(TripPlan this.plan) : failure = null;
  const RoutePlanOutcome.failure(RoutePlanFailure this.failure) : plan = null;

  final TripPlan? plan;
  final RoutePlanFailure? failure;
}

/// Motor de cálculo de ruta A→B (Hito 2).
///
/// Lógica pura, sin Flutter: se prueba con `flutter test`. Opera sobre las
/// rutas de Firestore ([Route]) y devuelve un [TripPlan] — el mismo contrato
/// que consume el seguimiento en tiempo real (Hito 4).
///
/// ## Objetivo
/// Menor tiempo total estimado:
///   caminata al origen + suma de minutos por tramo + caminata al destino.
///
/// ## Cómo busca
/// 1. Estaciones alcanzables a pie (≤ `maxWalkMeters`) desde origen y destino.
/// 2. Por cada par (abordaje, bajada), Dijkstra sobre el [StationGraph].
/// 3. Gana el plan de menor costo. Los transbordos —caminatas cortas en una
///    estación compartida por dos rutas— se suman como tramos a pie.
/// 4. Si origen y destino están lo bastante cerca, caminar directo compite con
///    el transporte y puede ganarle.
class RouteEngine {
  const RouteEngine();

  RoutePlanOutcome plan({
    required GeoPoint origin,
    required GeoPoint destination,
    required List<Route> routes,
    required double maxWalkMeters,
  }) {
    final List<Route> fixedRoutes = routes
        .where((Route r) =>
            r.active &&
            r.hasFixedStations &&
            (r.stations?.length ?? 0) >= 2)
        .toList(growable: false);
    if (fixedRoutes.isEmpty) {
      return const RoutePlanOutcome.failure(RoutePlanFailure.noRoute);
    }

    final StationGraph graph = StationGraph.build(fixedRoutes);

    final List<GraphNode> boardCandidates = graph.nodesWithin(origin, maxWalkMeters);
    if (boardCandidates.isEmpty) {
      return const RoutePlanOutcome.failure(RoutePlanFailure.noStationsNearOrigin);
    }
    final List<GraphNode> alightCandidates =
        graph.nodesWithin(destination, maxWalkMeters);
    if (alightCandidates.isEmpty) {
      return const RoutePlanOutcome.failure(RoutePlanFailure.noStationsNearDestination);
    }

    double? bestCost;
    PathResult? bestPath;
    bool walkOnly = false;

    // Plan alternativo a pie: si el destino queda dentro de la distancia
    // máxima a pie, caminar directo puede ganarle al transporte.
    final double directWalk = distanceMeters(origin, destination);
    if (directWalk <= maxWalkMeters) {
      walkOnly = true;
      bestCost = _walkMinutes(directWalk);
    }

    for (final GraphNode board in boardCandidates) {
      final double walkIn = _walkMinutes(distanceMeters(origin, board.position));
      for (final GraphNode alight in alightCandidates) {
        // Abordar y bajar en la misma estación sería "caminar a la estación y
        // volver": no tiene sentido, el viaje a pie directo siempre es mejor.
        if (board.id == alight.id) continue;

        final PathResult? path = graph.shortestPath(board.id, alight.id);
        if (path == null) continue;

        final double cost = walkIn +
            path.totalMinutes +
            _walkMinutes(distanceMeters(alight.position, destination));
        if (bestCost == null || cost < bestCost) {
          bestCost = cost;
          bestPath = path;
        }
      }
    }

    if (bestPath == null && !walkOnly) {
      return const RoutePlanOutcome.failure(RoutePlanFailure.noRoute);
    }

    final TripPlan plan = bestPath != null
        ? _buildTransitPlan(
            origin: origin,
            destination: destination,
            originName: _pointLabel(origin, boardCandidates, 'Origen'),
            destinationName: _pointLabel(destination, alightCandidates, 'Destino'),
            path: bestPath,
            graph: graph,
          )
        : _walkOnlyPlan(origin, destination);
    return RoutePlanOutcome.success(plan);
  }

  /// Convierte un camino del grafo en un [TripPlan]: un tramo a pie al
  /// abordaje, un tramo de transporte por cada ruta consecutiva del camino,
  /// una caminata corta (pasillo) por cada transbordo, y un tramo a pie final.
  TripPlan _buildTransitPlan({
    required GeoPoint origin,
    required GeoPoint destination,
    required String originName,
    required String destinationName,
    required PathResult path,
    required StationGraph graph,
  }) {
    final List<TripLeg> legs = <TripLeg>[
      TripLeg(
        id: 'walk-in',
        mode: TransportMode.walk,
        path: <GeoPoint>[origin, graph.node(path.nodeIds.first)!.position],
        lineColorHex: kWalkColor,
      ),
    ];

    int edgeIndex = 0;
    while (edgeIndex < path.edges.length) {
      final String routeId = path.edges[edgeIndex].routeId;
      int end = edgeIndex;
      while (end + 1 < path.edges.length && path.edges[end + 1].routeId == routeId) {
        end++;
      }

      final Route route = graph.routeById(routeId)!;
      final List<GraphNode> stations = <GraphNode>[
        for (int i = edgeIndex; i <= end + 1; i++) graph.node(path.nodeIds[i])!,
      ];
      final TransportMode mode = transportModeForTypeId(route.transportTypeId);

      legs.add(
        TripLeg(
          id: 'leg-${legs.length}',
          mode: mode,
          lineName: route.name,
          lineColorHex: lineColorForRoute(route),
          headsign: stations.last.name,
          path: <GeoPoint>[for (final GraphNode s in stations) s.position],
          stops: <TripStop>[
            for (final GraphNode s in stations)
              TripStop(
                id: s.id,
                name: s.name,
                position: s.position,
                isTransfer: s.isTransfer,
              ),
          ],
          // Tarifa de la ruta. El Metro real se paga una sola vez aunque se
          // transborde; ese descuento queda como deuda del motor (AGENTS.md).
          fareDop: route.price,
          // La frecuencia no vive en Firestore todavía; sin espera estimada.
          headwayMinutes: 0,
        ),
      );

      if (end + 1 < path.edges.length) {
        // Transbordo: la estación compartida es el pasillo entre las dos
        // líneas. El tramo es de 0 m a propósito: [TripGeometry] lo deduplica
        // y la instrucción es un "bájate: transborda a X".
        final GraphNode transfer = stations.last;
        legs.add(
          TripLeg(
            id: 'leg-transfer-${legs.length}',
            mode: TransportMode.walk,
            path: <GeoPoint>[transfer.position, transfer.position],
            lineColorHex: kWalkColor,
          ),
        );
      }

      edgeIndex = end + 1;
    }

    legs.add(
      TripLeg(
        id: 'walk-out',
        mode: TransportMode.walk,
        path: <GeoPoint>[graph.node(path.nodeIds.last)!.position, destination],
        lineColorHex: kWalkColor,
      ),
    );

    return TripPlan(
      id: _planId(origin, destination),
      originName: originName,
      destinationName: destinationName,
      legs: legs,
    );
  }

  TripPlan _walkOnlyPlan(GeoPoint origin, GeoPoint destination) => TripPlan(
        id: _planId(origin, destination),
        originName: 'Origen',
        destinationName: 'Destino',
        legs: <TripLeg>[
          TripLeg(
            id: 'walk-only',
            mode: TransportMode.walk,
            path: <GeoPoint>[origin, destination],
            lineColorHex: kWalkColor,
          ),
        ],
      );

  /// Etiqueta "Cerca de {estación}" usando la estación candidata más cercana.
  /// Sin geocodificación inversa todavía (AGENTS.md §3.2), es lo más parecido
  /// a un nombre de calle que puede mostrar la UI.
  String _pointLabel(GeoPoint point, List<GraphNode> near, String fallback) {
    if (near.isEmpty) return fallback;
    return 'Cerca de ${near.first.name}';
  }

  static String _planId(GeoPoint origin, GeoPoint destination) {
    String coord(GeoPoint p) =>
        '${p.lat.toStringAsFixed(5)},${p.lng.toStringAsFixed(5)}';
    return 'plan-${coord(origin)}-to-${coord(destination)}';
  }

  static double _walkMinutes(double meters) =>
      meters / TransportMode.walk.averageSpeedMps / 60.0;
}
