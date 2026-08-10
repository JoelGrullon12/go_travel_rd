/// Puente entre el `transportTypeId` de una estación (Firestore) y el asset
/// de su icono en `assets/icons/`.
///
/// Devuelve `null` para tipos sin icono conocido; quien lo use cae al
/// marcador por defecto. Agregar aquí las rutas cuando se sumen más tipos
/// de transporte (concho, microbus…).
String? stationIconAsset(String transportTypeId) => switch (transportTypeId) {
      'metro' => 'assets/icons/metro_icon.png',
      'omsa' => 'assets/icons/omsa_icon.png',
      'teleferico' => 'assets/icons/cable_car_icon.png',
      _ => null,
    };
