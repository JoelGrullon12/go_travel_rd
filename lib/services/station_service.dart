import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/station.dart';
import 'firebase_config.dart';

class StationService {
  final FirebaseFirestore _firestore = firestore;

  Stream<List<Station>> getStations() {
    return _firestore.collection('stations').snapshots().map(
          (snapshot) => snapshot.docs.map(Station.fromSnapshot).toList(),
        );
  }

  Future<List<Station>> getStationsOnce() async {
    final snapshot = await _firestore.collection('stations').get();
    return snapshot.docs.map(Station.fromSnapshot).toList();
  }
}
