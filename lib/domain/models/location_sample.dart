import '../geo/geo_point.dart';

/// Una lectura de posición.
///
/// Es el único formato que entra al motor de seguimiento, venga del GPS real o
/// del simulador. Gracias a eso el simulador no es un "modo especial" con
/// código aparte: recorre exactamente el mismo camino que la señal real.
class LocationSample {
  const LocationSample({
    required this.position,
    required this.timestamp,
    this.accuracyMeters,
    this.speedMps,
    this.headingDegrees,
    this.isSimulated = false,
  });

  final GeoPoint position;
  final DateTime timestamp;

  /// Precisión reportada por el proveedor (radio de confianza, en metros).
  final double? accuracyMeters;

  /// Velocidad instantánea. Puede venir nula o sin sentido en interiores.
  final double? speedMps;

  final double? headingDegrees;

  final bool isSimulated;
}
