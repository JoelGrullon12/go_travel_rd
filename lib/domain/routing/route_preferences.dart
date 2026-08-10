/// Preferencias de viaje del usuario que el motor A→B usa para sesgar la
/// búsqueda (Hito 5). Lógica pura, sin Flutter: se prueba con `flutter test`.
///
/// Valores por defecto (`speed`, sin tipo favorito) reproducen exactamente el
/// comportamiento del motor previo a las preferencias: minimizar tiempo.
class RoutePreferences {
  const RoutePreferences({
    this.routePreference = 'speed',
    this.favoriteTransportTypeId,
  });

  /// "speed" (más rápido) | "price" (más barato) | "distance" (más corto).
  /// Coincide con [AppUser.routePreferenceValues].
  final String routePreference;

  /// Id de `transportTypes` preferido (metro/omsa/teleferico…), o `null`
  /// cuando el usuario no marcó ninguno.
  final String? favoriteTransportTypeId;

  bool get hasFavoriteType => favoriteTransportTypeId != null;

  /// `true` si `mode` es el tipo de transporte favorito del usuario.
  bool prefersMode(String modeCode) =>
      hasFavoriteType && favoriteTransportTypeId == modeCode;
}
