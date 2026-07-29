class AppUser {
  final String uid;
  final String email;
  final String name;
  final String? favoriteTransportTypeId;
  final double maxWalkDistance;
  final String routePreference;
  final String? photoUrl;

  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
    this.favoriteTransportTypeId,
    this.maxWalkDistance = 500.0,
    this.routePreference = 'rapidez',
    this.photoUrl,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'name': name,
        'favoriteTransportTypeId': favoriteTransportTypeId,
        'maxWalkDistance': maxWalkDistance,
        'routePreference': routePreference,
        'photoUrl': photoUrl,
      };

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) => AppUser(
        uid: uid,
        email: map['email'] as String? ?? '',
        name: map['name'] as String? ?? '',
        favoriteTransportTypeId: map['favoriteTransportTypeId'] as String?,
        maxWalkDistance: (map['maxWalkDistance'] as num?)?.toDouble() ?? 500.0,
        routePreference: map['routePreference'] as String? ?? 'rapidez',
        photoUrl: map['photoUrl'] as String?,
      );

  AppUser copyWith({
    String? uid,
    String? email,
    String? name,
    String? favoriteTransportTypeId,
    double? maxWalkDistance,
    String? routePreference,
    String? photoUrl,
  }) =>
      AppUser(
        uid: uid ?? this.uid,
        email: email ?? this.email,
        name: name ?? this.name,
        favoriteTransportTypeId:
            favoriteTransportTypeId ?? this.favoriteTransportTypeId,
        maxWalkDistance: maxWalkDistance ?? this.maxWalkDistance,
        routePreference: routePreference ?? this.routePreference,
        photoUrl: photoUrl ?? this.photoUrl,
      );
}
