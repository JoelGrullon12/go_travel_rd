import 'dart:math' as math;

import '../models/transport_mode.dart';
import '../models/trip_instruction.dart';
import '../models/trip_plan.dart';
import 'route_matcher.dart';
import 'trip_geometry.dart';

/// Umbrales de disparo de las instrucciones, en metros.
///
/// Están agrupados en una clase para poder ajustarlos sin cazar números mágicos
/// por el código, y para poder probarlos con valores distintos en los tests.
class InstructionThresholds {
  const InstructionThresholds({
    this.arrivedMeters = 35,
    this.boardMeters = 45,
    this.exitNowMeters = 250,
    this.prepareMeters = 900,
    this.offRouteMeters = 70,
  });

  /// A esta distancia del destino final, el viaje se da por terminado.
  final double arrivedMeters;

  /// A esta distancia de la parada de abordaje, se le dice "móntate aquí".
  final double boardMeters;

  /// A esta distancia de la parada de bajada: "bájate ahora".
  ///
  /// 250 m en metro son ~28 s: suficiente para pararse y llegar a la puerta,
  /// no tanto como para que se baje una estación antes.
  final double exitNowMeters;

  /// A esta distancia de la parada de bajada: "prepárate".
  final double prepareMeters;

  /// Desviación lateral a partir de la cual se considera fuera de ruta.
  final double offRouteMeters;
}

/// Genera la instrucción que corresponde al estado actual del viaje.
///
/// Es una **función pura del progreso**: mismas entradas, misma salida. No
/// guarda estado propio, lo que la hace trivial de probar y evita el clásico
/// bug de instrucciones "pegadas" cuando el usuario retrocede o se reconecta.
/// El anti-rebote de fuera-de-ruta vive en [TripTracker], no aquí.
class InstructionEngine {
  const InstructionEngine(
    this.geometry, {
    this.thresholds = const InstructionThresholds(),
  });

  final TripGeometry geometry;
  final InstructionThresholds thresholds;

  TripPlan get plan => geometry.plan;

  TripInstruction build({
    required RouteMatch match,
    required bool offRoute,
    required bool hasStarted,
  }) {
    final double traveled = match.traveledMeters;
    final double remaining = geometry.totalMeters - traveled;

    // 1. Llegada: gana sobre todo lo demás.
    if (remaining <= thresholds.arrivedMeters) {
      return TripInstruction(
        key: 'arrived',
        kind: InstructionKind.arrived,
        urgency: InstructionUrgency.headsUp,
        title: 'Llegaste',
        detail: plan.destinationName,
      );
    }

    // 2. Fuera de ruta: el usuario necesita saberlo antes que cualquier
    //    instrucción de navegación, que ya no aplica.
    if (offRoute) {
      return TripInstruction(
        key: 'off-route',
        kind: InstructionKind.offRoute,
        urgency: InstructionUrgency.critical,
        title: 'Te saliste de la ruta',
        detail: 'Estás a ${_fmt(match.distanceFromRouteMeters)} del recorrido. '
            'Vuelve o recalcula el viaje.',
        distanceMeters: match.distanceFromRouteMeters,
      );
    }

    final int legIndex = match.legIndex.clamp(0, plan.legs.length - 1);
    final TripLeg leg = plan.legs[legIndex];
    final double toLegEnd = math.max(0, geometry.legEndMeters[legIndex] - traveled);
    final TripLeg? nextLeg =
        legIndex + 1 < plan.legs.length ? plan.legs[legIndex + 1] : null;

    // 3. Todavía no se ha movido.
    if (!hasStarted) {
      return TripInstruction(
        key: 'start',
        kind: InstructionKind.start,
        urgency: InstructionUrgency.calm,
        title: _startTitle(leg),
        detail: 'Hacia ${plan.destinationName} · '
            '${_fmt(geometry.totalMeters)} en total',
        legIndex: legIndex,
        lineColorHex: leg.lineColorHex,
      );
    }

    // 4. Tramo a pie.
    if (leg.mode.isWalking) {
      final bool isLastLeg = nextLeg == null;

      if (isLastLeg) {
        return TripInstruction(
          key: 'walk-dest:$legIndex',
          kind: InstructionKind.walkToDestination,
          urgency: toLegEnd <= 120
              ? InstructionUrgency.headsUp
              : InstructionUrgency.calm,
          title: 'Camina hasta ${plan.destinationName}',
          detail: '${_fmt(toLegEnd)} · ${_walkMinutes(toLegEnd)}',
          legIndex: legIndex,
          distanceMeters: toLegEnd,
        );
      }

      final TripStop? boarding = nextLeg.boardingStop;
      final String destination = boarding?.name.isNotEmpty == true
          ? boarding!.name
          : nextLeg.shortLabel;

      // Ya llegó a la parada: instrucción de abordaje.
      if (toLegEnd <= thresholds.boardMeters) {
        return TripInstruction(
          key: 'board:${nextLeg.id}',
          kind: InstructionKind.board,
          urgency: InstructionUrgency.headsUp,
          title: 'Móntate en ${nextLeg.shortLabel}',
          detail: _boardDetail(nextLeg, destination),
          legIndex: legIndex + 1,
          targetStop: boarding,
          lineColorHex: nextLeg.lineColorHex,
        );
      }

      return TripInstruction(
        key: 'walk-board:$legIndex',
        kind: InstructionKind.walkToBoarding,
        urgency: InstructionUrgency.calm,
        title: 'Camina hasta $destination',
        detail: '${_fmt(toLegEnd)} · ${_walkMinutes(toLegEnd)} · '
            'ahí tomas ${nextLeg.shortLabel}',
        legIndex: legIndex,
        targetStop: boarding,
        distanceMeters: toLegEnd,
        lineColorHex: nextLeg.lineColorHex,
      );
    }

    // 5. Tramo en vehículo.
    final TripStop? alighting = leg.alightingStop;
    final String stopName = alighting?.name ?? plan.destinationName;

    // Cuántas paradas intermedias faltan. Solo tiene sentido en modos con
    // paradas fijas: en un concho no existe "la próxima parada", así que aquí
    // vale `null` y las instrucciones hablan de distancia, no de paradas.
    final int? stopsToGo = leg.mode.hasFixedStops && leg.stops.isNotEmpty
        ? math.max(0, geometry.upcomingStopsOfLeg(legIndex, traveled).length - 1)
        : null;

    if (toLegEnd <= thresholds.exitNowMeters) {
      final TripLeg? connecting = _transferTargetAfter(legIndex);
      return TripInstruction(
        key: 'exit-now:$legIndex',
        kind: connecting != null
            ? InstructionKind.transfer
            : InstructionKind.exitNow,
        urgency: InstructionUrgency.critical,
        title: 'Bájate ahora',
        detail: connecting != null
            ? '$stopName · transbordo a ${connecting.shortLabel}'
            : '$stopName · ${_fmt(toLegEnd)}',
        legIndex: legIndex,
        targetStop: alighting,
        distanceMeters: toLegEnd,
        lineColorHex: leg.lineColorHex,
      );
    }

    if (toLegEnd <= thresholds.prepareMeters ||
        (stopsToGo != null && stopsToGo <= 1)) {
      return TripInstruction(
        key: 'prepare:$legIndex',
        kind: InstructionKind.prepareToExit,
        urgency: InstructionUrgency.headsUp,
        title: stopsToGo != null && stopsToGo <= 0
            ? 'Te bajas en la próxima'
            : 'Prepárate para bajar',
        detail: '$stopName · ${_fmt(toLegEnd)}',
        legIndex: legIndex,
        targetStop: alighting,
        distanceMeters: toLegEnd,
        lineColorHex: leg.lineColorHex,
      );
    }

    return TripInstruction(
      key: 'riding:$legIndex',
      kind: InstructionKind.riding,
      urgency: InstructionUrgency.calm,
      title: 'Sigue en ${leg.shortLabel}',
      detail: switch (stopsToGo) {
        null => 'Te bajas en $stopName · ${_fmt(toLegEnd)}',
        1 => 'Te bajas en $stopName, falta 1 parada',
        final int n => 'Te bajas en $stopName, faltan $n paradas',
      },
      legIndex: legIndex,
      targetStop: alighting,
      distanceMeters: toLegEnd,
      lineColorHex: leg.lineColorHex,
    );
  }

