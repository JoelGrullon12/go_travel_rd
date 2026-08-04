import 'trip_plan.dart';

/// Qué le estamos diciendo al usuario que haga ahora mismo.
enum InstructionKind {
  /// Aún no ha empezado a moverse.
  start,

  /// Caminando hacia la parada/estación de abordaje.
  walkToBoarding,

  /// Ya está en la parada: que se monte.
  board,

  /// Va en el vehículo, con margen de sobra.
  riding,

  /// Falta poco: que se prepare para bajar.
  prepareToExit,

  /// Bájate ahora.
  exitNow,

  /// Se bajó y tiene que cambiar de línea.
  transfer,

  /// Último tramo a pie hacia el destino.
  walkToDestination,

  /// Llegó.
  arrived,

  /// Se salió de la ruta planificada.
  offRoute,
}

/// Cuánto ruido merece la instrucción: color, vibración y anuncio por voz.
enum InstructionUrgency {
  /// Informativa. Sin vibración.
  calm,

  /// Requiere atención pronto. Vibración media.
  headsUp,

  /// Acción inmediata o error. Vibración fuerte.
  critical,
}

/// Una instrucción de viaje lista para mostrar.
class TripInstruction {
  const TripInstruction({
    required this.key,
    required this.kind,
    required this.urgency,
    required this.title,
    required this.detail,
    this.legIndex,
    this.targetStop,
    this.distanceMeters,
    this.lineColorHex,
  });

  /// Identidad estable de la instrucción.
  ///
  /// El título y el detalle cambian en cada muestra del GPS (la distancia baja
  /// metro a metro), pero mientras la `key` no cambie es *la misma* instrucción.
  /// De ahí sale saber cuándo vibrar, cuándo animar la tarjeta y cuándo
  /// anunciar por accesibilidad — una sola vez, no 20 veces por minuto.
  final String key;

  final InstructionKind kind;
  final InstructionUrgency urgency;

  /// Frase principal, en imperativo y corta: se lee de un vistazo en la guagua.
  final String title;

  /// Línea de apoyo: estación, línea, distancia.
  final String detail;

  final int? legIndex;
  final TripStop? targetStop;
  final double? distanceMeters;
  final int? lineColorHex;
}
