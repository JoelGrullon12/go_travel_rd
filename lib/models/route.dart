import 'package:cloud_firestore/cloud_firestore.dart';

class RouteSchedule {
  final String day;
  final int startMinutes;
  final int finishMinutes;

  const RouteSchedule({
    required this.day,
    required this.startMinutes,
    required this.finishMinutes,
  });

  factory RouteSchedule.fromMap(Map<String, dynamic> map) => RouteSchedule(
        day: map['day'] as String? ?? '',
        startMinutes: (map['startMinutes'] as num?)?.toInt() ?? 0,
        finishMinutes: (map['finishMinutes'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'day': day,
        'startMinutes': startMinutes,
        'finishMinutes': finishMinutes,
      };
}

class RouteStation {
  final String stationId;
  final int order;
  final String name;
  final GeoPoint location;

  const RouteStation({
    required this.stationId,
    required this.order,
    required this.name,
    required this.location,
  });

  factory RouteStation.fromMap(Map<String, dynamic> map) => RouteStation(
        stationId: map['stationId'] as String? ?? '',
        order: (map['order'] as num?)?.toInt() ?? 0,
        name: map['name'] as String? ?? '',
        location: map['location'] as GeoPoint? ?? const GeoPoint(0, 0),
      );

  Map<String, dynamic> toMap() => {
        'stationId': stationId,
        'order': order,
        'name': name,
        'location': location,
      };
}

class Route {
  final String id;
  final String name;
  final String transportTypeId;
  final String province;
  final List<RouteSchedule> schedule;
  final double price;
  final double avgMinutesPerKm;
  final bool active;
  final bool hasFixedStations;
  final GeoPoint? startLocation;
  final GeoPoint? finishLocation;
  final List<RouteStation>? stations;

  const Route({
    required this.id,
    required this.name,
    required this.transportTypeId,
    required this.province,
    this.schedule = const [],
    this.price = 0.0,
    this.avgMinutesPerKm = 0.0,
    this.active = true,
    this.hasFixedStations = true,
    this.startLocation,
    this.finishLocation,
    this.stations,
  });

  factory Route.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Route.fromMap(data, doc.id);
  }

  factory Route.fromMap(Map<String, dynamic> map, String id) {
    final schedule = (map['schedule'] as List? ?? [])
        .map((e) => RouteSchedule.fromMap(e as Map<String, dynamic>))
        .toList();
    final stations = (map['stations'] as List?)
        ?.map((e) => RouteStation.fromMap(e as Map<String, dynamic>))
        .toList();
    return Route(
      id: id,
      name: map['name'] as String? ?? '',
      transportTypeId: map['transportTypeId'] as String? ?? '',
      province: map['province'] as String? ?? '',
      schedule: schedule,
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      avgMinutesPerKm: (map['avgMinutesPerKm'] as num?)?.toDouble() ?? 0.0,
      active: map['active'] as bool? ?? true,
      hasFixedStations: map['hasFixedStations'] as bool? ?? true,
      startLocation: map['startLocation'] as GeoPoint?,
      finishLocation: map['finishLocation'] as GeoPoint?,
      stations: stations,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'transportTypeId': transportTypeId,
        'province': province,
        'schedule': schedule.map((e) => e.toMap()).toList(),
        'price': price,
        'avgMinutesPerKm': avgMinutesPerKm,
        'active': active,
        'hasFixedStations': hasFixedStations,
        if (startLocation != null) 'startLocation': startLocation,
        if (finishLocation != null) 'finishLocation': finishLocation,
        if (stations != null) 'stations': stations!.map((e) => e.toMap()).toList(),
      };

  Route copyWith({
    String? name,
    String? transportTypeId,
    String? province,
    List<RouteSchedule>? schedule,
    double? price,
    double? avgMinutesPerKm,
    bool? active,
    bool? hasFixedStations,
    GeoPoint? startLocation,
    GeoPoint? finishLocation,
    List<RouteStation>? stations,
  }) =>
      Route(
        id: id,
        name: name ?? this.name,
        transportTypeId: transportTypeId ?? this.transportTypeId,
        province: province ?? this.province,
        schedule: schedule ?? this.schedule,
        price: price ?? this.price,
        avgMinutesPerKm: avgMinutesPerKm ?? this.avgMinutesPerKm,
        active: active ?? this.active,
        hasFixedStations: hasFixedStations ?? this.hasFixedStations,
        startLocation: startLocation ?? this.startLocation,
        finishLocation: finishLocation ?? this.finishLocation,
        stations: stations ?? this.stations,
      );
}
