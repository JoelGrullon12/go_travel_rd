import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/data/fixtures/demo_trip_plans.dart';
import 'package:go_travel_rd/domain/geo/geo_math.dart';
import 'package:go_travel_rd/domain/geo/geo_point.dart';
import 'package:go_travel_rd/domain/models/location_sample.dart';
import 'package:go_travel_rd/domain/models/trip_instruction.dart';
import 'package:go_travel_rd/domain/models/trip_progress.dart';
import 'package:go_travel_rd/domain/tracking/trip_tracker.dart';

import 'support/test_plans.dart';

/// Recorre el plan completo alimentando al tracker como lo haría el GPS y
/// devuelve todos los estados intermedios.
List<TripProgress> runFullTrip(
  TripTracker tracker, {
  double stepMeters = 40,
  double lateralOffset = 0,
}) {
  final List<TripProgress> history = <TripProgress>[];
  DateTime clock = DateTime(2026, 7, 27, 8, 0);

  // Se recorre a pasos fijos y **siempre** se termina exactamente en el final:
  // si el último paso se quedara a 50 m del destino, el viaje no se daría por
  // llegado y la prueba fallaría por culpa del muestreo, no del código.
  final double total = tracker.geometry.totalMeters;
  double m = 0;
  while (true) {
    GeoPoint position = tracker.geometry.pointAt(m);
    if (lateralOffset != 0) {
      position = offsetMeters(
        position,
        lateralOffset,
        tracker.geometry.headingAt(m) + 90,
      );
    }
    history.add(
      tracker.onSample(
        LocationSample(position: position, timestamp: clock, accuracyMeters: 8),
      ),
    );
    clock = clock.add(const Duration(seconds: 5));
    if (m >= total) break;
    m = (m + stepMeters).clamp(0.0, total);
  }
  return history;
}

