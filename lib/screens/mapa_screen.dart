import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/auth_service.dart';
import '../services/station_service.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

class MapaScreen extends StatefulWidget {
  const MapaScreen({super.key});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  final _authService = AuthService();
  final _stationService = StationService();
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = _authService.currentUser;
    _authService.authStateChanges.listen((user) {
      if (mounted) setState(() => _user = user);
    });
  }

  Set<Marker> _marcadoresFromStations(List stations) => stations
      .map(
        (s) => Marker(
          markerId: MarkerId(s.id),
          position: LatLng(s.location.latitude, s.location.longitude),
          infoWindow: InfoWindow(title: s.name),
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
        actions: [
          _user != null
              ? IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ProfileScreen()),
                    );
                  },
                  icon: CircleAvatar(
                    radius: 16,
                    backgroundImage: _user!.photoURL != null
                        ? NetworkImage(_user!.photoURL!)
                        : null,
                    child: _user!.photoURL == null
                        ? const Icon(Icons.person,
                            size: 20, color: Colors.white)
                        : null,
                  ),
                )
              : IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LoginScreen()),
                    );
                  },
                  icon: const Icon(Icons.person),
                ),
        ],
      ),
      body: StreamBuilder<List>(
        stream: _stationService.getStations(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error al cargar estaciones: ${snapshot.error}'));
          }
          final stations = snapshot.data ?? [];
          return GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(18.4861, -69.9312),
              zoom: 12,
            ),
            markers: _marcadoresFromStations(stations),
            myLocationEnabled: true,
          );
        },
      ),
    );
  }
}
