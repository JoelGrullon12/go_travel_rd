import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../models/route.dart';
import '../geo/geo_math.dart';
import '../geo/geo_point.dart';
import '../models/transport_mode.dart';

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
  GraphNode({
    required this.id,
    required this.name,
    required this.position,
  });

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
        _nodeFor(station.stationId, station.name, _domainPoint(station.location))
            .routeIds
            .add(route.id);
      }

      for (int i = 0; i < ordered.length - 1; i++) {
        final RouteStation a = ordered[i];
        final RouteStation b = ordered[i + 1];
        final double minutes = _edgeMinutes(route, a.location, b.location);
        _addEdge(a.stationId, b.stationId, route.id, minutes);
        _addEdge(b.stationId, a.stationId, route.id, minutes);
      }
    }
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

  /// Camino más corto (Dijkstra, por minutos) entre dos estaciones, o `null`
  /// si no hay conexión. La estación de transbordo —un nodo que pertenece a
  /// más de una ruta— es donde el camino cambia de ruta.
  PathResult? shortestPath(String fromId, String toId) {
    if (fromId == toId) {
      return PathResult(nodeIds: <String>[fromId], edges: const <GraphEdge>[], totalMinutes: 0);
    }

    final Map<String, double> dist = <String, double>{fromId: 0};
    final Map<String, GraphEdge> prevEdge = <String, GraphEdge>{};
    final SplayTreeMap<double, List<String>> queue = SplayTreeMap<double, List<String>>();
    queue[0] = <String>[fromId];

    while (queue.isNotEmpty) {
      final double d = queue.firstKey()!;
      final List<String> nodes = queue.remove(d)!;
      for (final String nodeId in nodes) {
        if (d != dist[nodeId]) continue; // entrada obsoleta del heap
        if (nodeId == toId) {
          final List<String> ids = <String>[toId];
          final List<GraphEdge> edges = <GraphEdge>[];
          while (ids.last != fromId) {
            final GraphEdge edge = prevEdge[ids.last]!;
            edges.add(edge);
            ids.add(edge.fromId);
          }
          return PathResult(
            nodeIds: ids.reversed.toList(growable: false),
            edges: edges.reversed.toList(growable: false),
            totalMinutes: d,
          );
        }

        for (final GraphEdge edge in _adjacency[nodeId] ?? const <GraphEdge>[]) {
          final double nd = d + edge.minutes;
          final double? old = dist[edge.toId];
          if (old != null && old <= nd) continue;
          dist[edge.toId] = nd;
          prevEdge[edge.toId] = edge;
          queue.putIfAbsent(nd, () => <String>[]).add(edge.toId);
        }
      }
    }
    return null;
  }

  GraphNode _nodeFor(String id, String name, GeoPoint position) => _nodes
      .putIfAbsent(id, () => GraphNode(id: id, name: name, position: position));

  void _addEdge(String fromId, String toId, String routeId, double minutes) {
    _adjacency.putIfAbsent(fromId, () => <GraphEdge>[]).add(
          GraphEdge(
            fromId: fromId,
            toId: toId,
            routeId: routeId,
            minutes: minutes,
          ),
        );
  }

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
