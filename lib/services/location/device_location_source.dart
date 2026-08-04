import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../domain/geo/geo_point.dart';
import '../../domain/models/location_sample.dart';
import 'location_source.dart';

/// GPS real del dispositivo, vía `geolocator`.
class DeviceLocationSource implements LocationSource {
  DeviceLocationSource({this.distanceFilterMeters = 4});

  /// Solo emitir cuando el usuario se mueva al menos estos metros. Baja el
  /// consumo de batería y evita que el punto "tiemble" estando quieto.
  final int distanceFilterMeters;

  StreamSubscription<Position>? _subscription;
  StreamController<LocationSample>? _controller;

  @override
  String get label => 'GPS del dispositivo';

  @override
  bool get isSimulated => false;

  @override
  Stream<LocationSample> watch() {
    final StreamController<LocationSample> controller =
        StreamController<LocationSample>.broadcast(onCancel: dispose);
    _controller = controller;
    _start(controller);
    return controller.stream;
  }

  Future<void> _start(StreamController<LocationSample> controller) async {
    try {
      await _ensurePermission();

      // `bestForNavigation` pide al SO la mayor precisión disponible: es lo que
      // corresponde cuando el usuario está siguiendo instrucciones paso a paso.
      const LocationSettings settings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 4,
      );

      // Primera posición inmediata: no hacemos esperar al usuario a que se
      // mueva 4 metros para que la pantalla deje de estar vacía.
      try {
        final Position current = await Geolocator.getCurrentPosition(
          locationSettings: settings,
        );
        if (!controller.isClosed) controller.add(_toSample(current));
      } catch (_) {
        // Sin fix inicial no pasa nada: el stream la traerá.
      }

      _subscription =
          Geolocator.getPositionStream(locationSettings: settings).listen(
        (Position position) {
          if (!controller.isClosed) controller.add(_toSample(position));
        },
        onError: (Object error) {
          if (!controller.isClosed) {
            controller.addError(
              LocationUnavailable('Se perdió la señal del GPS: $error'),
            );
          }
        },
      );
    } on LocationUnavailable catch (error) {
      if (!controller.isClosed) controller.addError(error);
    } catch (error) {
      if (!controller.isClosed) {
        controller.addError(
          LocationUnavailable('No se pudo iniciar la ubicación: $error'),
        );
      }
    }
  }

  /// Pide permiso y traduce cada fallo a un mensaje accionable.
  ///
  /// El usuario no tiene por qué saber qué es `LocationPermission.deniedForever`:
  /// necesita saber qué hacer.
  Future<void> _ensurePermission() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationUnavailable(
        'La ubicación del teléfono está apagada. Actívala para seguir tu viaje.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable(
        'Bloqueaste el permiso de ubicación. Habilítalo desde los ajustes '
        'del teléfono para usar el seguimiento en vivo.',
        canRetry: false,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationUnavailable(
        'Necesitamos tu ubicación para saber en qué parte del viaje vas.',
      );
    }
  }

  LocationSample _toSample(Position position) => LocationSample(
        position: GeoPoint(position.latitude, position.longitude),
        timestamp: position.timestamp,
        accuracyMeters: position.accuracy,
        speedMps: position.speed,
        headingDegrees: position.heading,
      );

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _controller?.close();
    _controller = null;
  }
}
