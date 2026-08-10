import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/transport_type.dart';
import 'firebase_config.dart';

/// Lee los tipos de transporte del catálogo (`transportTypes`) para la UI de
/// preferencias del usuario (Hito 5). Cada documento tiene `name` e `icon`
/// (ambos string) — ver `lib/models/models.yaml`.
class TransportTypeService {
  final FirebaseFirestore _firestore = firestore;

  /// Todos los tipos de transporte del catálogo. Vacío si la colección no
  /// tiene documentos (o no existe).
  Future<List<TransportType>> getTransportTypes() async {
    final snapshot = await _firestore
        .collection('transportTypes')
        .get(const GetOptions(source: Source.server));
    return snapshot.docs.map(TransportType.fromSnapshot).toList(growable: false);
  }
}
