import '../geo/geo_math.dart';
import '../geo/geo_point.dart';
import 'transport_mode.dart';

/// Parada o estación dentro de un tramo del viaje.
class TripStop {
  const TripStop({
    required this.id,
    required this.name,
    required this.position,
    this.isTransfer = false,
  });

  final String id;
  final String name;
  final GeoPoint position;

  /// Estación de transbordo (ej. Juan Pablo Duarte entre L1 y L2).
  final bool isTransfer;

  factory TripStop.fromJson(Map<String, dynamic> json) => TripStop(
        id: json['id'] as String,
        name: json['name'] as String,
        position: GeoPoint.fromJson(json['position'] as Map<String, dynamic>),
        isTransfer: json['is_transfer'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'position': position.toJson(),
        'is_transfer': isTransfer,
      };
}

/// Un tramo del viaje: caminar hasta la estación, o viajar en una línea.
class TripLeg {
  TripLeg({
    required this.id,
    required this.mode,
    required this.path,
    this.lineName = '',
    this.lineColorHex = 0xFF8B94A8,
    this.headsign = '',
    this.stops = const <TripStop>[],
    this.fareDop = 0,
    this.headwayMinutes = 0,
  }) : assert(path.length >= 2, 'Un tramo necesita al menos 2 puntos');

  final String id;
  final TransportMode mode;

  /// Geometría del tramo. Para tramos de transporte son los vértices del
  /// trazado; para tramos a pie, la ruta peatonal (hoy: línea recta entre
  /// extremos; cuando entre Directions API serán los vértices reales).
  final List<GeoPoint> path;

  /// "Línea 1", "Corredor Núñez de Cáceres"…
  final String lineName;

  /// Color de la línea en ARGB. Viene del dato, no del tema: cada línea de
  /// transporte tiene su color oficial y la UI debe respetarlo.
  final int lineColorHex;

  /// Hacia dónde va el vehículo: "dirección Centro de los Héroes".
  final String headsign;

  /// Paradas del tramo, en orden de recorrido. Incluye la de abordaje y la de
  /// bajada. Vacío en tramos a pie.
  final List<TripStop> stops;

  /// Costo del tramo en pesos dominicanos.
  final double fareDop;

  /// Frecuencia de paso en minutos. Se usa para estimar la espera al abordar
  /// (esperas en promedio la mitad de la frecuencia).
  final int headwayMinutes;

  GeoPoint get start => path.first;
  GeoPoint get end => path.last;

  TripStop? get boardingStop => stops.isEmpty ? null : stops.first;
  TripStop? get alightingStop => stops.isEmpty ? null : stops.last;

  double? _distanceCache;
  double get distanceMeters => _distanceCache ??= polylineLengthMeters(path);

  /// Nombre corto para mostrar en chips y listas.
  String get shortLabel => lineName.isEmpty ? mode.label : lineName;

  factory TripLeg.fromJson(Map<String, dynamic> json) => TripLeg(
        id: json['id'] as String,
        mode: TransportMode.fromCode(json['mode'] as String),
        path: (json['path'] as List)
            .map((e) => GeoPoint.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        lineName: json['line_name'] as String? ?? '',
        lineColorHex: json['line_color'] as int? ?? 0xFF8B94A8,
        headsign: json['headsign'] as String? ?? '',
        stops: (json['stops'] as List? ?? const [])
            .map((e) => TripStop.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        fareDop: (json['fare_dop'] as num?)?.toDouble() ?? 0,
        headwayMinutes: (json['headway_minutes'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'mode': mode.code,
        'path': path.map((p) => p.toJson()).toList(),
        'line_name': lineName,
        'line_color': lineColorHex,
        'headsign': headsign,
        'stops': stops.map((s) => s.toJson()).toList(),
        'fare_dop': fareDop,
        'headway_minutes': headwayMinutes,
      };
}

/// Plan de viaje A→B ya resuelto.
///
/// ── CONTRATO CON EL HITO 2 ────────────────────────────────────────────────
/// Este es el objeto que el motor de cálculo de ruta (Hito 2) le entrega al
/// seguimiento en tiempo real (Hito 4). El Hito 4 NO calcula rutas: las
/// consume. Los planes realistas para los tests viven en
/// `test/support/demo_trip_plans.dart`.
///
/// Para conectar el motor real basta con que devuelva un `TripPlan`
/// (o su JSON, vía [TripPlan.fromJson]). Nada más de esta capa cambia.
/// ──────────────────────────────────────────────────────────────────────────
class TripPlan {
  const TripPlan({
    required this.id,
    required this.originName,
    required this.destinationName,
    required this.legs,
  });

  final String id;
  final String originName;
  final String destinationName;
  final List<TripLeg> legs;

  GeoPoint get origin => legs.first.start;
  GeoPoint get destination => legs.last.end;

  double get totalFareDop =>
      legs.fold<double>(0, (sum, leg) => sum + leg.fareDop);

  double get totalDistanceMeters =>
      legs.fold<double>(0, (sum, leg) => sum + leg.distanceMeters);

  /// Cantidad de transbordos = tramos de transporte menos uno.
  int get transferCount {
    final int transitLegs = legs.where((l) => !l.mode.isWalking).length;
    return transitLegs <= 1 ? 0 : transitLegs - 1;
  }

  factory TripPlan.fromJson(Map<String, dynamic> json) => TripPlan(
        id: json['id'] as String,
        originName: json['origin_name'] as String,
        destinationName: json['destination_name'] as String,
        legs: (json['legs'] as List)
            .map((e) => TripLeg.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'origin_name': originName,
        'destination_name': destinationName,
        'legs': legs.map((l) => l.toJson()).toList(),
      };
}
