import 'package:cloud_firestore/cloud_firestore.dart';

class UserRoute {
  final String id;
  final String name;
  final GeoPoint startLocation;
  final GeoPoint finishLocation;

  /// Nombres geocodificados (calle/establecimiento) de los extremos, para
  /// mostrarlos en el listado de favoritos sin re-consultar al geocoder.
  /// Vacíos en rutas guardadas antes de esta versión → la UI cae a
  /// coordenadas.
  final String startName;
  final String finishName;
  final String preferredTransportTypeId;

  const UserRoute({
    required this.id,
    required this.name,
    required this.startLocation,
    required this.finishLocation,
    this.startName = '',
    this.finishName = '',
    required this.preferredTransportTypeId,
  });

  factory UserRoute.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserRoute.fromMap(data, doc.id);
  }

  factory UserRoute.fromMap(Map<String, dynamic> map, String id) =>
      UserRoute(
        id: id,
        name: map['name'] as String? ?? '',
        startLocation:
            map['startLocation'] as GeoPoint? ?? const GeoPoint(0, 0),
        finishLocation:
            map['finishLocation'] as GeoPoint? ?? const GeoPoint(0, 0),
        startName: map['startName'] as String? ?? '',
        finishName: map['finishName'] as String? ?? '',
        preferredTransportTypeId:
            map['preferredTransportTypeId'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'startLocation': startLocation,
        'finishLocation': finishLocation,
        'startName': startName,
        'finishName': finishName,
        'preferredTransportTypeId': preferredTransportTypeId,
      };

  UserRoute copyWith({
    String? name,
    GeoPoint? startLocation,
    GeoPoint? finishLocation,
    String? startName,
    String? finishName,
    String? preferredTransportTypeId,
  }) =>
      UserRoute(
        id: id,
        name: name ?? this.name,
        startLocation: startLocation ?? this.startLocation,
        finishLocation: finishLocation ?? this.finishLocation,
        startName: startName ?? this.startName,
        finishName: finishName ?? this.finishName,
        preferredTransportTypeId:
            preferredTransportTypeId ?? this.preferredTransportTypeId,
      );
}
