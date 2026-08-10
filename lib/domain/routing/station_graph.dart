import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../models/route.dart';
import '../geo/geo_math.dart';
import '../geo/geo_point.dart';
import '../models/transport_mode.dart';

/// Distancia máxima a pie (metros) para sugerir un transbordo entre
/// estaciones de rutas distintas (ej. Metro ↔ OMSA, que no comparten ids de
/// parada). Por encima de esto no se sugiere el trasbordo y el plan se
/// considera no conectado.
///
/// Es la misma cota que usa `InstructionEngine` para anunciar "bájate:
/// transbordo a X" ([kTransferWalkMeters]).
const double kTransferWalkMeters = 400;

/// Id sentinela de las aristas de transbordo a pie dentro del grafo.
///
/// No es una ruta real de Firestore: `RouteEngine._buildTransitPlan` lo
/// interpreta como "caminata entre dos estaciones" y emite un tramo a pie
/// con distancia real, en vez de un tramo de vehículo.
const String kTransferRouteId = '__walk_transfer__';

/// Mapea el `transportTypeId` de Firestore a un [TransportMode].
///
/// Los ids del backend son estables (AGENTS.md §9.4: `"metro"` / `"omsa"`).
/// Tipos desconocidos caen a [TransportMode.concho], el transporte informal
/// genérico, para que el plan siga siendo navegable.
TransportMode transportModeForTypeId(String typeId) => switch (typeId) {
  'metro' => TransportMode.metro,
  'teleferico' => TransportMode.teleferico,
  'corredor' => TransportMode.corredor,
  'omsa' => TransportMode.omsa,
  'concho' => TransportMode.concho,
  'motoconcho' => TransportMode.motoconcho,
  _ => TransportMode.concho,
};

/// Nodo del grafo: una estación única (por su `stationId` en Firestore).
class GraphNode {
  GraphNode({required this.id, required this.name, required this.position});

  final String id;
  final String name;
  final GeoPoint position;

  /// Rutas con paradas fijas que pasan por esta estación. Si hay más de una,
  /// la estación sirve de transbordo (ej. Juan Pablo Duarte en L1 y L2).
  final Set<String> routeIds = <String>{};

  bool get isTransfer => routeIds.length > 1;
}

/// Arista entre dos estaciones consecutivas de una misma ruta.
class GraphEdge {
  GraphEdge({
    required this.fromId,
    required this.toId,
    required this.routeId,
    required this.minutes,
  });

  final String fromId;
  final String toId;
  final String routeId;
  final double minutes;
}

/// Camino más corto entre dos estaciones (resultado de Dijkstra).
class PathResult {
  PathResult({
    required this.nodeIds,
    required this.edges,
    required this.totalMinutes,
  }) : assert(nodeIds.length == edges.length + 1);

  /// Ids de las estaciones, del origen (inclusive) al destino (inclusive).
  final List<String> nodeIds;

  /// Aristas recorridas, en orden (cada una del mismo [StationGraph]).
  final List<GraphEdge> edges;

  final double totalMinutes;
}

/// Costo de recorrer una arista durante el Dijkstra.
///
/// `incomingEdge` es la arista por la que se llegó al nodo actual (`null`
/// cuando el nodo es una fuente, p.ej. el usuario acaba de caminar hasta él):
/// con eso el motor detecta si esta arista es un **abordaje** (cambió de ruta)
/// y puede cobrar tarifa o penalizar el modo, o si es una arista más del mismo
/// trayecto. Sin callback, [StationGraph.dijkstraFrom] usa [GraphEdge.minutes].
typedef EdgeCost = double Function(GraphEdge? incomingEdge, GraphEdge edge);

/// Resultado de un Dijkstra multi-fuente: la distancia mínima a **cada** nodo
/// del grafo y la arista por la que se llegó mejor a cada uno.
///
/// Se construye una sola vez por búsqueda; [StationGraph.pathTo] reconstruye
/// un [PathResult] concreto para el destino elegido.
class DijkstraResult {
  DijkstraResult(this.dist, this.prevEdge);

  /// Mejor costo (minutos) desde cualquiera de los orígenes hasta el nodo.
  final Map<String, double> dist;

