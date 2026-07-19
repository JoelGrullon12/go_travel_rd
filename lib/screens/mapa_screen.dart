import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/metro_stations.dart';

class MapaScreen extends StatefulWidget {
  const MapaScreen({super.key});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  Set<Marker> get _marcadores => metroStations
      .map(
        (s) => Marker(
          markerId: MarkerId(s.name),
          position: LatLng(s.lat, s.lng),
          infoWindow: InfoWindow(
            title: s.name,
            snippet: 'Línea ${s.line}',
          ),
        ),
      )
      .toSet();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GoTravel RD'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(18.4861, -69.9312),
          zoom: 12,
        ),
        markers: _marcadores,
        myLocationEnabled: true,
      ),
    );
  }
}
