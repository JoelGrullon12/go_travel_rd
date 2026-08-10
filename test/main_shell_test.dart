// Tests de humo de la barra de navegación flotante (Hito 5).

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/core/theme/app_theme.dart';
import 'package:go_travel_rd/screens/main_shell.dart';

void main() {
  // MainShell monta AuthService (Firebase) al arrancar, igual que HomeScreen en
  // widget_test.dart: con los mocks de firebase_core las llamadas responden sin
  // tocar la red.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  Widget harness() => ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const MainShellScreen(),
        ),
      );

  Future<void> pumpPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
  }

  testWidgets('La barra flotante muestra las tres pestañas y arranca en Inicio',
      (WidgetTester tester) async {
    await pumpPhone(tester);

    // La píldora flotante con sus tres ítems.
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Historial'), findsOneWidget);
    expect(find.text('Usuario'), findsOneWidget);

    // Pestaña por defecto: el contenido de HomeScreen es el visible.
    expect(find.text('GoTravel RD').hitTestable(), findsOneWidget);
    expect(find.text('TUS RUTAS FAVORITAS').hitTestable(), findsOneWidget);
  });

  testWidgets('Cambiar de pestaña muestra historial y perfil (sin sesión)',
      (WidgetTester tester) async {
    await pumpPhone(tester);

    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();
    expect(find.text('Historial de viajes').hitTestable(), findsOneWidget);
    expect(find.textContaining('Aún no has hecho viajes').hitTestable(),
        findsOneWidget);

    await tester.tap(find.text('Usuario'));
    await tester.pumpAndSettle();
    expect(find.text('Tu perfil te espera').hitTestable(), findsOneWidget);

    // Y volver a Inicio restaura el contenido principal.
    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    expect(find.text('GoTravel RD').hitTestable(), findsOneWidget);
  });

  testWidgets('No hay desbordes de layout en pantalla estrecha (375 pt)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1125, 2436);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