  /// Arista que produjo el mejor costo a cada nodo. Los orígenes no aparecen
  /// (no se "llegó" a ellos a través de ninguna arista).
  final Map<String, GraphEdge> prevEdge;
}

/// Grafo de transporte construido desde las rutas de Firestore.
///
/// Nodos = estaciones únicas (por `stationId`). Aristas = pares de estaciones
/// consecutivas dentro de una ruta (campo `stations[].order`), bidireccionales
/// —una ruta se recorre en ambos sentidos— con peso en minutos de viaje.
///
/// El peso por arista es `distancia(km) × route.avgMinutesPerKm`. Cuando la
/// ruta no trae ese campo, se cae a la velocidad comercial del modo
/// ([TransportMode.averageSpeedKmh]).
class StationGraph {
  StationGraph.build(List<Route> routes) {
    for (final Route route in routes) {
      final List<RouteStation>? raw = route.stations;
      if (raw == null || raw.length < 2) continue;

      _routeById[route.id] = route;

      final List<RouteStation> ordered = List<RouteStation>.of(raw)
        ..sort((RouteStation a, RouteStation b) => a.order.compareTo(b.order));

      for (final RouteStation station in ordered) {
        _nodeFor(
          station.stationId,
          station.name,
          _domainPoint(station.location),
        ).routeIds.add(route.id);
      }

      for (int i = 0; i < ordered.length - 1; i++) {
        final RouteStation a = ordered[i];
        final RouteStation b = ordered[i + 1];
        final double minutes = _edgeMinutes(route, a.location, b.location);
        _addEdge(a.stationId, b.stationId, route.id, minutes);
        _addEdge(b.stationId, a.stationId, route.id, minutes);
      }
    }

    _addTransferEdges();
  }

  final Map<String, GraphNode> _nodes = <String, GraphNode>{};
  final Map<String, List<GraphEdge>> _adjacency = <String, List<GraphEdge>>{};
  final Map<String, Route> _routeById = <String, Route>{};

  Iterable<GraphNode> get nodes => _nodes.values;

  GraphNode? node(String id) => _nodes[id];

  Route? routeById(String id) => _routeById[id];

  /// Nodos alcanzables desde `point` en línea recta a menos de `maxMeters`,
  /// ordenados de más cercano a más lejano.
  List<GraphNode> nodesWithin(GeoPoint point, double maxMeters) {
    final List<(GraphNode, double)> within = <(GraphNode, double)>[];
    for (final GraphNode node in _nodes.values) {
      final double d = distanceMeters(point, node.position);
      if (d <= maxMeters) within.add((node, d));
    }
    within.sort((a, b) => a.$2.compareTo(b.$2));
    return <GraphNode>[for (final (node, _) in within) node];
  }

  /// Dijkstra **multi-fuente**: distancia mínima a todos los nodos partiendo
  /// de varios orígenes a la vez, cada uno con su costo acumulado inicial
  /// (ej. los minutos de caminata desde el punto A a cada estación de abordaje).
  ///
  /// Es el núcleo del motor A→B: con UNA pasada se obtiene el mejor camino a
  /// todos los destinos posibles, en vez de correr un Dijkstra por cada par
  /// (abordaje × bajada). Complejidad O((V+E) log V).
  ///
  /// Si un nodo aparece en varias fuentes, gana la de menor costo inicial.
  ///
  /// [cost] sobreescribe el peso de cada arista (p.ej. costo generalizado con
  /// tarifa y preferencias de modo). Sin él, el peso es [GraphEdge.minutes].
  DijkstraResult dijkstraFrom(
    Iterable<(String, double)> starts, {
    EdgeCost? cost,
  }) {
    final Map<String, double> dist = <String, double>{};
    final Map<String, GraphEdge> prevEdge = <String, GraphEdge>{};
    final SplayTreeMap<double, List<String>> queue =
        SplayTreeMap<double, List<String>>();

    for (final (String nodeId, double minutes) in starts) {
      final double? old = dist[nodeId];
      if (old != null && old <= minutes) continue;
      dist[nodeId] = minutes;
      queue.putIfAbsent(minutes, () => <String>[]).add(nodeId);
    }

    while (queue.isNotEmpty) {
      final double d = queue.firstKey()!;
      final List<String> nodes = queue.remove(d)!;
      for (final String nodeId in nodes) {
        if (d != dist[nodeId]) continue; // entrada obsoleta del heap

        for (final GraphEdge edge
            in _adjacency[nodeId] ?? const <GraphEdge>[]) {
          final double edgeCost =
              cost?.call(prevEdge[nodeId], edge) ?? edge.minutes;
          final double nd = d + edgeCost;
          final double? old = dist[edge.toId];
          if (old != null && old <= nd) continue;
          dist[edge.toId] = nd;
          prevEdge[edge.toId] = edge;
          queue.putIfAbsent(nd, () => <String>[]).add(edge.toId);
        }
      }
    }

    return DijkstraResult(dist, prevEdge);
  }

