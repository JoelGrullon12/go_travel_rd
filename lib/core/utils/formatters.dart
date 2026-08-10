import 'package:intl/intl.dart';

/// Formateo pensado para leerse de pie, en movimiento y de un vistazo.
///
/// La regla de fondo: **precisión falsa es ruido**. Un GPS con ±10 m de error
/// no puede decir "487 m"; decir "500 m" es más honesto y más rápido de leer.
abstract final class Fmt {
  static final DateFormat _hour = DateFormat('h:mm a', 'es');
  static final DateFormat _dayMonth = DateFormat('d MMM', 'es');

  /// "3:42 p. m."
  static String clock(DateTime time) => _hour.format(time).toLowerCase();

  /// "10 ago" — día + mes abreviado en es-DO, para listas e historial.
  static String dateDayMonth(DateTime date) => _dayMonth.format(date);

  /// "18 min", "1 h 05 min", "ahora".
  static String duration(Duration d) {
    final int totalMinutes = d.inSeconds <= 30 ? 0 : (d.inSeconds / 60).round();
    if (totalMinutes <= 0) return 'ahora';
    if (totalMinutes < 60) return '$totalMinutes min';
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;
    if (minutes == 0) return '$hours h';
    return '$hours h ${minutes.toString().padLeft(2, '0')} min';
  }

  /// Solo el número, para poder componerlo con una unidad más pequeña al lado.
  static String durationValue(Duration d) {
    final int totalMinutes = d.inSeconds <= 30 ? 0 : (d.inSeconds / 60).round();
    if (totalMinutes <= 0) return '0';
    if (totalMinutes < 60) return '$totalMinutes';
    return '${totalMinutes ~/ 60}:${(totalMinutes % 60).toString().padLeft(2, '0')}';
  }

  static String durationUnit(Duration d) =>
      d.inSeconds < 3600 ? 'min' : 'h';

  /// "1.4 km", "350 m", "80 m", "12 m".
  static String distance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    if (meters >= 100) return '${(meters / 50).round() * 50} m';
    if (meters >= 20) return '${(meters / 10).round() * 10} m';
    return '${meters.round()} m';
  }

  /// "RD$ 40".
  static String money(double dop) =>
      'RD\$ ${dop % 1 == 0 ? dop.toStringAsFixed(0) : dop.toStringAsFixed(2)}';

  /// "24 km/h".
  static String speed(double? mps) {
    if (mps == null || mps.isNaN || mps < 0) return '—';
    return '${(mps * 3.6).round()} km/h';
  }
}
