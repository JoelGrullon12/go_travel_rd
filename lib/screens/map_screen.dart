import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/station.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/station_service.dart';
import '../widgets/search_box.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

/// Pantalla principal: mapa a pantalla completa + buscador flotante
/// estilo Uber + estaciones de Firestore + acceso al perfil.
///
/// Nota (ver AGENTS.md sección 5.4): este widget necesita un
/// contenedor de tamaño acotado para el `GoogleMap`, por eso vive
/// directamente en el `body` de un `Scaffold`.
///
/// La ubicación del usuario se obtiene del GPS en tiempo real
/// (stream continuo). Si el GPS está apagado o el permiso es
/// denegado, se usa [_defaultLocation] (Santo Domingo) como fallback
/// para que la app siga funcionando.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _authService = AuthService();
  final _locationService = LocationService();
  final _stationService = StationService();

  // ---------------------------------------------------------------------
  // Constantes / fallback
  // ---------------------------------------------------------------------

  /// Ubicación por defecto (Santo Domingo, centro) usada como fallback
  /// cuando no se puede obtener la posición real del GPS.
  static const LatLng _defaultLocation = LatLng(18.4861, -69.9312);

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: _defaultLocation,
    zoom: 14,
  );

  // ---------------------------------------------------------------------
  // Estado
  // ---------------------------------------------------------------------

  GoogleMapController? _mapController;

  /// Última posición real del usuario (desde el stream de GPS).
  LatLng? _currentLocation;

  /// Icono personalizado de ubicación actual (círculo azul con borde
  /// blanco + indicador de rumbo), generado al iniciar la pantalla.
  BitmapDescriptor? _locationIndicatorIcon;

  /// Rumbo actual del usuario en grados (0 = norte). Rota el icono de
  /// ubicación actual cuando el dispositivo gira.
  double _heading = 0.0;

  StreamSubscription<Position>? _positionSubscription;

  /// Suscripción a la brújula del dispositivo (rota el icono de
  /// ubicación actual según la orientación del teléfono).
  StreamSubscription<CompassEvent>? _compassSubscription;

  /// Evita animar la cámara hacia la ubicación más de una vez al inicio.
  bool _cameraCenteredOnStart = false;

  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController =
      TextEditingController();

  /// Texto de origen y destino ingresados por el usuario.
  String origin = '';
  String destination = '';

  User? _user;

  final Set<Marker> _markers = {};

  /// Preparado para dibujar rutas más adelante (Hito 2/3, ver
  /// AGENTS.md). Por ahora queda vacío; cuando exista un motor de
  /// cálculo de ruta, se llenaría con un `Polyline` a partir de la
  /// lista de puntos que devuelva ese cálculo.
  final Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _user = _authService.currentUser;
    _authService.authStateChanges.listen((user) {
      if (mounted) setState(() => _user = user);
    });
    _markers.add(_buildOriginMarker(_defaultLocation));
    origin = 'Mi ubicación actual';
    _originController.text = origin;
    _loadStations();
    _startLocationTracking();
    _initLocationIndicator();
    _startCompassTracking();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _compassSubscription?.cancel();
    _originController.dispose();
    _destinationController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Seguimiento de ubicación
  // ---------------------------------------------------------------------

  Future<void> _startLocationTracking() async {
    final granted = await _locationService.requestLocationPermission();
    if (!mounted || !granted) return;

    _positionSubscription = _locationService.getPositionStream().listen(
          _onPositionUpdate,
          onError: (Object _) {
            // Si se pierde el permiso o el GPS a mitad de sesión, se
            // conserva la última posición conocida como fallback.
          },
        );
  }

  /// Escucha la brújula del dispositivo para rotar el icono de
  /// ubicación actual cuando se gira el teléfono.
  ///
  /// El rumbo de `geolocator` solo refleja la dirección de movimiento
  /// (curso GPS), no la orientación del teléfono, por eso se usa el
  /// magnetómetro del dispositivo como fuente de rotación.
  void _startCompassTracking() {
    final stream = FlutterCompass.events;
    if (stream == null) return;
    _compassSubscription = stream.listen(_onCompassHeading);
  }

  void _onCompassHeading(CompassEvent event) {
    final heading = event.heading;
    if (heading == null) return;
    setState(() {
      _heading = heading;
      _markers.removeWhere((m) => m.markerId == const MarkerId('origin'));
      _markers.add(_buildOriginMarker(_currentLocation ?? _defaultLocation));
    });
  }

  void _onPositionUpdate(Position position) {
    final latLng = LatLng(position.latitude, position.longitude);
    final heading = position.heading < 0 ? _heading : position.heading;
    setState(() {
      _currentLocation = latLng;
      _heading = heading;
      _markers.removeWhere((m) => m.markerId == const MarkerId('origin'));
      _markers.add(_buildOriginMarker(latLng));
    });

    if (!_cameraCenteredOnStart) {
      _cameraCenteredOnStart = true;
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 16),
      );
    }
  }

  Future<void> _initLocationIndicator() async {
    final icon = await _buildLocationIndicatorIcon();
    if (!mounted) return;
    setState(() {
      _locationIndicatorIcon = icon;
      _markers.removeWhere((m) => m.markerId == const MarkerId('origin'));
      _markers.add(_buildOriginMarker(_currentLocation ?? _defaultLocation));
    });
  }

  /// Genera el icono de ubicación actual estilo Google Maps/Uber:
  /// círculo azul con borde blanco y un indicador de rumbo que apunta
  /// al norte por defecto. [Marker.rotation] lo rota con el rumbo del
  /// dispositivo.
  Future<BitmapDescriptor> _buildLocationIndicatorIcon() async {
    const size = 128.0;
    final center = Offset(size / 2, size / 2);
    const blue = Color(0xFF1A73E8);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Sombra sutil
    final shadow = ui.Paint()..isAntiAlias = true;
    shadow.color = const Color(0x40000000);
    canvas.drawCircle(center + const Offset(0, 3), 30, shadow);

    // Indicador de rumbo (triángulo apuntando al norte por defecto)
    final arrow = ui.Paint()..isAntiAlias = true;
    arrow.color = blue;
    final arrowPath = ui.Path()
      ..moveTo(size / 2, size / 2 - 52)
      ..lineTo(size / 2 - 15, size / 2 - 20)
      ..lineTo(size / 2 + 15, size / 2 - 20)
      ..close();
    canvas.drawPath(arrowPath, arrow);

    // Borde blanco
    final border = ui.Paint()..isAntiAlias = true;
    border.color = Colors.white;
    canvas.drawCircle(center, 30, border);

    // Círculo azul
    final fill = ui.Paint()..isAntiAlias = true;
    fill.color = blue;
    canvas.drawCircle(center, 24, fill);

    // Punto interior blanco
    final dot = ui.Paint()..isAntiAlias = true;
    dot.color = Colors.white;
    canvas.drawCircle(center, 8, dot);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: 2,
    );
  }

  // ---------------------------------------------------------------------
  // Carga de estaciones
  // ---------------------------------------------------------------------

  Future<void> _loadStations() async {
    final stations = await _stationService.getStationsOnce();
    if (!mounted) return;
    setState(() {
      _markers.addAll(stations.map(_buildStationMarker));
    });
  }

  // ---------------------------------------------------------------------
  // Helpers de marcadores
  // ---------------------------------------------------------------------

  Marker _buildStationMarker(Station station) {
    return Marker(
      markerId: MarkerId('station-${station.id}'),
      position: LatLng(station.location.latitude, station.location.longitude),
      infoWindow: InfoWindow(title: station.name),
    );
  }

  Marker _buildOriginMarker(LatLng position) {
    return Marker(
      markerId: const MarkerId('origin'),
      position: position,
      rotation: _heading,
      anchor: const Offset(0.5, 0.5),
      icon: _locationIndicatorIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      infoWindow: const InfoWindow(title: 'Origen'),
    );
  }

  Marker _buildDestinationMarker(LatLng position, String label) {
    return Marker(
      markerId: const MarkerId('destination'),
      position: position,
      icon: BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueRed,
      ),
      infoWindow: InfoWindow(title: 'Destino', snippet: label),
    );
  }

  /// Genera coordenadas simuladas para el destino.
  ///
  /// No hay geocodificación real todavía (ver AGENTS.md sección 3.2:
  /// las fuentes oficiales no traen lat/lng listas). Mientras tanto,
  /// se ubica el destino en un punto cercano a la ubicación actual,
  /// con un pequeño desplazamiento aleatorio, solo para poder
  /// visualizar el flujo completo en el mapa.
  LatLng _simulateDestinationCoordinates() {
    final base = _currentLocation ?? _defaultLocation;
    final random = Random();
    final latOffset = (random.nextDouble() - 0.5) * 0.05;
    final lngOffset = (random.nextDouble() - 0.5) * 0.05;
    return LatLng(
      base.latitude + latOffset,
      base.longitude + lngOffset,
    );
  }

  // ---------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------

  void _onOriginSubmitted(String value) {
    setState(() => origin = value);
  }

  void _onDestinationSubmitted(String value) {
    if (value.trim().isEmpty) return;

    final destinationCoordinates = _simulateDestinationCoordinates();

    setState(() {
      destination = value;
      _markers.removeWhere((m) => m.markerId == const MarkerId('destination'));
      _markers.add(_buildDestinationMarker(destinationCoordinates, value));

      // TODO(hito-2/3): cuando exista el motor de cálculo de ruta,
      // reemplazar esto por el trazado real devuelto por ese cálculo.
      _polylines.clear();
    });

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(destinationCoordinates, 15),
    );

    FocusScope.of(context).unfocus();
  }

  Future<void> _onLocationButtonPressed() async {
    final current = _currentLocation;
    if (current != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(current, 18),
      );
      return;
    }

    final position = await _locationService.getCurrentPosition();
    if (!mounted) return;

    if (position != null) {
      final latLng = LatLng(position.latitude, position.longitude);
      final heading = position.heading < 0 ? _heading : position.heading;
      setState(() {
        _currentLocation = latLng;
        _heading = heading;
        _markers.removeWhere((m) => m.markerId == const MarkerId('origin'));
        _markers.add(_buildOriginMarker(latLng));
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 16),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No se pudo obtener tu ubicación. Activa el GPS o concede el permiso de ubicación.',
          ),
          action: SnackBarAction(
            label: 'Ajustes',
            onPressed: () => _locationService.openLocationSettings(),
          ),
        ),
      );
    }
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _user != null
            ? const ProfileScreen()
            : const LoginScreen(),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // El mapa ocupa toda la pantalla; el buscador y el avatar se
      // superponen encima con un Stack.
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              final current = _currentLocation;
              if (current != null && !_cameraCenteredOnStart) {
                _cameraCenteredOnStart = true;
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(current, 16),
                );
              }
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SearchBox(
                      originController: _originController,
                      destinationController: _destinationController,
                      onOriginSubmitted: _onOriginSubmitted,
                      onDestinationSubmitted: _onDestinationSubmitted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildProfileAvatar(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onLocationButtonPressed,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        child: const Icon(Icons.my_location),
      ),
    );
  }

  Widget _buildProfileAvatar() {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _openProfile,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: Colors.green[700],
            backgroundImage: _user?.photoURL != null
                ? NetworkImage(_user!.photoURL!)
                : null,
            child: _user?.photoURL == null
                ? Icon(
                    _user != null
                        ? Icons.person
                        : Icons.person_outline,
                    size: 20,
                    color: Colors.white,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
