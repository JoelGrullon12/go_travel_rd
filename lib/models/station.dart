import 'package:cloud_firestore/cloud_firestore.dart';

class Station {
  final String id;
  final String name;
  final GeoPoint location;
  final List<String> routeIds;
  final String? transportTypeId;

  const Station({
    required this.id,
    required this.name,
    required this.location,
    required this.routeIds,
    this.transportTypeId,
  });

  factory Station.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Station(
      id: doc.id,
      name: data['name'] as String? ?? '',
      location: data['location'] as GeoPoint? ?? const GeoPoint(0, 0),
      routeIds: List<String>.from(data['routeIds'] as List? ?? []),
      transportTypeId: data['transportTypeId'] as String?,
    );
  }
}
