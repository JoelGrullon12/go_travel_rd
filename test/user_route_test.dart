// Tests del modelo de rutas personalizadas del Hito 5: serialización
// `UserRoute` ↔ mapa de Firestore y su integración embebida en `AppUser`.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/models/user.dart';
import 'package:go_travel_rd/models/user_route.dart';

void main() {
  group('UserRoute', () {
    test('fromMap/toMap redondea todos los campos', () {
      final UserRoute route = UserRoute(
        id: 'route-1',
        name: 'Casa → Trabajo',
        startLocation: const GeoPoint(18.4816, -69.9151),
        finishLocation: const GeoPoint(18.5052, -69.8577),
        preferredTransportTypeId: 'metro',
      );

      final UserRoute restored = UserRoute.fromMap(route.toMap(), 'route-1');

      expect(restored.id, 'route-1');
      expect(restored.name, 'Casa → Trabajo');
      expect(restored.startLocation.latitude, closeTo(18.4816, 1e-9));
      expect(restored.startLocation.longitude, closeTo(-69.9151, 1e-9));
      expect(restored.finishLocation.latitude, closeTo(18.5052, 1e-9));
      expect(restored.finishLocation.longitude, closeTo(-69.8577, 1e-9));
      expect(restored.preferredTransportTypeId, 'metro');
    });

    test('sin datos devuelve valores por defecto', () {
      final UserRoute route =
          UserRoute.fromMap(const <String, dynamic>{}, 'route-2');

      expect(route.name, '');
      expect(route.preferredTransportTypeId, '');
      expect(route.startLocation.latitude, 0);
    });
  });

  group('AppUser', () {
    test('serializa userRoutes embebidas en el documento', () {
      final AppUser user = AppUser(
        uid: 'u1',
        email: 'ana@gotravel.do',
        name: 'Ana',
        userRoutes: <UserRoute>[
          UserRoute(
            id: '',
            name: 'Casa → Trabajo',
            startLocation: const GeoPoint(18.4816, -69.9151),
            finishLocation: const GeoPoint(18.5052, -69.8577),
            preferredTransportTypeId: 'metro',
          ),
        ],
      );

      final AppUser restored = AppUser.fromMap(user.toMap(), 'u1');

      expect(restored.userRoutes, hasLength(1));
      expect(restored.userRoutes.first.name, 'Casa → Trabajo');
      expect(
        restored.userRoutes.first.finishLocation.latitude,
        closeTo(18.5052, 1e-9),
      );
    });

    test('sin userRoutes devuelve lista vacía', () {
      final AppUser user =
          AppUser.fromMap(const <String, dynamic>{}, 'u2');

      expect(user.userRoutes, isEmpty);
      expect(user.maxWalkDistance, 1500.0);
    });
  });
}
