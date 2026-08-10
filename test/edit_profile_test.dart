// Tests de humo de la pantalla de edición de preferencias (Hito 5).
//
// `transportTypesProvider` se sobrescribe con datos de prueba: la pantalla no
// toca Firestore. El guardado real (AuthService.updateUserData) no se dispara
// en los tests — se valida solo el camino de error para no depender de mocks
// de Firestore.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/application/data_providers.dart';
import 'package:go_travel_rd/core/theme/app_theme.dart';
import 'package:go_travel_rd/models/transport_type.dart';
import 'package:go_travel_rd/models/user.dart';
import 'package:go_travel_rd/screens/edit_profile_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  const AppUser user = AppUser(
    uid: 'uid-1',
    email: 'ana@example.com',
    name: 'Ana',
    favoriteTransportTypeId: 'metro',
    maxWalkDistance: 1500,
    routePreference: 'speed',
  );

  const List<TransportType> transportTypes = <TransportType>[
    TransportType(id: 'metro', name: 'Metro', icon: 'assets/icons/metro_icon.png'),
    TransportType(id: 'omsa', name: 'OMSA', icon: 'assets/icons/omsa_icon.png'),
    TransportType(id: 'concho', name: 'Concho', icon: ''),
  ];

  Widget harness({AppUser? overriddenUser}) => ProviderScope(
        overrides: <Override>[
          transportTypesProvider.overrideWith((ref) async => transportTypes),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: EditProfileScreen(user: overriddenUser ?? user),
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

  testWidgets('Renderiza los tres campos de preferencia con los valores actuales',
      (WidgetTester tester) async {
    await pumpPhone(tester);

    expect(find.text('Tipo de transporte preferido'), findsOneWidget);
    expect(find.text('Preferencia de viaje'), findsOneWidget);
    expect(find.text('Distancia máxima a pie (metros)'), findsOneWidget);

    // Valores precargados: transporte favorito y distancia a pie.
    expect(find.text('Metro'), findsOneWidget);
    final TextFormField walkField = tester.widget<TextFormField>(
      find.byKey(const Key('max-walk-field')),
    );
    expect(walkField.controller?.text, '1500');
  });

  testWidgets('El dropdown de preferencia de viaje muestra las tres opciones',
      (WidgetTester tester) async {
    await pumpPhone(tester);

    await tester.tap(find.byKey(const Key('route-preference-field')));
    await tester.pumpAndSettle();

    expect(find.text('Más rápido'), findsWidgets);
    expect(find.text('Más barato'), findsOneWidget);
    expect(find.text('Más corto'), findsOneWidget);
  });

  testWidgets(
      'Un routePreference legado (p.ej. "rapidez") no crashea y cae a "Más rápido"',
      (WidgetTester tester) async {
    const AppUser legacyUser = AppUser(
      uid: 'uid-legacy',
      email: 'legacy@example.com',
      name: 'Legacy',
      routePreference: 'rapidez',
    );

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(harness(overriddenUser: legacyUser));
    await tester.pumpAndSettle();

    // Sin excepción por el valor desconocido y el dropdown muestra el default.
    expect(tester.takeException(), isNull);
    expect(find.text('Más rápido'), findsOneWidget);
  });

  testWidgets('Rechaza una distancia a pie fuera del rango 100–5000',
      (WidgetTester tester) async {
    await pumpPhone(tester);

    await tester.enterText(
        find.byKey(const Key('max-walk-field')), '6000');
    await tester.tap(find.byKey(const Key('save-preferences-button')));
    await tester.pumpAndSettle();
    expect(find.text('El máximo es 5000 m'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('max-walk-field')), '50');
    await tester.tap(find.byKey(const Key('save-preferences-button')));
    await tester.pumpAndSettle();
    expect(find.text('El mínimo es 100 m'), findsOneWidget);
  });

  testWidgets('El radio de transporte permite elegir un solo tipo a la vez',
      (WidgetTester tester) async {
    await pumpPhone(tester);

    await tester.tap(find.byKey(const Key('transport-types-field')));
    await tester.pumpAndSettle();

    expect(find.text('Tipo de transporte preferido'), findsNWidgets(2));
    final Finder dialog = find.byType(AlertDialog);

    // Metro viene marcado (precargado); se marca OMSA y queda solo OMSA.
    await tester.tap(
        find.descendant(of: dialog, matching: find.text('OMSA')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    // La etiqueta del campo refleja la nueva selección (una sola).
    expect(find.text('OMSA'), findsOneWidget);
    expect(find.text('Metro'), findsNothing);
  });

  testWidgets('El radio permite limpiar la preferencia con "Ninguno"',
      (WidgetTester tester) async {
    await pumpPhone(tester);

    await tester.tap(find.byKey(const Key('transport-types-field')));
    await tester.pumpAndSettle();

    final Finder dialog = find.byType(AlertDialog);
    await tester.tap(find.descendant(of: dialog, matching: find.text('Ninguno')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(find.text('Ninguno'), findsOneWidget);
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
