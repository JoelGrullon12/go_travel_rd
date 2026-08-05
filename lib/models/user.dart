class AppUser {
  final String uid;
  final String email;
  final String name;
  final List<String> favoriteTransportTypeIds;
  final double maxWalkDistance;
  final String routePreference;
  final String? photoUrl;

  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
    this.favoriteTransportTypeIds = const [],
    this.maxWalkDistance = 1500.0,
    this.routePreference = 'speed',
    this.photoUrl,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'name': name,
        'favoriteTransportTypeIds': favoriteTransportTypeIds,
        'maxWalkDistance': maxWalkDistance,
        'routePreference': routePreference,
        'photoUrl': photoUrl,
      };

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) => AppUser(
        uid: uid,
        email: map['email'] as String? ?? '',
        name: map['name'] as String? ?? '',
        favoriteTransportTypeIds:
            List<String>.from(map['favoriteTransportTypeIds'] as List? ?? []),
        maxWalkDistance: (map['maxWalkDistance'] as num?)?.toDouble() ?? 1500.0,
        routePreference: map['routePreference'] as String? ?? 'speed',
        photoUrl: map['photoUrl'] as String?,
      );

  AppUser copyWith({
    String? uid,
    String? email,
    String? name,
    List<String>? favoriteTransportTypeIds,
    double? maxWalkDistance,
    String? routePreference,
    String? photoUrl,
  }) =>
      AppUser(
        uid: uid ?? this.uid,
        email: email ?? this.email,
        name: name ?? this.name,
        favoriteTransportTypeIds:
            favoriteTransportTypeIds ?? this.favoriteTransportTypeIds,
        maxWalkDistance: maxWalkDistance ?? this.maxWalkDistance,
        routePreference: routePreference ?? this.routePreference,
        photoUrl: photoUrl ?? this.photoUrl,
      );
}
