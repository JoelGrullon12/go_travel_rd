import 'package:cloud_firestore/cloud_firestore.dart';

class FavoriteRoute {
  final String id;
  final DateTime? addedAt;

  const FavoriteRoute({
    required this.id,
    this.addedAt,
  });

  factory FavoriteRoute.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FavoriteRoute.fromMap(data, doc.id);
  }

  factory FavoriteRoute.fromMap(Map<String, dynamic> map, String id) =>
      FavoriteRoute(
        id: id,
        addedAt: (map['addedAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        if (addedAt != null) 'addedAt': Timestamp.fromDate(addedAt!),
      };
}
