import 'package:cloud_firestore/cloud_firestore.dart';

class TransportType {
  final String id;
  final String name;
  final String icon;

  const TransportType({
    required this.id,
    required this.name,
    required this.icon,
  });

  factory TransportType.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TransportType.fromMap(data, doc.id);
  }

  factory TransportType.fromMap(Map<String, dynamic> map, String id) =>
      TransportType(
        id: id,
        name: map['name'] as String? ?? '',
        icon: map['icon'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'icon': icon,
      };

  TransportType copyWith({
    String? name,
    String? icon,
  }) =>
      TransportType(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
      );
}
