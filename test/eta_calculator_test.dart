import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/domain/tracking/eta_calculator.dart';
import 'package:go_travel_rd/domain/tracking/trip_geometry.dart';

import 'support/test_plans.dart';

void main() {
  final TripGeometry geometry = TripGeometry.from(straightTestPlan());
  final EtaCalculator calculator = EtaCalculator(geometry);
  final DateTime now = DateTime(2026, 7, 27, 15, 0);

  test('el tiempo restante baja conforme se avanza', () {
    final EtaEstimate start =
        calculator.estimate(match: matchAt(geometry, 0), now: now);
    final EtaEstimate middle =
        calculator.estimate(match: matchAt(geometry, 900), now: now);
    final EtaEstimate end = calculator.estimate(
      match: matchAt(geometry, geometry.totalMeters),
      now: now,
    );

    expect(start.remaining, greaterThan(middle.remaining));
    expect(middle.remaining, greaterThan(end.remaining));
    expect(end.remaining.inSeconds, lessThan(5));
  });

  test('calcula por tramo, no con una velocidad promedio única', () {
    // 200 m a pie (4.8 km/h) + 1489 m de metro (32 km/h) + 200 m a pie.
    // A pie: 400 m / 1.333 m/s ≈ 300 s. Metro: 1489 / 8.89 ≈ 168 s.
    // Un promedio ingenuo daría un número muy distinto.
    final EtaEstimate eta =
        calculator.estimate(match: matchAt(geometry, 0), now: now);
    expect(eta.remaining.inSeconds, closeTo(468, 60));
  });

  test('la hora de llegada es coherente con el tiempo restante', () {
    final EtaEstimate eta =
        calculator.estimate(match: matchAt(geometry, 500), now: now);
    expect(
      eta.arrivalAt.difference(now).inSeconds,
      eta.remaining.inSeconds,
    );
  });

  test('toEndOfLeg mide solo lo que falta del tramo actual', () {
    final EtaEstimate eta =
        calculator.estimate(match: matchAt(geometry, 900), now: now);
    expect(eta.toEndOfLeg, lessThan(eta.remaining));
    expect(eta.toEndOfLeg.inSeconds, greaterThan(0));
  });

  test('una velocidad observada más lenta alarga el ETA', () {
    final EtaEstimate normal =
        calculator.estimate(match: matchAt(geometry, 600), now: now);
    final EtaEstimate slow = calculator.estimate(
      match: matchAt(geometry, 600),
      now: now,
      observedSpeedMps: 3, // el metro va lento hoy
    );
    expect(slow.remaining, greaterThan(normal.remaining));
  });

  test('estar parado no vuelve infinito el ETA', () {
    // Un semáforo o una parada larga dejan la velocidad instantánea casi en 0.
    // El ETA tiene que seguir siendo un número usable.
    final EtaEstimate stopped = calculator.estimate(
      match: matchAt(geometry, 600),
      now: now,
      observedSpeedMps: 0.05,
    );
    expect(stopped.remaining.inMinutes, lessThan(60));
  });

  test('una velocidad observada absurda no distorsiona el resultado', () {
    // Un pico de GPS puede reportar 90 m/s. La banda de confianza lo recorta.
    final EtaEstimate crazy = calculator.estimate(
      match: matchAt(geometry, 600),
      now: now,
      observedSpeedMps: 90,
    );
    expect(crazy.remaining.inSeconds, greaterThan(30));
  });

  test('remainingMeters coincide con lo que falta de recorrido', () {
    final EtaEstimate eta =
        calculator.estimate(match: matchAt(geometry, 700), now: now);
    expect(eta.remainingMeters, closeTo(geometry.totalMeters - 700, 1));
  });
}
