import '../../domain/models/location_sample.dart';

/// Origen de las lecturas de posición.
///
/// La abstracción existe por una razón concreta: el seguimiento en tiempo real
/// es imposible de probar y de demostrar si depende directamente del GPS. Con
/// esta interfaz, el GPS real y el simulador son intercambiables y el motor de
/// seguimiento no sabe cuál está corriendo.
abstract class LocationSource {
  /// Nombre para mostrar en la UI ("GPS del dispositivo", "Simulador").
  String get label;

  /// `true` si las posiciones son sintéticas. La UI lo marca en pantalla para
  /// que nadie confunda una demo con un viaje real.
  bool get isSimulated;

  /// Flujo de posiciones. Se cierra al llamar [dispose].
  Stream<LocationSample> watch();

  Future<void> dispose();
}

/// Error de ubicación con un mensaje que se le puede enseñar al usuario.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message, {this.canRetry = true});

  final String message;
  final bool canRetry;

  @override
  String toString() => 'LocationUnavailable: $message';
}
