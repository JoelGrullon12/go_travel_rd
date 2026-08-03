import 'package:cloud_firestore/cloud_firestore.dart';

class FavoriteCustomRoute {
  final String id;
  final String name;
  final GeoPoint startLocation;
  final GeoPoint finishLocation;
  final String preferredTransportTypeId;

  const FavoriteCustomRoute({
    required this.id,
    required this.name,
    required this.startLocation,
    required this.finishLocation,
    required this.preferredTransportTypeId,
  });

  factory FavoriteCustomRoute.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FavoriteCustomRoute.fromMap(data, doc.id);
  }

  factory FavoriteCustomRoute.fromMap(Map<String, dynamic> map, String id) =>
      FavoriteCustomRoute(
        id: id,
        name: map['name'] as String? ?? '',
        startLocation:
            map['startLocation'] as GeoPoint? ?? const GeoPoint(0, 0),
        finishLocation:
            map['finishLocation'] as GeoPoint? ?? const GeoPoint(0, 0),
        preferredTransportTypeId:
            map['preferredTransportTypeId'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'startLocation': startLocation,
        'finishLocation': finishLocation,
        'preferredTransportTypeId': preferredTransportTypeId,
      };

  FavoriteCustomRoute copyWith({
    String? name,
    GeoPoint? startLocation,
    GeoPoint? finishLocation,
    String? preferredTransportTypeId,
  }) =>
      FavoriteCustomRoute(
        id: id,
        name: name ?? this.name,
        startLocation: startLocation ?? this.startLocation,
        finishLocation: finishLocation ?? this.finishLocation,
        preferredTransportTypeId:
            preferredTransportTypeId ?? this.preferredTransportTypeId,
      );
}
