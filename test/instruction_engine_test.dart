import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/domain/models/trip_instruction.dart';
import 'package:go_travel_rd/domain/models/trip_plan.dart';
import 'package:go_travel_rd/domain/tracking/instruction_engine.dart';
import 'package:go_travel_rd/domain/tracking/trip_geometry.dart';

import 'support/demo_trip_plans.dart';
import 'support/test_plans.dart';

void main() {
  group('InstructionEngine sobre un plan recto conocido', () {
    final TripGeometry geometry = TripGeometry.from(straightTestPlan());
    final InstructionEngine engine = InstructionEngine(geometry);

    TripInstruction at(double meters, {bool started = true, bool off = false}) =>
        engine.build(
          match: matchAt(geometry, meters, offRouteM: off ? 300 : 0),
          offRoute: off,
          hasStarted: started,
        );

    test('antes de moverse invita a empezar', () {
      expect(at(0, started: false).kind, InstructionKind.start);
    });

    test('caminando hacia la parada dice a dónde ir y qué se toma ahí', () {
      final TripInstruction i = at(60);
      expect(i.kind, InstructionKind.walkToBoarding);
      expect(i.detail, contains('Línea 1'));
      expect(i.urgency, InstructionUrgency.calm);
    });

    test('al llegar a la parada manda a abordar', () {
      final TripInstruction i = at(180); // a 20 m del fin de la caminata
      expect(i.kind, InstructionKind.board);
      expect(i.urgency, InstructionUrgency.headsUp);
      expect(i.detail, contains('dirección Este'));
    });

    test('en marcha informa cuántas paradas faltan, sin alarmar', () {
      final TripInstruction i = at(400);
      expect(i.kind, InstructionKind.riding);
      expect(i.urgency, InstructionUrgency.calm);
      expect(i.detail, contains('paradas'));
    });

    test('a menos de 900 m del destino del tramo, avisa que se prepare', () {
      final TripInstruction i = at(1000);
      expect(i.kind, InstructionKind.prepareToExit);
      expect(i.urgency, InstructionUrgency.headsUp);
      expect(i.detail, contains('Parada D'));
    });

    test('a menos de 250 m manda a bajarse, con urgencia máxima', () {
      final TripInstruction i = at(1600);
      expect(i.kind, InstructionKind.exitNow);
      expect(i.urgency, InstructionUrgency.critical);
    });

    test('el último tramo a pie apunta al destino', () {
      final TripInstruction i = at(1750);
      expect(i.kind, InstructionKind.walkToDestination);
      expect(i.title, contains('Destino'));
    });

    test('al llegar cierra el viaje', () {
      final TripInstruction i = at(geometry.totalMeters - 5);
      expect(i.kind, InstructionKind.arrived);
    });

    test('estar fuera de ruta tapa cualquier otra instrucción', () {
      final TripInstruction i = at(600, off: true);
      expect(i.kind, InstructionKind.offRoute);
      expect(i.urgency, InstructionUrgency.critical);
    });

    test('la llegada gana incluso sobre el fuera de ruta', () {
      // Si ya llegaste, decirte "te saliste de la ruta" es ruido inútil.
      final TripInstruction i = at(geometry.totalMeters - 5, off: true);
      expect(i.kind, InstructionKind.arrived);
    });

    test('la clave de la instrucción es estable mientras no cambie el paso', () {
      expect(at(400).key, at(430).key);
      expect(at(400).key, isNot(at(1000).key));
    });
  });

  group('InstructionEngine con transbordo real (L1 → L2)', () {
    final TripPlan plan = DemoTripPlans.villaMellaLosMina();
    final TripGeometry geometry = TripGeometry.from(plan);
    final InstructionEngine engine = InstructionEngine(geometry);

    test('anuncia el transbordo, no un final de viaje', () {
      // 100 m antes de terminar el tramo de la Línea 1.
      final double meters = geometry.legEndMeters[1] - 100;
      final TripInstruction i = engine.build(
        match: matchAt(geometry, meters),
        offRoute: false,
        hasStarted: true,
      );
      expect(i.kind, InstructionKind.transfer);
      expect(i.detail, contains('transbordo'));
      expect(i.detail, contains('Línea 2'));
    });
  });

  group('InstructionEngine con transporte sin paradas fijas (concho)', () {
    final TripGeometry geometry =
        TripGeometry.from(DemoTripPlans.nacoVillaConsuelo());
    final InstructionEngine engine = InstructionEngine(geometry);

    test('no habla de "paradas" cuando la ruta no las tiene', () {
      final double middle =
          (geometry.legStartMeters[1] + geometry.legEndMeters[1]) / 2;
      final TripInstruction i = engine.build(
        match: matchAt(geometry, middle),
        offRoute: false,
        hasStarted: true,
      );
      expect(i.detail, isNot(contains('paradas')));
      expect(i.detail, contains('Villa Consuelo'));
    });
  });
}
