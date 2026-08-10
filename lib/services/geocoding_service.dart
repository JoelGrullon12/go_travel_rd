import 'package:geocoding/geocoding.dart';

/// Geocodificación inversa: convierte coordenadas en un nombre de lugar
/// legible (calle, localidad o establecimiento).
///
/// Usa el `geocoding` de Baseflow, que a su vez llama al geocoder gratuito
/// de la plataforma (Android Geocoder / CLGeocoder de iOS). Por eso nunca
/// lanza: ante un fallo de red o de límite de llamadas devuelve `null` y la
/// UI cae al fallback (coordenadas).
class GeocodingService {
  final Geocoding _geocoding = Geocoding();

  /// Nombre corto del lugar más cercano a `(lat, lng)`, o `null` si no se
  /// puede resolver. Compone calle/establecimiento + zona/localidad.
  Future<String?> placeNameFor(double lat, double lng) async {
    try {
      final List<Placemark> placemarks =
          await _geocoding.placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return null;

      final Placemark p = placemarks.first;
      final String? name = _clean(p.name) ?? _clean(p.street);
      final String? area = _clean(p.subLocality) ?? _clean(p.locality);

      final List<String> parts = <String>[?name, ?area];
      if (parts.isEmpty) return null;
      return parts.join(', ');
    } catch (_) {
      // IO_ERROR (límite de llamadas), red caída, etc.: no se rompe el flujo.
      return null;
    }
  }

  String? _clean(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;
    return trimmed;
  }
}
