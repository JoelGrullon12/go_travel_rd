// Tests de normalización de `routePreference` del modelo `AppUser` (Hito 5).
//
// La BD puede contener valores legados/desconocidos (p.ej. `'rapidez'`). El
// modelo los normaliza a `'speed'` para que ningún valor ajeno llegue a la UI
// (el dropdown de `EditProfileScreen` exige que el valor coincida con una
// opción, si no, crashea).

import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/models/user.dart';

void main() {
  group('AppUser.normalizeRoutePreference', () {
    test('devuelve los valores conocidos tal cual', () {
      expect(AppUser.normalizeRoutePreference('speed'), 'speed');
      expect(AppUser.normalizeRoutePreference('price'), 'price');
      expect(AppUser.normalizeRoutePreference('distance'), 'distance');
    });

    test('los valores legados o vacíos caen al default speed', () {
      expect(AppUser.normalizeRoutePreference('rapidez'), 'speed');
      expect(AppUser.normalizeRoutePreference(''), 'speed');
      expect(AppUser.normalizeRoutePreference(null), 'speed');
      expect(AppUser.normalizeRoutePreference('cualquier_cosa'), 'speed');
    });
  });

  group('AppUser.fromMap', () {
    test('normaliza un routePreference legado al leer el documento', () {
      final AppUser user = AppUser.fromMap(
        <String, dynamic>{'routePreference': 'rapidez'},
        'u1',
      );

      expect(user.routePreference, 'speed');
    });

    test('sin routePreference usa el default speed', () {
      final AppUser user = AppUser.fromMap(const <String, dynamic>{}, 'u2');

      expect(user.routePreference, 'speed');
    });

    test('un valor válido se conserva', () {
      final AppUser user = AppUser.fromMap(
        <String, dynamic>{'routePreference': 'price'},
        'u3',
      );

      expect(user.routePreference, 'price');
    });
  });

  group('AppUser.favoriteTransportTypeId', () {
    test('lee el campo único', () {
      final AppUser user = AppUser.fromMap(
        <String, dynamic>{'favoriteTransportTypeId': 'teleferico'},
        'u4',
      );

      expect(user.favoriteTransportTypeId, 'teleferico');
    });

    test('sin preferencia → null', () {
      final AppUser user = AppUser.fromMap(const <String, dynamic>{}, 'u5');

      expect(user.favoriteTransportTypeId, isNull);
    });

    test('fallback legado: lista favoriteTransportTypeIds → primer elemento', () {
      final AppUser user = AppUser.fromMap(
        <String, dynamic>{
          'favoriteTransportTypeIds': <String>['omsa', 'metro'],
        },
        'u6',
      );

      expect(user.favoriteTransportTypeId, 'omsa');
    });

    test('el campo único gana sobre el fallback legado', () {
      final AppUser user = AppUser.fromMap(
        <String, dynamic>{
          'favoriteTransportTypeId': 'metro',
          'favoriteTransportTypeIds': <String>['omsa'],
        },
        'u7',
      );

      expect(user.favoriteTransportTypeId, 'metro');
    });
  });
}
