import '../../data/metro_stations.dart'
    show kConchoColor, kLine1Color, kLine2Color, kWalkColor;
import '../../models/route.dart';
import '../geo/geo_math.dart';
import '../geo/geo_point.dart';
import '../models/transport_mode.dart';
import '../models/trip_plan.dart';
import 'route_preferences.dart';
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

/// Penalización (en minutos) por **abordar** un modo de transporte que no es
/// el favorito del usuario ([RoutePreferences.favoriteTransportTypeId]).
///
/// Es un sobrecosto dentro del grafo: hace que el tipo preferido salga
/// favorecido sin tocar los minutos/tarifas reales que se muestran en el plan.
/// ~15 min ≈ un headway promedio del transporte en Santo Domingo.
const double kModePenaltyMinutes = 15;

/// Pesos del **costo generalizado** según la preferencia de viaje
/// ([RoutePreferences.routePreference]). El costo de una arista es:
///
///   time × minutos + distanceKm × km + valueOfTimeDop × tarifa + penalización
///
/// · `speed`: solo minutos (reproduce el motor original).
/// · `price`: la tarifa domina; el tiempo es desempate.
/// · `distance`: los kilómetros dominan; el tiempo es desempate.
class _CostWeights {
  const _CostWeights({
    required this.time,
    required this.valueOfTimeDop,
    required this.distanceKm,
  });

  final double time;
  final double valueOfTimeDop;
  final double distanceKm;

  static _CostWeights forPreference(String routePreference) =>
      switch (routePreference) {
        'price' => const _CostWeights(
            time: 0.35,
            valueOfTimeDop: 5.0,
            distanceKm: 0.0,
          ),
        'distance' => const _CostWeights(
            time: 0.35,
            valueOfTimeDop: 1.0,
            distanceKm: 1.0,
          ),
        _ => const _CostWeights(time: 1.0, valueOfTimeDop: 0.0, distanceKm: 0.0),
      };
}

/// Motor de cálculo de ruta A→B (Hito 2).
///
/// Lógica pura, sin Flutter: se prueba con `flutter test`. Opera sobre las
/// rutas de Firestore ([Route]) y devuelve un [TripPlan] — el mismo contrato
/// que consume el seguimiento en tiempo real (Hito 4).
///
/// ## Objetivo
/// Minimizar el **costo generalizado** total, que por defecto es el tiempo
/// estimado (caminata al origen + minutos por tramo + caminata al destino) y
/// con preferencias suma tarifa y sesgo de modo preferido
/// ([RoutePreferences]): "más rápido" pondera solo tiempo, "más barato"
/// pondera la tarifa y "más corto" los kilómetros; el tipo favorito se premia
/// penalizando el abordaje de los demás.
///
/// ## Cómo busca
/// 1. Estaciones alcanzables a pie (≤ `maxWalkMeters`) desde origen y destino.
/// 2. Un solo **Dijkstra multi-fuente** sobre el [StationGraph], arrancando de
///    una fuente virtual conectada a cada estación de abordaje (peso = caminata
///    ponderada desde el origen). Así se obtiene el mejor costo a **todos** los
///    destinos en una pasada —O((V+E) log V)— en vez de correr un Dijkstra por
///    cada par (abordaje × bajada), que con distancia a pie ∞ disparaba B×A
///    ejecuciones y congelaba la UI.
/// 3. Gana el mejor destino de bajada. Los transbordos —caminatas cortas entre
///    estaciones cercanas o el pasillo de una estación compartida— se suman
///    como tramos a pie dentro del grafo.
/// 4. Si origen y destino están lo bastante cerca, caminar directo compite con
///    el transporte y puede ganarle.
///
/// El [TripPlan] resultante siempre reporta **valores reales** (minutos,
/// tarifa y distancia de sus tramos); el costo generalizado solo decide el
/// camino dentro del grafo.
class RouteEngine {
  const RouteEngine();

