import 'package:cloud_firestore/cloud_firestore.dart';

/// Entrada del historial de viajes del usuario (Hito 5).
///
/// Se guarda embebida en `users/{uid}.tripHistory` (array de maps) cuando el
/// usuario **inicia** un viaje desde el mapa — calcular una ruta sin comenzarla
/// no genera una entrada. Ver `lib/models/models.yaml`.
class TripHistoryEntry {
  final String id;

  /// Nombres geocodificados (calle/establecimiento) de origen y destino,
  /// igual que en [UserRoute], para mostrar el historial sin re-consultar al
  /// geocoder.
  final String startName;
  final String finishName;

  /// Fecha en la que se inició el viaje.
  final DateTime date;

  /// Costo total del viaje en pesos dominicanos.
  final double cost;

  const TripHistoryEntry({
    required this.id,
    required this.startName,
    required this.finishName,
    required this.date,
    required this.cost,
  });

  factory TripHistoryEntry.fromMap(Map<String, dynamic> map, String id) {
    final Object? rawDate = map['date'];
    DateTime? parsedDate;
    if (rawDate is Timestamp) {
      parsedDate = rawDate.toDate();
    } else if (rawDate is DateTime) {
      parsedDate = rawDate;
    }
    return TripHistoryEntry(
      id: id,
      startName: map['startName'] as String? ?? '',
      finishName: map['finishName'] as String? ?? '',
      date: parsedDate ?? DateTime.fromMillisecondsSinceEpoch(0),
      cost: (map['cost'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'startName': startName,
        'finishName': finishName,
        'date': Timestamp.fromDate(date),
        'cost': cost,
      };

  TripHistoryEntry copyWith({
    String? startName,
    String? finishName,
    DateTime? date,
    double? cost,
  }) =>
      TripHistoryEntry(
        id: id,
        startName: startName ?? this.startName,
        finishName: finishName ?? this.finishName,
        date: date ?? this.date,
        cost: cost ?? this.cost,
      );
}
