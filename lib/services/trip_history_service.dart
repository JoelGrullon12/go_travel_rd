import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/trip_history_entry.dart';
import 'firebase_config.dart';

/// Historial de viajes del usuario (Hito 5).
///
/// Los viajes viven embebidos en `users/{uid}.tripHistory` (array de maps) —
/// ver `lib/models/models.yaml`. Igual que `UserRouteService`, lee y reescribe
/// el documento del usuario con `set` para conservar el resto de campos. Las
/// reglas de Firestore ya permiten que cada usuario lea/escriba su propio
/// documento, así que no hay que tocar `firestore.rules`.
class TripHistoryService {
  final FirebaseFirestore _firestore = firestore;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Historial de viajes del usuario actual, nuevo primero. Vacío sin sesión.
  Future<List<TripHistoryEntry>> getTripHistory() async {
    final String? uid = _uid;
    if (uid == null) return const <TripHistoryEntry>[];
    final DocumentSnapshot doc =
        await _firestore.collection('users').doc(uid).get();
    final List<dynamic> raw =
        (doc.data() as Map<String, dynamic>?)?['tripHistory'] as List? ??
            const [];
    return raw
        .whereType<Map>()
        .map((e) => TripHistoryEntry.fromMap(e.cast<String, dynamic>(), ''))
        .toList(growable: false);
  }

  /// Registra un viaje iniciado en el historial, insertándolo al inicio.
  Future<void> addEntry(TripHistoryEntry entry) async {
    final String? uid = _uid;
    if (uid == null) {
      throw StateError('Se requiere iniciar sesión para guardar un viaje');
    }
    final DocumentReference ref = _firestore.collection('users').doc(uid);
    final DocumentSnapshot doc = await ref.get();
    final Map<String, dynamic> data =
        (doc.data() as Map<String, dynamic>?)?.cast<String, dynamic>() ?? {};
    final List<Map<String, dynamic>> history =
        (data['tripHistory'] as List?)
                ?.whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList() ??
            <Map<String, dynamic>>[];
    history.insert(0, entry.toMap());
    await ref.set(<String, dynamic>{...data, 'tripHistory': history});
  }
}
