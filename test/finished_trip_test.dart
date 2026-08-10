// Test del widget "Viaje terminado" en la pantalla principal (Hito 5): la
// tarjeta aparece cuando finishedTripProvider tiene un plan y "Cerrar" la limpia.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/application/data_providers.dart';
import 'package:go_travel_rd/core/theme/app_theme.dart';
import 'package:go_travel_rd/core/utils/formatters.dart';
import 'package:go_travel_rd/domain/geo/geo_point.dart';
import 'package:go_travel_rd/domain/models/transport_mode.dart';
import 'package:go_travel_rd/domain/models/trip_plan.dart';
import 'package:go_travel_rd/screens/home_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  TripPlan finishedPlan() => TripPlan(
        id: 'trip-terminado',
        originName: 'Villa Mella',
        destinationName: 'Los Mina',
        legs: <TripLeg>[
          TripLeg(
            id: 'leg-metro',
            mode: TransportMode.metro,
            lineName: 'Metro Línea 1',
            path: <GeoPoint>[
              const GeoPoint(18.549800, -69.899900),
              const GeoPoint(18.501000, -69.881700),
            ],
            fareDop: 40,
          ),
        ],
      );

  Future<void> pumpHome(WidgetTester tester, {TripPlan? finished}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          finishedTripProvider.overrideWith((ref) => finished),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin viaje terminado no hay tarjeta', (WidgetTester tester) async {
    await pumpHome(tester);
    expect(find.text('Viaje terminado'), findsNothing);
  });

  testWidgets('muestra inicio, fin, precio y distancia', (WidgetTester tester) async {
    final TripPlan plan = finishedPlan();
    await pumpHome(tester, finished: plan);

    expect(find.text('Viaje terminado'), findsOneWidget);
    expect(find.text('Villa Mella'), findsOneWidget);
    expect(find.text('Los Mina'), findsOneWidget);
    expect(find.text('RD\$ 40'), findsOneWidget);
    expect(find.text(Fmt.distance(plan.totalDistanceMeters)), findsOneWidget);
  });

  testWidgets('"Cerrar" limpia la tarjeta', (WidgetTester tester) async {
    await pumpHome(tester, finished: finishedPlan());

    expect(find.text('Viaje terminado'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Viaje terminado'), findsNothing);
  });
}
