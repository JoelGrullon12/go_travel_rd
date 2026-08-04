import 'dart:math' as math;

import '../geo/geo_math.dart';
import '../models/location_sample.dart';
import '../models/trip_instruction.dart';
import '../models/trip_plan.dart';
import '../models/trip_progress.dart';
import 'eta_calculator.dart';
import 'instruction_engine.dart';
import 'route_matcher.dart';
import 'trip_geometry.dart';

/// Orquestador del seguimiento en tiempo real.
///
/// Recibe muestras de posición y devuelve el estado completo del viaje. Es el
/// único objeto con memoria del proceso: el emparejador, el ETA y el generador
/// de instrucciones son funciones puras, y aquí vive lo que hay que recordar
/// entre muestras (avance previo, velocidad suavizada, anti-rebote de fuera de
/// ruta, última instrucción emitida).
///
/// Es Dart puro: se prueba con `flutter test` sin emulador ni GPS.
class TripTracker {
  TripTracker(
    TripPlan plan, {
    InstructionThresholds thresholds = const InstructionThresholds(),
    this.offRouteSamplesToTrigger = 3,
    this.onRouteSamplesToRecover = 2,
  })  : geometry = TripGeometry.from(plan),
        _thresholds = thresholds {
    _matcher = RouteMatcher(geometry);
    _eta = EtaCalculator(geometry);
    _instructions = InstructionEngine(geometry, thresholds: thresholds);
  }

  final TripGeometry geometry;
  final InstructionThresholds _thresholds;

  /// Cuántas muestras seguidas fuera del corredor hacen falta para declarar
  /// "fuera de ruta". Con 1 sola, un rebote del GPS entre edificios altos —muy
  /// común en la Churchill— dispararía la alerta cada dos por tres.
  final int offRouteSamplesToTrigger;

  /// Y cuántas seguidas dentro para volver a la normalidad.
  final int onRouteSamplesToRecover;

  late final RouteMatcher _matcher;
  late final EtaCalculator _eta;
  late final InstructionEngine _instructions;

  TripPlan get plan => geometry.plan;

  double? _previousTraveled;
  LocationSample? _previousSample;
  double? _smoothedSpeedMps;
  int _offRouteStreak = 0;
  int _onRouteStreak = 0;
  bool _offRoute = false;
  bool _hasStarted = false;
  String? _lastInstructionKey;

  TripProgress? _last;
  TripProgress? get last => _last;

  /// Procesa una muestra y devuelve el nuevo estado del viaje.
  TripProgress onSample(LocationSample sample) {
    final RouteMatch match = _matcher.match(
      sample.position,
      previousTraveledMeters: _previousTraveled,
    );

    // ── Fuera de ruta, con anti-rebote ──────────────────────────────────────
    // Un GPS con precisión de 50 m no puede "probar" una desviación de 70 m,
    // así que el umbral se relaja con la precisión reportada.
    final double tolerance = _thresholds.offRouteMeters +
        math.min(60, (sample.accuracyMeters ?? 0) * 0.5);
    if (match.distanceFromRouteMeters > tolerance) {
      _offRouteStreak++;
      _onRouteStreak = 0;
      if (_offRouteStreak >= offRouteSamplesToTrigger) _offRoute = true;
    } else {
      _onRouteStreak++;
      _offRouteStreak = 0;
      if (_onRouteStreak >= onRouteSamplesToRecover) _offRoute = false;
    }

    // ── Velocidad suavizada ─────────────────────────────────────────────────
    final double? instantSpeed = _instantSpeed(sample);
    if (instantSpeed != null) {
      _smoothedSpeedMps = _smoothedSpeedMps == null
          ? instantSpeed
          : _smoothedSpeedMps! * 0.7 + instantSpeed * 0.3;
    }

    // "Ya arrancó" = se movió lo suficiente como para que no sea ruido del GPS.
    if (!_hasStarted && match.traveledMeters > 15) _hasStarted = true;

    final EtaEstimate eta = _eta.estimate(
      match: match,
      now: sample.timestamp,
      observedSpeedMps: _smoothedSpeedMps,
    );

    final TripInstruction instruction = _instructions.build(
      match: match,
      offRoute: _offRoute,
      hasStarted: _hasStarted,
    );

    final bool isNew = instruction.key != _lastInstructionKey;
    _lastInstructionKey = instruction.key;
    _previousTraveled = match.traveledMeters;
    _previousSample = sample;

    final int legIndex = match.legIndex.clamp(0, plan.legs.length - 1);
    final TripProgress progress = TripProgress(
      plan: plan,
      match: match,
      eta: eta,
      instruction: instruction,
      isNewInstruction: isNew,
      offRoute: _offRoute,
      currentLegIndex: legIndex,
      metersToLegEnd:
          math.max(0, geometry.legEndMeters[legIndex] - match.traveledMeters),
      upcomingStops: geometry.upcomingStopsOfLeg(legIndex, match.traveledMeters),
      timestamp: sample.timestamp,
      totalMeters: geometry.totalMeters,
      rawPosition: sample.position,
      speedMps: _smoothedSpeedMps,
      headingDegrees:
          sample.headingDegrees ?? geometry.headingAt(match.traveledMeters),
      accuracyMeters: sample.accuracyMeters,
      isSimulated: sample.isSimulated,
    );

    _last = progress;
    return progress;
  }

  /// Reinicia el seguimiento (cambio de plan, o el usuario reinicia el viaje).
  void reset() {
    _previousTraveled = null;
    _previousSample = null;
    _smoothedSpeedMps = null;
    _offRouteStreak = 0;
    _onRouteStreak = 0;
    _offRoute = false;
    _hasStarted = false;
    _lastInstructionKey = null;
    _last = null;
  }

  /// Velocidad de esta muestra.
  ///
  /// Se prefiere la del proveedor (viene del Doppler del chip GPS y es más
  /// estable); si no la trae, se deriva de la distancia entre muestras.
  double? _instantSpeed(LocationSample sample) {
    final double? reported = sample.speedMps;
    if (reported != null && !reported.isNaN && reported >= 0) return reported;

    final LocationSample? prev = _previousSample;
    if (prev == null) return null;
    final double seconds =
        sample.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
    if (seconds <= 0.2) return null;
    return distanceMeters(prev.position, sample.position) / seconds;
  }
}
