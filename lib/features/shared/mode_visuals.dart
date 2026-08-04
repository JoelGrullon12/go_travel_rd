import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/geo/geo_point.dart';
import '../../domain/models/trip_instruction.dart';
import '../../domain/models/transport_mode.dart';

/// Puente entre el dominio (Dart puro) y el mapa de Google.
///
/// Existe para que `GeoPoint` no tenga que conocer `LatLng`: si mañana el
/// equipo cambia de proveedor de mapas, se reescribe este archivo y nada más.
extension GeoPointMapX on GeoPoint {
  LatLng get toLatLng => LatLng(lat, lng);
}

extension LatLngDomainX on LatLng {
  GeoPoint get toGeoPoint => GeoPoint(latitude, longitude);
}

/// Ícono por modo de transporte.
///
/// Íconos vectoriales, nunca emojis: los emojis cambian de forma según el
/// sistema operativo y no responden al color del tema.
IconData iconForMode(TransportMode mode) => switch (mode) {
      TransportMode.walk => Icons.directions_walk_rounded,
      TransportMode.metro => Icons.subway_rounded,
      TransportMode.teleferico => Icons.airline_seat_recline_normal_rounded,
      TransportMode.corredor => Icons.directions_bus_filled_rounded,
      TransportMode.omsa => Icons.directions_bus_rounded,
      TransportMode.concho => Icons.local_taxi_rounded,
      TransportMode.motoconcho => Icons.two_wheeler_rounded,
    };

/// Ícono por tipo de instrucción. Refuerza el mensaje sin depender del color
/// (importante para daltonismo: el color nunca es el único canal).
IconData iconForInstruction(InstructionKind kind) => switch (kind) {
      InstructionKind.start => Icons.play_arrow_rounded,
      InstructionKind.walkToBoarding => Icons.directions_walk_rounded,
      InstructionKind.board => Icons.login_rounded,
      InstructionKind.riding => Icons.trending_flat_rounded,
      InstructionKind.prepareToExit => Icons.notifications_active_rounded,
      InstructionKind.exitNow => Icons.logout_rounded,
      InstructionKind.transfer => Icons.swap_horiz_rounded,
      InstructionKind.walkToDestination => Icons.flag_rounded,
      InstructionKind.arrived => Icons.check_circle_rounded,
      InstructionKind.offRoute => Icons.warning_amber_rounded,
    };

/// Color que corresponde a la urgencia de una instrucción.
Color colorForUrgency(InstructionUrgency urgency) => switch (urgency) {
      InstructionUrgency.calm => AppColors.info,
      InstructionUrgency.headsUp => AppColors.warning,
      InstructionUrgency.critical => AppColors.critical,
    };
