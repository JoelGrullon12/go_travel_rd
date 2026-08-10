// Tests del modelo y serialización del historial de viajes (Hito 5).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/models/trip_history_entry.dart';

void main() {
  group('TripHistoryEntry', () {
    final DateTime date = DateTime(2026, 8, 10, 15, 42);

    test('toMap → fromMap redondea los campos (Timestamp incluido)', () {
      final TripHistoryEntry entry = TripHistoryEntry(
        id: 'trip-1',
        startName: 'Universidad APEC',
        finishName: 'Centro de los Héroes',
        date: date,
        cost: 40,
      );

      final Map<String, dynamic> map = entry.toMap();
      final TripHistoryEntry back = TripHistoryEntry.fromMap(map, 'trip-1');

      expect(map['startName'], 'Universidad APEC');
      expect(map['finishName'], 'Centro de los Héroes');
      expect(map['cost'], 40);
      expect(map['date'], isA<Timestamp>());
      expect(back.id, 'trip-1');
      expect(back.startName, entry.startName);
      expect(back.finishName, entry.finishName);
      expect(back.cost, entry.cost);
      expect(back.date, date);
    });

    test('fromMap tolera la ausencia de campos (entradas de otro formato)', () {
      final TripHistoryEntry entry = TripHistoryEntry.fromMap(
        <String, dynamic>{'startName': 'A', 'finishName': 'B'},
        'trip-x',
      );
      expect(entry.startName, 'A');
      expect(entry.finishName, 'B');
      expect(entry.cost, 0);
      // Sin fecha se cae a época 0 (se reconoce como "invalida" sin romper).
      expect(entry.date, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('fromMap acepta DateTime crudo además de Timestamp', () {
      final TripHistoryEntry entry = TripHistoryEntry.fromMap(
        <String, dynamic>{
          'startName': 'A',
          'finishName': 'B',
          'date': date,
          'cost': 25,
        },
        'trip-y',
      );
      expect(entry.date, date);
    });
  });
}
