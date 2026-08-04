import 'dart:math' as math;

import '../models/trip_plan.dart';
import 'route_matcher.dart';
import 'trip_geometry.dart';

/// Estimación de llegada.
class EtaEstimate {
  const EtaEstimate({
    required this.remaining,
    required this.arrivalAt,
    required this.toEndOfLeg,
    required this.remainingMeters,
  });

  /// Cuánto falta para llegar al destino final.
  final Duration remaining;

  /// Hora estimada de llegada.
  final DateTime arrivalAt;

  /// Cuánto falta para terminar el tramo actual (para "te bajas en X min").
  final Duration toEndOfLeg;

  final double remainingMeters;
}

/// Calcula el tiempo estimado de llegada tramo por tramo.
///
/// Dos decisiones de diseño que vale la pena defender:
///
/// 1. **Se calcula por tramo, no con una velocidad promedio del viaje.** Un
///    viaje con 400 m a pie + 9 km de metro no se parece en nada al promedio de
///    ambos; hay que sumar tiempos por separado.
///
/// 2. **La velocidad observada corrige la teórica, pero no la reemplaza.** Si el
///    metro va lento hoy, el ETA debe reflejarlo; pero si el usuario está
///    parado en un semáforo, su velocidad instantánea es 0 y el ETA no puede
///    volverse infinito. Por eso mezclamos con un promedio móvil exponencial y
///    la acotamos a una banda razonable del modo (40 %–160 % de la teórica).
class EtaCalculator {
  EtaCalculator(this.geometry, {this.transferPenalty = const Duration(seconds: 75)});

  final TripGeometry geometry;

  /// Penalización fija por transbordo: caminar dentro de la estación, subir
  /// escaleras, cruzar el andén.
  final Duration transferPenalty;

  TripPlan get plan => geometry.plan;

  EtaEstimate estimate({
    required RouteMatch match,
    required DateTime now,
    double? observedSpeedMps,
  }) {
    final double traveled = match.traveledMeters;
    double seconds = 0;
    double toEndOfLegSeconds = 0;

    for (int i = 0; i < plan.legs.length; i++) {
      final TripLeg leg = plan.legs[i];
      final double legEnd = geometry.legEndMeters[i];
      final double legStart = geometry.legStartMeters[i];
      if (legEnd <= traveled) continue; // tramo ya completado

      final double pending = legEnd - math.max(traveled, legStart);
      final bool isCurrentLeg = i == match.legIndex;

      final double speed = isCurrentLeg
          ? _blendedSpeed(leg.mode.averageSpeedMps, observedSpeedMps)
          : leg.mode.averageSpeedMps;

      final double legSeconds = pending / speed;
      seconds += legSeconds;
      if (isCurrentLeg) toEndOfLegSeconds = legSeconds;

      // Espera por abordar un tramo que todavía no ha empezado: en promedio,
      // media frecuencia de paso.
      final bool notStartedYet = traveled < legStart;
      if (notStartedYet && !leg.mode.isWalking && leg.headwayMinutes > 0) {
        seconds += leg.headwayMinutes * 60 / 2;
      }
      // Transbordo: cambiar de un tramo de transporte a otro.
      if (notStartedYet &&
          !leg.mode.isWalking &&
          i > 0 &&
          !plan.legs[i - 1].mode.isWalking) {
        seconds += transferPenalty.inSeconds;
      }
    }

    return EtaEstimate(
      remaining: Duration(seconds: seconds.round()),
      arrivalAt: now.add(Duration(seconds: seconds.round())),
      toEndOfLeg: Duration(seconds: toEndOfLegSeconds.round()),
      remainingMeters: math.max(0, geometry.totalMeters - traveled),
    );
  }

  /// Mezcla la velocidad teórica del modo con la observada por el GPS.
  double _blendedSpeed(double modeSpeed, double? observed) {
    if (observed == null || observed.isNaN || observed <= 0.4) return modeSpeed;
    final double blended = modeSpeed * 0.4 + observed * 0.6;
    return blended.clamp(modeSpeed * 0.4, modeSpeed * 1.6);
  }
}
