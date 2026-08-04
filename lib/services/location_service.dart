import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  /// Pide permiso de ubicación si todavía no se ha concedido.
  ///
  /// Siempre consulta el estado actual y llama a `.request()` cuando el
  /// permiso está denegado, así el diálogo del sistema aparece aunque el
  /// GPS esté apagado. Devuelve `true` solo si se concede acceso.
  ///
  /// Si el permiso fue denegado de forma permanente, el usuario tendrá
  /// que habilitarlo desde la configuración del sistema.
  Future<bool> requestLocationPermission() async {
    var status = await Permission.locationWhenInUse.status;
    if (status.isDenied) {
      status = await Permission.locationWhenInUse.request();
    }
    if (status.isPermanentlyDenied) return false;

    return status.isGranted || status.isLimited || status.isProvisional;
  }

  /// Devuelve `true` si el GPS del dispositivo está activo.
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  /// Obtiene una posición puntual del usuario.
  ///
  /// Pide el permiso si hace falta. Devuelve `null` si el permiso fue
  /// denegado, el GPS está apagado o la lectura de posición falla.
  Future<Position?> getCurrentPosition() async {
    if (!await requestLocationPermission()) return null;
    if (!await isLocationServiceEnabled()) return null;

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } on Exception {
      return null;
    }
  }

  /// Abre los ajustes de ubicación del sistema (para activar el GPS).
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Stream continuo de posición para seguimiento en tiempo real.
  ///
  /// Emite un nuevo [Position] cada vez que el dispositivo se mueve la
  /// [LocationSettings.distanceFilter] mínima (5 metros por defecto).
  /// Se cancela con la suscripción (ver `StreamSubscription.cancel`).
  Stream<Position> getPositionStream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      );
}
