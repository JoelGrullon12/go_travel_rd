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

  /// Obtiene las estaciones dentro del rectángulo `southWest`-`northEast`
  /// (el viewport visible del mapa).
  ///
  /// Firestore ordena los `GeoPoint` lexicográficamente (latitud primero),
  /// así que el rango `location >= southWest && location <= northEast`
  /// devuelve la banda de latitud completa (sobre-aproximación) y el filtro
  /// exacto por longitud se hace en Dart. La query usa un índice de un solo
  /// campo sobre `location`, que Firestore auto-crea.
  Future<List<Station>> getStationsInBounds({
    required GeoPoint southWest,
    required GeoPoint northEast,
  }) async {
    final snapshot = await _firestore
        .collection('stations')
        .where('location', isGreaterThanOrEqualTo: southWest)
        .where('location', isLessThanOrEqualTo: northEast)
        .get(const GetOptions(source: Source.server));
    return snapshot.docs.map(Station.fromSnapshot).where(
      (Station s) =>
          s.location.latitude >= southWest.latitude &&
          s.location.latitude <= northEast.latitude &&
          s.location.longitude >= southWest.longitude &&
          s.location.longitude <= northEast.longitude,
    ).toList();
  }
}
