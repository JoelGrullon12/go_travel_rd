import 'dart:async';
import 'dart:math' as math;

import '../../domain/geo/geo_math.dart';
import '../../domain/geo/geo_point.dart';
import '../../domain/models/location_sample.dart';
import '../../domain/tracking/trip_geometry.dart';
import 'location_source.dart';

/// Simulador de viaje: recorre el plan como si el usuario fuera dentro.
///
/// No es un adorno de desarrollo, es parte de la entrega. Sin él el Hito 4 es
/// indemostrable: en un emulador el GPS no se mueve, y probar el flujo completo
/// en la calle son 40 minutos de metro por cada corrida.
///
/// Emite en el mismo formato que el GPS real ([LocationSample]), así que el
/// motor de seguimiento no distingue entre uno y otro — lo que se demuestra en
/// clase es exactamente el mismo código que corre en la calle.
class SimulatedLocationSource implements LocationSource {
  SimulatedLocationSource(
    this.geometry, {
    this.tick = const Duration(milliseconds: 400),
    double speedMultiplier = 6,
    this.noiseMeters = 6,
    int randomSeed = 7,
    // El campo es privado y mutable (tiene setter público), así que no puede
    // recibirse como parámetro con nombre inicializador: los nombres de
    // parámetros no pueden empezar con guion bajo.
    // ignore: prefer_initializing_formals
  })  : _speedMultiplier = speedMultiplier,
        _random = math.Random(randomSeed);

  final TripGeometry geometry;
  final Duration tick;

  /// Ruido gaussiano añadido a cada posición, para que la demo se parezca a un
  /// GPS de verdad y no a un punto perfecto sobre la línea. También ejercita el
  /// suavizado y el anti-rebote de fuera de ruta.
  final double noiseMeters;

  final math.Random _random;

  double _speedMultiplier;
  double _traveled = 0;
  double _lateralOffsetMeters = 0;
  bool _paused = false;
  Timer? _timer;
  StreamController<LocationSample>? _controller;

  /// Velocidad de la simulación. 1× = tiempo real (un viaje de 40 min dura 40
  /// min). En la demo se usa 6×–15×.
  double get speedMultiplier => _speedMultiplier;
  set speedMultiplier(double value) => _speedMultiplier = value.clamp(0.25, 40);

  /// Desviación lateral forzada, en metros. Sirve para demostrar en vivo la
  /// detección de "te saliste de la ruta" sin tener que salirse de verdad.
  double get lateralOffsetMeters => _lateralOffsetMeters;
  set lateralOffsetMeters(double value) =>
      _lateralOffsetMeters = value.clamp(0, 2000);

  double get traveledMeters => _traveled;
  bool get isPaused => _paused;

  @override
  String get label => 'Simulador de viaje';

  @override
  bool get isSimulated => true;

  @override
  Stream<LocationSample> watch() {
    final StreamController<LocationSample> controller =
        StreamController<LocationSample>.broadcast(onCancel: dispose);
    _controller = controller;
    _timer = Timer.periodic(tick, (_) => _emit(controller));
    // Primera muestra inmediata: la pantalla no arranca vacía.
    scheduleMicrotask(() => _emit(controller));
    return controller.stream;
  }

  void pause() => _paused = true;
  void resume() => _paused = false;

  /// Salta a una distancia concreta del viaje (para demostrar el final sin
  /// esperar todo el recorrido).
  void seekTo(double meters) =>
      _traveled = meters.clamp(0.0, geometry.totalMeters);

  void seekToFraction(double fraction) =>
      seekTo(geometry.totalMeters * fraction.clamp(0.0, 1.0));

  void restart() {
    _traveled = 0;
    _lateralOffsetMeters = 0;
    _paused = false;
  }

  void _emit(StreamController<LocationSample> controller) {
    if (controller.isClosed) return;

    if (!_paused) {
      // La velocidad sale del modo del tramo en el que va: caminar 4.8 km/h,
      // metro 32 km/h. Así el simulador no solo mueve un punto, reproduce el
      // ritmo real del viaje.
      final int legIndex = geometry.legIndexAt(_traveled);
      final double baseSpeed =
          geometry.plan.legs[legIndex].mode.averageSpeedMps;
      final double seconds = tick.inMilliseconds / 1000.0;
      _traveled = math.min(
        geometry.totalMeters,
        _traveled + baseSpeed * _speedMultiplier * seconds,
      );
    }

    final GeoPoint onRoute = geometry.pointAt(_traveled);
    final double heading = geometry.headingAt(_traveled);

    GeoPoint position = onRoute;
    if (_lateralOffsetMeters > 0) {
      // Desviación perpendicular al sentido de marcha.
      position = offsetMeters(position, _lateralOffsetMeters, heading + 90);
    }
    if (noiseMeters > 0) {
      position = offsetMeters(
        position,
        _gaussian() * noiseMeters,
        _random.nextDouble() * 360,
      );
    }

    final int legIndex = geometry.legIndexAt(_traveled);
    controller.add(
      LocationSample(
        position: position,
        timestamp: DateTime.now(),
        accuracyMeters: 8,
        speedMps: _paused
            ? 0
            : geometry.plan.legs[legIndex].mode.averageSpeedMps,
        headingDegrees: heading,
        isSimulated: true,
      ),
    );
  }

  /// Ruido normal(0,1) por Box-Muller. Un `nextDouble()` plano produce un error
  /// uniforme que no se parece al de un GPS real.
  double _gaussian() {
    final double u1 = math.max(1e-9, _random.nextDouble());
    final double u2 = _random.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _controller?.close();
    _controller = null;
  }
}
