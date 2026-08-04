/// Punto geográfico del dominio.
///
/// Deliberadamente NO usamos `LatLng` de `google_maps_flutter` aquí: todo el
/// motor de seguimiento es Dart puro, sin dependencias de Flutter ni del
/// proveedor de mapas. Eso permite (a) probarlo con `flutter test` sin
/// emulador y (b) cambiar Google Maps por otro mapa sin tocar la lógica.
/// La conversión a `LatLng` vive en la capa de UI (`lib/features/.../map`).
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() =>
      'GeoPoint(${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})';
}
