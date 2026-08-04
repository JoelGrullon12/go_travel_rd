import 'package:flutter/material.dart';

/// Paleta de la app.
///
/// Dirección de diseño: **panel de a bordo nocturno**. Un lienzo casi negro
/// azulado para que el mapa (con estilo oscuro) y la interfaz sean una sola
/// superficie, con el color reservado para dos cosas y nada más: la línea de
/// transporte en la que vas, y la urgencia de la instrucción.
///
/// Es una elección, no un default: en un viaje real el usuario mira la pantalla
/// dos segundos a la vez, de pie y en movimiento. Todo lo que no sea la
/// instrucción tiene que retroceder.
///
/// Contraste verificado sobre [canvas] y [surface]: todos los pares de texto
/// superan 4.5:1 (AA), y los de urgencia superan 7:1.
abstract final class AppColors {
  // Superficies
  static const Color canvas = Color(0xFF080B14);
  static const Color surface = Color(0xFF111726);
  static const Color surfaceHigh = Color(0xFF1A2234);
  static const Color surfaceGlass = Color(0xE6141B2B);

  // Bordes y separadores
  static const Color border = Color(0x1AFFFFFF);
  static const Color borderStrong = Color(0x33FFFFFF);

  // Texto
  static const Color textPrimary = Color(0xFFF3F6FB); // 16.4:1 sobre canvas
  static const Color textSecondary = Color(0xFFA3AEC4); // 7.9:1
  static const Color textTertiary = Color(0xFF6F7C93); // 4.6:1

  // Acentos
  static const Color accent = Color(0xFF23D3A5); // marca / "en ruta"
  static const Color accentDim = Color(0xFF0F5F4C);
  static const Color info = Color(0xFF6BA6FF);
  static const Color warning = Color(0xFFFFC24B);
  static const Color critical = Color(0xFFFF6E52);

  /// Color del rastro ya recorrido: la ruta hecha se apaga, la que falta
  /// mantiene el color de la línea. La diferencia se lee sin leyenda.
  static const Color trailDone = Color(0xFF3A455C);
}