  /// Si al bajarse de `legIndex` viene otro tramo de transporte —directo o
  /// después de una caminata corta dentro de la estación— devuelve ese tramo.
  ///
  /// Es lo que convierte un "bájate aquí" en un "bájate: transbordo a L2".
  /// Sin esto, el transbordo de Juan Pablo Duarte se anunciaría como si el
  /// viaje se acabara ahí.
  TripLeg? _transferTargetAfter(int legIndex) {
    final int nextIndex = legIndex + 1;
    if (nextIndex >= plan.legs.length) return null;
    final TripLeg next = plan.legs[nextIndex];
    if (!next.mode.isWalking) return next;

    // Caminata corta = pasillo de transbordo, no un tramo del viaje.
    if (next.distanceMeters > 250) return null;
    final int afterIndex = nextIndex + 1;
    if (afterIndex >= plan.legs.length) return null;
    final TripLeg after = plan.legs[afterIndex];
    return after.mode.isWalking ? null : after;
  }

  String _startTitle(TripLeg leg) => leg.mode.isWalking
      ? 'Empieza a caminar'
      : 'Móntate en ${leg.shortLabel}';

  String _boardDetail(TripLeg leg, String stopName) {
    final StringBuffer buffer = StringBuffer(stopName);
    if (leg.headsign.isNotEmpty) buffer.write(' · dirección ${leg.headsign}');
    if (leg.headwayMinutes > 0) {
      buffer.write(' · pasa cada ${leg.headwayMinutes} min');
    }
    return buffer.toString();
  }

  /// Distancias redondeadas como las diría una persona: nadie dice "487 metros".
  static String _fmt(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    if (meters >= 100) return '${(meters / 50).round() * 50} m';
    if (meters >= 20) return '${(meters / 10).round() * 10} m';
    return '${meters.round()} m';
  }

  static String _walkMinutes(double meters) {
    final int minutes =
        (meters / TransportMode.walk.averageSpeedMps / 60).ceil();
    return minutes <= 1 ? '1 min' : '$minutes min';
  }
}