  RoutePlanOutcome plan({
    required GeoPoint origin,
    required GeoPoint destination,
    required List<Route> routes,
    required double maxWalkMeters,
    RoutePreferences preferences = const RoutePreferences(),
  }) {
    final _CostWeights weights =
        _CostWeights.forPreference(preferences.routePreference);
    final String? favoriteTypeId = preferences.favoriteTransportTypeId;
    final double modePenalty = preferences.hasFavoriteType
        ? kModePenaltyMinutes
        : 0.0;

    final List<Route> fixedRoutes = routes
        .where(
          (Route r) =>
              r.active && r.hasFixedStations && (r.stations?.length ?? 0) >= 2,
        )
        .toList(growable: false);
    if (fixedRoutes.isEmpty) {
      return const RoutePlanOutcome.failure(RoutePlanFailure.noRoute);
    }

    final StationGraph graph = StationGraph.build(fixedRoutes);

    final List<GraphNode> boardCandidates = graph.nodesWithin(
      origin,
      maxWalkMeters,
    );
    if (boardCandidates.isEmpty) {
      return const RoutePlanOutcome.failure(
        RoutePlanFailure.noStationsNearOrigin,
      );
    }
    final List<GraphNode> alightCandidates = graph.nodesWithin(
      destination,
      maxWalkMeters,
    );
    if (alightCandidates.isEmpty) {
      return const RoutePlanOutcome.failure(
        RoutePlanFailure.noStationsNearDestination,
      );
    }

    // Dijkstra multi-fuente: una sola pasada desde una fuente virtual conectada
    // a cada estación de abordaje (peso = caminata ponderada desde el origen).
    // `dist[alight]` queda = min sobre los abordajes de (caminata + viaje), que
    // es exactamente lo que antes calculaba el doble bucle de Dijkstras, pero
    // sin repetir trabajo por cada par (abordaje × bajada). Con `cost`, cada
    // arista usa el costo generalizado (tiempo + tarifa + modo preferido); el
    // plan mostrado sigue reportando los valores reales de sus tramos.
    final DijkstraResult dijkstra = graph.dijkstraFrom(<(String, double)>[
      for (final GraphNode board in boardCandidates)
        (
          board.id,
          _weightedWalk(weights, distanceMeters(origin, board.position)),
        ),
    ], cost: (GraphEdge? incoming, GraphEdge edge) {
      return _edgeCost(
        graph: graph,
        weights: weights,
        modePenalty: modePenalty,
        favoriteTypeId: favoriteTypeId,
        incoming: incoming,
        edge: edge,
      );
    });

    double? bestCost;
    PathResult? bestPath;
    bool walkOnly = false;

    // Plan alternativo a pie: si el destino queda dentro de la distancia
    // máxima a pie, caminar directo puede ganarle al transporte. Se compara en
    // el mismo costo generalizado (caminar no cobra tarifa ni penaliza modo).
    final double directWalk = distanceMeters(origin, destination);
    if (directWalk <= maxWalkMeters) {
      walkOnly = true;
      bestCost = _weightedWalk(weights, directWalk);
    }

    for (final GraphNode alight in alightCandidates) {
      final double? dist = dijkstra.dist[alight.id];
      if (dist == null) continue;

      // Abordar y bajar en la misma estación (la mejor entrada al nodo fue
      // caminar hasta él, sin ninguna arista de por medio): ese "plan" es
      // caminar al punto y volver, siempre ≥ caminar directo. Se descarta.
      if (!dijkstra.prevEdge.containsKey(alight.id)) continue;

      final double cost = dist +
          _weightedWalk(weights, distanceMeters(alight.position, destination));
      if (bestCost == null || cost < bestCost) {
        bestCost = cost;
        bestPath = graph.pathTo(dijkstra, alight.id);
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
            destinationName: _pointLabel(
              destination,
              alightCandidates,
              'Destino',
            ),
            path: bestPath,
            graph: graph,
          )
        : _walkOnlyPlan(origin, destination);
    return RoutePlanOutcome.success(plan);
  }

  /// Costo generalizado de recorrer `edge` saliendo del nodo alcanzado por
  /// `incoming` ([EdgeCost]).
  ///
  /// - Aristas de transbordo a pie: solo tiempo/distancia ponderados.
  /// - Aristas de vehículo: tiempo/distancia ponderados, y si la arista es un
  ///   **abordaje** (cambia de ruta o es la primera de la búsqueda) se suma la
  ///   tarifa ponderada y, si el modo no es el favorito, la penalización.
  ///
  /// Excepción: cambiar de ruta **dentro de una misma estación** (transbordo
  /// en estación compartida, ej. Juan Pablo Duarte L1/L2) no cobra una segunda
  /// tarifa — el pasaje del Metro se paga una sola vez aunque se transborde.
  /// La penalización de modo preferido sí se mantiene: es un sesgo de
  /// preferencia, no un cobro.
  double _edgeCost({
    required StationGraph graph,
    required _CostWeights weights,
    required double modePenalty,
    required String? favoriteTypeId,
    required GraphEdge? incoming,
    required GraphEdge edge,
  }) {
    final double km = distanceMeters(
          graph.node(edge.fromId)!.position,
          graph.node(edge.toId)!.position,
        ) /
        1000.0;
    double cost = weights.time * edge.minutes + weights.distanceKm * km;

    if (edge.routeId == kTransferRouteId) return cost;

    final bool boarding = incoming == null || incoming.routeId != edge.routeId;
    if (!boarding) return cost;

    final Route route = graph.routeById(edge.routeId)!;
    final bool inStationTransfer =
        incoming != null &&
        incoming.routeId != kTransferRouteId &&
        graph.node(edge.fromId)!.routeIds.contains(incoming.routeId) &&
        graph.node(edge.fromId)!.routeIds.contains(edge.routeId);
    if (!inStationTransfer) {
      cost += weights.valueOfTimeDop * route.price;
    }
    if (modePenalty > 0 && route.transportTypeId != favoriteTypeId) {
      cost += modePenalty;
    }
    return cost;
  }

  /// Caminata (metros) convertida al costo generalizado: tiempo ponderado +
  /// kilómetros ponderados. Caminar no cobra tarifa ni penaliza modo.
  static double _weightedWalk(_CostWeights weights, double meters) =>
      weights.time * _walkMinutes(meters) +
      weights.distanceKm * meters / 1000.0;

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

      // Transbordo a pie entre dos estaciones de rutas distintas (ej. Metro →
      // OMSA): el camino cruza caminando de una estación a otra cercana. La
      // distancia es real, a diferencia del pasillo de 0 m de la estación
      // compartida que se emite más abajo.
      if (routeId == kTransferRouteId) {
        final GraphNode from = graph.node(path.nodeIds[edgeIndex])!;
        final GraphNode to = graph.node(path.nodeIds[edgeIndex + 1])!;
        legs.add(
          TripLeg(
            id: 'leg-transfer-${legs.length}',
            mode: TransportMode.walk,
            path: <GeoPoint>[from.position, to.position],
            lineColorHex: kWalkColor,
          ),
        );
        edgeIndex++;
        continue;
      }

      int end = edgeIndex;
      while (end + 1 < path.edges.length &&
          path.edges[end + 1].routeId == routeId) {
        end++;
      }

      final Route route = graph.routeById(routeId)!;
      final List<GraphNode> stations = <GraphNode>[
        for (int i = edgeIndex; i <= end + 1; i++) graph.node(path.nodeIds[i])!,
      ];
      final TransportMode mode = transportModeForTypeId(route.transportTypeId);

      // Transbordo en estación compartida: el plan llega a esta ruta sin pasar
      // por un tramo a pie de transbordo, y la estación de abordaje pertenece a
      // la ruta anterior y a la actual (ej. Juan Pablo Duarte en L1/L2). El
      // pasaje se cobra una sola vez: este tramo no suma tarifa.
      final bool inStationTransfer = edgeIndex > 0 &&
          path.edges[edgeIndex - 1].routeId != kTransferRouteId &&
          path.edges[edgeIndex - 1].routeId != routeId &&
          graph.node(path.nodeIds[edgeIndex])!.routeIds.contains(
                path.edges[edgeIndex - 1].routeId,
              ) &&
          graph.node(path.nodeIds[edgeIndex])!.routeIds.contains(routeId);

      // Marcar como transbordo las paradas limítrofes cuando el camino entra o
      // sale caminando hacia otra ruta (para el badge "transbordo" en la UI).
      final bool entersViaWalkTransfer =
          edgeIndex > 0 &&
          path.edges[edgeIndex - 1].routeId == kTransferRouteId;
      final bool exitsViaWalkTransfer =
          end + 1 < path.edges.length &&
          path.edges[end + 1].routeId == kTransferRouteId;

      legs.add(
        TripLeg(
          id: 'leg-${legs.length}',
          mode: mode,
          lineName: route.name,
          lineColorHex: lineColorForRoute(route),
          headsign: stations.last.name,
          path: <GeoPoint>[for (final GraphNode s in stations) s.position],
          stops: <TripStop>[
            for (int i = 0; i < stations.length; i++)
              TripStop(
                id: stations[i].id,
                name: stations[i].name,
                position: stations[i].position,
                isTransfer:
                    stations[i].isTransfer ||
                    (i == 0 && entersViaWalkTransfer) ||
                    (i == stations.length - 1 && exitsViaWalkTransfer),
              ),
          ],
          // Tarifa de la ruta. Cada tramo cobra su pasaje: un transbordo a pie
          // entre sistemas (Metro → OMSA) suma dos tarifas a propósito. Un
          // transbordo dentro de la misma estación compartida (ej. L1 → L2 en
          // Juan Pablo Duarte) no cobra la segunda: el pasaje se paga una vez.
          fareDop: inStationTransfer ? 0 : route.price,
          // La frecuencia no vive en Firestore todavía; sin espera estimada.
          headwayMinutes: 0,
        ),
      );

      if (end + 1 < path.edges.length &&
          path.edges[end + 1].routeId != kTransferRouteId) {
        // Transbordo en estación compartida: el pasillo es la misma estación.
        // El tramo es de 0 m a propósito: [TripGeometry] lo deduplica y la
        // instrucción es un "bájate: transborda a X".
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
