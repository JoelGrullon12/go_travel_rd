import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_route.dart';
import 'firebase_config.dart';

/// CRUD de rutas personalizadas del usuario (Hito 5).
///
/// Las rutas viven embebidas en `users/{uid}.userRoutes` (array de maps) — ver
/// `lib/models/models.yaml`. Las reglas de Firestore ya permiten que cada
/// usuario lea/escriba su propio documento, así que no hay que tocar
/// `firestore.rules`.
class UserRouteService {
  final FirebaseFirestore _firestore = firestore;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Rutas personalizadas del usuario actual. Vacío sin sesión.
  Future<List<UserRoute>> getUserRoutes() async {
    final String? uid = _uid;
    if (uid == null) return const <UserRoute>[];
    final DocumentSnapshot doc =
        await _firestore.collection('users').doc(uid).get();
    final List<dynamic> raw =
        (doc.data() as Map<String, dynamic>?)?['userRoutes'] as List? ??
            const [];
    return raw
        .whereType<Map>()
        .map((e) => UserRoute.fromMap(e.cast<String, dynamic>(), ''))
        .toList(growable: false);
  }

  /// Guarda (o reemplaza por nombre) una ruta personalizada.
  Future<void> saveRoute(UserRoute route) async {
    final String? uid = _uid;
    if (uid == null) {
      throw StateError('Se requiere iniciar sesión para guardar una ruta');
    }
    final DocumentReference ref = _firestore.collection('users').doc(uid);
    final DocumentSnapshot doc = await ref.get();
    final Map<String, dynamic> data =
        (doc.data() as Map<String, dynamic>?)?.cast<String, dynamic>() ?? {};
    final List<Map<String, dynamic>> routes = (data['userRoutes'] as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        <Map<String, dynamic>>[];
    routes.removeWhere((Map<String, dynamic> m) => m['name'] == route.name);
    routes.add(route.toMap());
    await ref.set(<String, dynamic>{...data, 'userRoutes': routes});
  }

  /// Borra la ruta personalizada con ese nombre (si existe).
  Future<void> deleteRoute(String name) async {
    final String? uid = _uid;
    if (uid == null) return;
    final DocumentReference ref = _firestore.collection('users').doc(uid);
    final DocumentSnapshot doc = await ref.get();
    final Map<String, dynamic> data =
        (doc.data() as Map<String, dynamic>?)?.cast<String, dynamic>() ?? {};
    final List<Map<String, dynamic>> routes = (data['userRoutes'] as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        <Map<String, dynamic>>[];
    routes.removeWhere((Map<String, dynamic> m) => m['name'] == name);
    await ref.set(<String, dynamic>{...data, 'userRoutes': routes});
  }
}
