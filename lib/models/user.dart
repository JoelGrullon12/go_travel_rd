import 'trip_history_entry.dart';
import 'user_route.dart';

class AppUser {
  /// Valores válidos de `routePreference` (ver `lib/models/models.yaml`).
  static const List<String> routePreferenceValues = <String>[
    'speed',
    'price',
    'distance',
  ];

  /// Normaliza una preferencia de ruta leída de la BD: si no es uno de los
  /// valores conocidos ([routePreferenceValues]) —p.ej. legados como
  /// `'rapidez'`— devuelve el default `'speed'`. Así ningún valor ajeno llega
  /// al resto de la app (la UI nunca debe recibir una preferencia desconocida).
  static String normalizeRoutePreference(String? value) {
    if (routePreferenceValues.contains(value)) return value!;
    return 'speed';
  }

  final String uid;
  final String email;
  final String name;
  final List<String> favoriteTransportTypeIds;
  final double maxWalkDistance;
  final String routePreference;
  final String? photoUrl;
  final List<UserRoute> userRoutes;

  /// Viajes iniciados por el usuario, en orden cronológico (nuevo primero).
  /// Se guarda en `users/{uid}.tripHistory` (array de maps).
  final List<TripHistoryEntry> tripHistory;

  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
    this.favoriteTransportTypeIds = const [],
    this.maxWalkDistance = 1500.0,
    this.routePreference = 'speed',
    this.photoUrl,
    this.userRoutes = const [],
    this.tripHistory = const [],
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'name': name,
        'favoriteTransportTypeIds': favoriteTransportTypeIds,
        'maxWalkDistance': maxWalkDistance,
        'routePreference': routePreference,
        'photoUrl': photoUrl,
        'userRoutes': userRoutes.map((r) => r.toMap()).toList(),
        'tripHistory': tripHistory.map((e) => e.toMap()).toList(),
      };

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) => AppUser(
        uid: uid,
        email: map['email'] as String? ?? '',
        name: map['name'] as String? ?? '',
        favoriteTransportTypeIds:
            List<String>.from(map['favoriteTransportTypeIds'] as List? ?? []),
        maxWalkDistance: (map['maxWalkDistance'] as num?)?.toDouble() ?? 1500.0,
        routePreference: normalizeRoutePreference(map['routePreference'] as String?),
        photoUrl: map['photoUrl'] as String?,
        userRoutes: (map['userRoutes'] as List? ?? [])
            .whereType<Map>()
            .map((e) => UserRoute.fromMap(e.cast<String, dynamic>(), ''))
            .toList(),
        tripHistory: (map['tripHistory'] as List? ?? [])
            .whereType<Map>()
            .map((e) => TripHistoryEntry.fromMap(e.cast<String, dynamic>(), ''))
            .toList(),
      );

  AppUser copyWith({
    String? uid,
    String? email,
    String? name,
    List<String>? favoriteTransportTypeIds,
    double? maxWalkDistance,
    String? routePreference,
    String? photoUrl,
    List<UserRoute>? userRoutes,
    List<TripHistoryEntry>? tripHistory,
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
        userRoutes: userRoutes ?? this.userRoutes,
        tripHistory: tripHistory ?? this.tripHistory,
      );
}