void main() {
  group('Recorrido completo de un plan recto', () {
    late List<TripProgress> history;

    setUp(() {
      history = runFullTrip(TripTracker(straightTestPlan()));
    });

    test('el avance nunca retrocede', () {
      for (int i = 1; i < history.length; i++) {
        expect(
          history[i].traveledMeters,
          greaterThanOrEqualTo(history[i - 1].traveledMeters - 1),
        );
      }
    });

    test('la fracción va de 0 a 1', () {
      expect(history.first.fraction, closeTo(0, 0.02));
      expect(history.last.fraction, closeTo(1, 0.03));
    });

    test('el viaje termina en estado "llegaste"', () {
      expect(history.last.hasArrived, isTrue);
      expect(history.last.instruction.kind, InstructionKind.arrived);
    });

    test('las instrucciones aparecen en el orden lógico del viaje', () {
      final List<InstructionKind> sequence = <InstructionKind>[];
      for (final TripProgress p in history) {
        if (sequence.isEmpty || sequence.last != p.instruction.kind) {
          sequence.add(p.instruction.kind);
        }
      }
      expect(
        sequence,
        containsAllInOrder(<InstructionKind>[
          InstructionKind.walkToBoarding,
          InstructionKind.board,
          InstructionKind.riding,
          InstructionKind.prepareToExit,
          InstructionKind.exitNow,
          InstructionKind.walkToDestination,
          InstructionKind.arrived,
        ]),
      );
    });

    test('cada instrucción se marca como nueva una sola vez', () {
      final Map<String, int> newFlags = <String, int>{};
      for (final TripProgress p in history) {
        if (p.isNewInstruction) {
          newFlags.update(
            p.instruction.key,
            (int count) => count + 1,
            ifAbsent: () => 1,
          );
        }
      }
      // Si una clave se marcara como nueva dos veces, el teléfono vibraría de
      // más y el lector de pantalla repetiría el aviso.
      for (final MapEntry<String, int> entry in newFlags.entries) {
        expect(entry.value, 1, reason: 'La instrucción ${entry.key} se repitió');
      }
    });

    test('nunca se reporta fuera de ruta yendo por la ruta', () {
      expect(history.any((TripProgress p) => p.offRoute), isFalse);
    });

    test('el ETA decrece de forma monótona salvo ruido menor', () {
      for (int i = 1; i < history.length; i++) {
        expect(
          history[i].eta.remaining.inSeconds,
          lessThanOrEqualTo(history[i - 1].eta.remaining.inSeconds + 30),
        );
      }
    });
  });

  group('Detección de fuera de ruta', () {
    late TripTracker tracker;

    setUp(() => tracker = TripTracker(straightTestPlan()));

    TripProgress feed(double meters, {double lateral = 0, double accuracy = 8}) {
      GeoPoint position = tracker.geometry.pointAt(meters);
      if (lateral != 0) {
        position = offsetMeters(
          position,
          lateral,
          tracker.geometry.headingAt(meters) + 90,
        );
      }
      return tracker.onSample(
        LocationSample(
          position: position,
          timestamp: DateTime(2026, 7, 27, 8, 0).add(
            Duration(seconds: (meters / 10).round()),
          ),
          accuracyMeters: accuracy,
        ),
      );
    }

    test('una sola lectura mala no dispara la alerta', () {
      feed(400);
      final TripProgress p = feed(440, lateral: 300);
      expect(p.offRoute, isFalse,
          reason: 'Un rebote de GPS no puede disparar la alerta');
    });

    test('tres lecturas seguidas fuera del corredor sí la disparan', () {
      feed(400);
      feed(440, lateral: 300);
      feed(480, lateral: 300);
      final TripProgress p = feed(520, lateral: 300);
      expect(p.offRoute, isTrue);
      expect(p.instruction.kind, InstructionKind.offRoute);
    });

    test('volver a la ruta apaga la alerta', () {
      feed(400);
      feed(440, lateral: 300);
      feed(480, lateral: 300);
      feed(520, lateral: 300);
      feed(560);
      final TripProgress recovered = feed(600);
      expect(recovered.offRoute, isFalse);
    });

    test('con GPS impreciso el umbral se relaja', () {
      // Con ±120 m de precisión, una desviación de 100 m no prueba nada.
      feed(400, accuracy: 120);
      feed(440, lateral: 100, accuracy: 120);
      feed(480, lateral: 100, accuracy: 120);
      final TripProgress p = feed(520, lateral: 100, accuracy: 120);
      expect(p.offRoute, isFalse);
    });

    test('fuera de ruta conserva la posición cruda, no la pegada', () {
      feed(400);
      feed(440, lateral: 300);
      feed(480, lateral: 300);
      final TripProgress p = feed(520, lateral: 300);
      expect(
        distanceMeters(p.rawPosition, p.match.snapped),
        greaterThan(200),
      );
    });
  });

  group('Recorrido completo del plan real con transbordo', () {
    test('llega al final y pasa por el transbordo', () {
      final TripTracker tracker = TripTracker(DemoTripPlans.villaMellaLosMina());
      final List<TripProgress> history = runFullTrip(tracker, stepMeters: 60);

      expect(history.last.hasArrived, isTrue);
      expect(
        history.any(
          (TripProgress p) => p.instruction.kind == InstructionKind.transfer,
        ),
        isTrue,
        reason: 'El transbordo L1 → L2 debe anunciarse',
      );
      expect(history.any((TripProgress p) => p.offRoute), isFalse);
    });

    test('reset deja el tracker como recién creado', () {
      final TripTracker tracker = TripTracker(DemoTripPlans.villaMellaLosMina());
      runFullTrip(tracker, stepMeters: 200);
      expect(tracker.last, isNotNull);

      tracker.reset();
      expect(tracker.last, isNull);

      final TripProgress first = tracker.onSample(
        LocationSample(
          position: tracker.geometry.pointAt(0),
          timestamp: DateTime(2026, 7, 27, 9, 0),
        ),
      );
      expect(first.traveledMeters, closeTo(0, 5));
      expect(first.instruction.kind, InstructionKind.start);
    });
  });
}
