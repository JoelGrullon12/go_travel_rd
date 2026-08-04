import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/location_sample.dart';
import '../domain/models/trip_plan.dart';
import '../domain/models/trip_progress.dart';
import '../domain/tracking/trip_tracker.dart';
import '../services/location/device_location_source.dart';
import '../services/location/location_source.dart';
import '../services/location/simulated_location_source.dart';

enum TripStatus { idle, connecting, tracking, paused, arrived, error }

/// De dónde salen las posiciones durante el viaje.
enum LocationMode {
  /// GPS real. Es el modo de producción.
  device('GPS del dispositivo'),

  /// Recorrido sintético sobre el plan. Es el modo de demostración y de prueba.
  simulated('Simulador');

  const LocationMode(this.label);
  final String label;
}

class LiveTripState {
  const LiveTripState({
    required this.plan,
    required this.status,
    required this.mode,
    this.progress,
    this.errorMessage,
    this.canRetry = true,
    this.simulationSpeed = 6,
    this.simulatedDeviationMeters = 0,
  });

  final TripPlan plan;
  final TripStatus status;
  final LocationMode mode;
  final TripProgress? progress;
  final String? errorMessage;
  final bool canRetry;
  final double simulationSpeed;
  final double simulatedDeviationMeters;

  bool get isLive => status == TripStatus.tracking || status == TripStatus.paused;
  bool get isSimulated => mode == LocationMode.simulated;

  LiveTripState copyWith({
    TripStatus? status,
    LocationMode? mode,
    TripProgress? progress,
    Object? errorMessage = _sentinel,
    bool? canRetry,
    double? simulationSpeed,
    double? simulatedDeviationMeters,
  }) =>
      LiveTripState(
        plan: plan,
        status: status ?? this.status,
        mode: mode ?? this.mode,
        progress: progress ?? this.progress,
        errorMessage: identical(errorMessage, _sentinel)
            ? this.errorMessage
            : errorMessage as String?,
        canRetry: canRetry ?? this.canRetry,
        simulationSpeed: simulationSpeed ?? this.simulationSpeed,
        simulatedDeviationMeters:
            simulatedDeviationMeters ?? this.simulatedDeviationMeters,
      );

  static const Object _sentinel = Object();
}

/// Controlador del viaje activo.
///
/// Conecta las tres piezas y no hace nada más: la fuente de ubicación
/// ([LocationSource]) alimenta al motor ([TripTracker]), y el resultado se
/// publica como estado para la UI. Toda la lógica de seguimiento vive en
/// `domain/`, sin Flutter de por medio; aquí solo hay cableado y ciclo de vida.
class LiveTripController extends StateNotifier<LiveTripState> {
  LiveTripController(TripPlan plan)
      : _tracker = TripTracker(plan),
        super(
          LiveTripState(
            plan: plan,
            status: TripStatus.idle,
            // El simulador es el modo por defecto a propósito: en un emulador o
            // en el navegador el GPS no se mueve, y arrancar en "GPS real"
            // dejaría la pantalla congelada sin explicación.
            mode: LocationMode.simulated,
          ),
        );

  final TripTracker _tracker;
  LocationSource? _source;
  StreamSubscription<LocationSample>? _subscription;

  TripTracker get tracker => _tracker;

  Future<void> start({LocationMode? mode}) async {
    final LocationMode target = mode ?? state.mode;
    await _teardown();
    _tracker.reset();

    state = state.copyWith(
      status: TripStatus.connecting,
      mode: target,
      errorMessage: null,
    );

    final LocationSource source = switch (target) {
      LocationMode.device => DeviceLocationSource(),
      LocationMode.simulated => SimulatedLocationSource(
          _tracker.geometry,
          speedMultiplier: state.simulationSpeed,
        ),
    };
    _source = source;

    _subscription = source.watch().listen(
      _onSample,
      onError: (Object error) {
        final String message = error is LocationUnavailable
            ? error.message
            : 'No pudimos leer tu ubicación: $error';
        state = state.copyWith(
          status: TripStatus.error,
          errorMessage: message,
          canRetry: error is! LocationUnavailable || error.canRetry,
        );
      },
    );
  }

  void _onSample(LocationSample sample) {
    final TripProgress progress = _tracker.onSample(sample);
    state = state.copyWith(
      status: progress.hasArrived
          ? TripStatus.arrived
          : (state.status == TripStatus.paused
              ? TripStatus.paused
              : TripStatus.tracking),
      progress: progress,
      errorMessage: null,
    );
    if (progress.hasArrived) _simulator?.pause();
  }

  SimulatedLocationSource? get _simulator =>
      _source is SimulatedLocationSource ? _source! as SimulatedLocationSource : null;

  /// Pausar solo tiene sentido en simulación: el mundo real no se pausa.
  void pause() {
    _simulator?.pause();
    if (state.status == TripStatus.tracking) {
      state = state.copyWith(status: TripStatus.paused);
    }
  }

  void resume() {
    _simulator?.resume();
    if (state.status == TripStatus.paused) {
      state = state.copyWith(status: TripStatus.tracking);
    }
  }

  void setSimulationSpeed(double multiplier) {
    _simulator?.speedMultiplier = multiplier;
    state = state.copyWith(simulationSpeed: multiplier);
  }

  /// Fuerza una desviación lateral para demostrar en vivo la detección de
  /// "te saliste de la ruta" sin tener que salirse de verdad.
  void setSimulatedDeviation(double meters) {
    _simulator?.lateralOffsetMeters = meters;
    state = state.copyWith(simulatedDeviationMeters: meters);
  }

  /// Salta a una fracción del viaje (para enseñar el final sin esperarlo).
  void seekToFraction(double fraction) {
    final SimulatedLocationSource? sim = _simulator;
    if (sim == null) return;
    sim.seekToFraction(fraction);
    if (state.status == TripStatus.arrived) {
      state = state.copyWith(status: TripStatus.tracking);
      sim.resume();
    }
  }

  Future<void> restart() async {
    await start(mode: state.mode);
  }

  Future<void> stop() async {
    await _teardown();
    _tracker.reset();
    state = state.copyWith(status: TripStatus.idle, errorMessage: null);
  }

  Future<void> _teardown() async {
    await _subscription?.cancel();
    _subscription = null;
    await _source?.dispose();
    _source = null;
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