  /// Reconstruye el camino (nodos + aristas + minutos totales) hacia `target`
  /// desde un resultado de [dijkstraFrom]. `null` si `target` es inalcanzable.
  ///
  /// Un destino que coincide con un origen (sin `prevEdge`, es decir "subir y
  /// bajar en la misma estación") devuelve un camino de un solo nodo; el motor
  /// decide si le sirve.
  PathResult? pathTo(DijkstraResult result, String target) {
    final double? total = result.dist[target];
    if (total == null) return null;

    final List<String> ids = <String>[target];
    final List<GraphEdge> edges = <GraphEdge>[];
    while (result.prevEdge.containsKey(ids.last)) {
      final GraphEdge edge = result.prevEdge[ids.last]!;
      edges.add(edge);
      ids.add(edge.fromId);
    }
    return PathResult(
      nodeIds: ids.reversed.toList(growable: false),
      edges: edges.reversed.toList(growable: false),
      totalMinutes: total,
    );
  }

  GraphNode _nodeFor(String id, String name, GeoPoint position) => _nodes
      .putIfAbsent(id, () => GraphNode(id: id, name: name, position: position));

  /// Añade aristas de transbordo a pie entre estaciones de rutas **distintas**
  /// que estén a menos de [kTransferWalkMeters].
  ///
  /// Sin esto, OMSA y Metro —que no comparten ids de parada— nunca se
  /// conectarían y cualquier par origen/destino que mezclara sistemas daría
  /// `noRoute`. Con estas aristas, Dijkstra encuentra el trasbordo y el plan
  /// suma un pasaje más (cada tramo de transporte cobra su tarifa).
  ///
  /// Se omiten los pares que ya comparten una ruta: ya están conectados por el
  /// servicio y una caminata entre ellos nunca sería más rápida.
  void _addTransferEdges() {
    final List<GraphNode> nodes = _nodes.values.toList(growable: false);
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final GraphNode a = nodes[i];
        final GraphNode b = nodes[j];
        if (a.routeIds.any(b.routeIds.contains)) continue;

        final double meters = distanceMeters(a.position, b.position);
        if (meters > kTransferWalkMeters) continue;

        final double minutes = _walkMinutes(meters);
        _addEdge(a.id, b.id, kTransferRouteId, minutes);
        _addEdge(b.id, a.id, kTransferRouteId, minutes);
      }
    }
  }

  void _addEdge(String fromId, String toId, String routeId, double minutes) {
    _adjacency
        .putIfAbsent(fromId, () => <GraphEdge>[])
        .add(
          GraphEdge(
            fromId: fromId,
            toId: toId,
            routeId: routeId,
            minutes: minutes,
          ),
        );
  }

  static double _walkMinutes(double meters) =>
      meters / TransportMode.walk.averageSpeedMps / 60.0;

  static GeoPoint _domainPoint(fs.GeoPoint cloud) =>
      GeoPoint(cloud.latitude, cloud.longitude);

  static double _edgeMinutes(Route route, fs.GeoPoint a, fs.GeoPoint b) {
    final double km = distanceMeters(_domainPoint(a), _domainPoint(b)) / 1000.0;
    if (km <= 0) return 0;
    if (route.avgMinutesPerKm > 0) return km * route.avgMinutesPerKm;
    final TransportMode mode = transportModeForTypeId(route.transportTypeId);
    return km / mode.averageSpeedKmh * 60.0;
  }
}
