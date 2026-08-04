/// Modo de transporte de un tramo del viaje.
///
/// Cubre los dos tipos de ruta que definió el equipo (AGENTS.md §10):
/// con paradas fijas (metro, teleférico, corredor, OMSA) y sin paradas fijas
/// (concho, motoconcho). `walk` es el pegamento entre tramos.
enum TransportMode {
  walk('walk', 'A pie'),
  metro('metro', 'Metro'),
  teleferico('teleferico', 'Teleférico'),
  corredor('corredor', 'Corredor'),
  omsa('omsa', 'OMSA'),
  concho('concho', 'Concho'),
  motoconcho('motoconcho', 'Motoconcho');

  const TransportMode(this.code, this.label);

  /// Identificador estable para JSON/Firestore. No usar `name` del enum
  /// directamente en persistencia: renombrar el enum rompería los datos.
  final String code;
  final String label;

  bool get isWalking => this == TransportMode.walk;

  /// ¿Tiene paradas fijas y por tanto instrucciones tipo "bájate en X"?
  bool get hasFixedStops =>
      this == TransportMode.metro ||
      this == TransportMode.teleferico ||
      this == TransportMode.corredor ||
      this == TransportMode.omsa;

  /// Velocidad comercial promedio en km/h — incluye paradas y semáforos, no es
  /// la velocidad punta del vehículo.
  ///
  /// Fuente: velocidades comerciales típicas del transporte urbano en Santo
  /// Domingo. Son estimaciones del equipo, no dato oficial del INTRANT: por eso
  /// el cálculo de ETA las usa solo como base y las corrige con la velocidad
  /// real observada del GPS (ver [EtaCalculator]).
  double get averageSpeedKmh => switch (this) {
        TransportMode.walk => 4.8,
        TransportMode.metro => 32.0,
        TransportMode.teleferico => 18.0,
        TransportMode.corredor => 19.0,
        TransportMode.omsa => 17.0,
        TransportMode.concho => 15.0,
        TransportMode.motoconcho => 22.0,
      };

  double get averageSpeedMps => averageSpeedKmh / 3.6;

  static TransportMode fromCode(String code) => TransportMode.values.firstWhere(
        (m) => m.code == code,
        orElse: () => TransportMode.walk,
      );
}
