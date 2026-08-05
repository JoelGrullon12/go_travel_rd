// Tests de humo de la pantalla de inicio (launcher estilo Uber × Google Maps).
//
// La pantalla de viaje activo (LiveTripScreen) no se prueba con widget tests:
// incrusta una vista nativa de Google Maps, que no existe en el entorno de
// pruebas. Su lógica —que es lo que de verdad puede romperse— está cubierta
// por los tests de dominio (trip_tracker_test.dart y compañía), que corren
// sin dispositivo.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/core/theme/app_theme.dart';
import 'package:go_travel_rd/screens/home_screen.dart';

void main() {
  // HomeScreen monta un AuthService (Firebase) al arrancar. Con los mocks de
  // firebase_core y la app inicializada con opciones de prueba, Firebase.app()
  // y FirebaseAuth.instance responden sin tocar la red.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  Widget harness() => ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const HomeScreen(),
        ),
      );

  /// Lienzo alto tipo teléfono: con el tamaño por defecto (800×600) la lista
  /// no llega a construir las últimas tarjetas y los buscadores no las ven.
  Future<void> pumpPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
  }

  testWidgets('Sin sesión la pantalla invita a registrarse para guardar rutas',
      (WidgetTester tester) async {
    await pumpPhone(tester);

    expect(find.text('GoTravel RD'), findsOneWidget);
    expect(find.text('Regístrate para guardar rutas personalizadas'),
        findsOneWidget);
    expect(find.text('Registrarse'), findsOneWidget);
    // Sin sesión no se listan rutas demo ni favoritas.
    expect(find.text('DEMO'), findsNothing);
  });

  testWidgets('El botón "Registrarse" abre la pantalla de iniciar sesión',
      (WidgetTester tester) async {
    await pumpPhone(tester);

    await tester.tap(find.text('Registrarse'));
    await tester.pumpAndSettle();

    expect(find.text('Iniciar Sesión'), findsWidgets);
  });

  testWidgets('No hay desbordes de layout en pantalla estrecha (375 pt)',
      (WidgetTester tester) async {
    // 375 pt es el ancho del iPhone SE/13 mini: el suelo real de la app.
    tester.view.physicalSize = const Size(1125, 2436);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
