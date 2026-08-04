import '../geo/geo_point.dart';
import '../tracking/eta_calculator.dart';
import '../tracking/route_matcher.dart';
import 'trip_instruction.dart';
import 'trip_plan.dart';

/// Foto completa del viaje en un instante.
///
/// Es inmutable a propósito: la UI recibe un objeto nuevo por muestra y puede
/// comparar con el anterior para decidir qué animar. Nada de mutar el estado
/// por debajo de los widgets.
class TripProgress {
  const TripProgress({
    required this.plan,
    required this.match,
    required this.eta,
    required this.instruction,
    required this.isNewInstruction,
    required this.offRoute,
    required this.currentLegIndex,
    required this.metersToLegEnd,
    required this.upcomingStops,
    required this.timestamp,
    required this.totalMeters,
    required this.rawPosition,
    this.speedMps,
    this.headingDegrees,
    this.accuracyMeters,
    this.isSimulated = false,
  });

  final TripPlan plan;
  final RouteMatch match;
  final EtaEstimate eta;
  final TripInstruction instruction;

  /// `true` solo en la primera muestra en que aparece esta instrucción.
  /// La UI lo usa para vibrar y anunciar una sola vez.
  final bool isNewInstruction;

  final bool offRoute;
  final int currentLegIndex;
  final double metersToLegEnd;

  /// Paradas que faltan del tramo actual, en orden.
  final List<TripStop> upcomingStops;

  final DateTime timestamp;
  final double totalMeters;

  /// Posición cruda del GPS, sin pegar a la ruta. Se dibuja aparte cuando el
  /// usuario está fuera de ruta: ahí la posición pegada mentiría.
  final GeoPoint rawPosition;

  final double? speedMps;
  final double? headingDegrees;
  final double? accuracyMeters;
  final bool isSimulated;

  TripLeg get currentLeg => plan.legs[currentLegIndex];
  TripStop? get nextStop => upcomingStops.isEmpty ? null : upcomingStops.first;

  double get traveledMeters => match.traveledMeters;
  double get remainingMeters => eta.remainingMeters;

  /// Fracción completada del viaje, en [0, 1].
  double get fraction =>
      totalMeters <= 0 ? 0 : (match.traveledMeters / totalMeters).clamp(0.0, 1.0);

  bool get hasArrived => instruction.kind == InstructionKind.arrived;

  /// Fracción completada de un tramo concreto, para la barra segmentada.
  double fractionOfLeg(int legIndex, double legStart, double legEnd) {
    final double length = legEnd - legStart;
    if (length <= 0) return match.traveledMeters >= legEnd ? 1 : 0;
    return ((match.traveledMeters - legStart) / length).clamp(0.0, 1.0);
  }
}
