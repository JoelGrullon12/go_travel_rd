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

  /// Tipo de transporte preferido del usuario (id de `transportTypes`), o
  /// `null` cuando no tiene ninguno marcado (se elige uno solo, radio en la UI).
  final String? favoriteTransportTypeId;
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
    this.favoriteTransportTypeId,
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
        'favoriteTransportTypeId': favoriteTransportTypeId,
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
        // Campo único nuevo. Fallback para docs legados que guardaban
        // `favoriteTransportTypeIds` (lista): se toma el primer elemento.
        favoriteTransportTypeId: _legacyFavoriteTransportType(map),
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

  /// Lee `favoriteTransportTypeId` (campo único) y cae al primer elemento de
  /// `favoriteTransportTypeIds` (lista) para los usuarios guardados antes de la
  /// migración. `null` cuando no hay preferencia.
  static String? _legacyFavoriteTransportType(Map<String, dynamic> map) {
    final String? single = map['favoriteTransportTypeId'] as String?;
    if (single != null && single.isNotEmpty) return single;
    final List<dynamic>? legacy = map['favoriteTransportTypeIds'] as List?;
    if (legacy == null || legacy.isEmpty) return null;
    final Object? first = legacy.first;
    return first is String && first.isNotEmpty ? first : null;
  }

  AppUser copyWith({
    String? uid,
    String? email,
    String? name,
    String? favoriteTransportTypeId,
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
        favoriteTransportTypeId:
            favoriteTransportTypeId ?? this.favoriteTransportTypeId,
        maxWalkDistance: maxWalkDistance ?? this.maxWalkDistance,
        routePreference: routePreference ?? this.routePreference,
        photoUrl: photoUrl ?? this.photoUrl,
        userRoutes: userRoutes ?? this.userRoutes,
        tripHistory: tripHistory ?? this.tripHistory,
      );
}
