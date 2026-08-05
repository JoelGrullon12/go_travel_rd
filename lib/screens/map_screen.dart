import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../application/data_providers.dart';
import '../application/planner_controller.dart';
import '../domain/models/trip_plan.dart';
import '../domain/routing/route_engine.dart';
import '../features/live_trip/live_trip_screen.dart';
import '../features/live_trip/widgets/map_style.dart';
import '../features/shared/mode_visuals.dart';
import '../features/shared/station_visuals.dart';
import '../models/station.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/station_service.dart';
import '../widgets/search_box.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';

/// Modo en el que el mapa elige un punto con un pin fijo en el centro
/// (estilo Uber), en vez de escribir coordenadas. [MapScreen.pickerMode]
/// define cuál de los dos campos se está eligiendo.
enum MapPickerMode { origin, destination }

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
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({
    super.key,
    this.plan,
    this.initialOrigin = '',
    this.initialDestination = '',
    this.pickerMode,
  });

  /// Plan de viaje ya resuelto (viene del Hito 4 / demo del Hito 2).
  ///
  /// Cuando se pasa, el mapa dibuja la ruta del plan y muestra la barra
  /// inferior con el botón "Iniciar Viaje". Sin plan, el mapa conserva el
  /// comportamiento de exploración (búsqueda libre + marcadores).
  final TripPlan? plan;

  /// Textos con los que se pre-llenan los campos de origen y destino.
  final String initialOrigin;
  final String initialDestination;

  /// Cuando no es `null`, el mapa entra en modo "elegir punto con el pin":
  /// se muestra un pin fijo en el centro y una barra inferior para confirmar
  /// el punto ([MapPickerMode.origin]) o calcular la ruta
  /// ([MapPickerMode.destination]).
  final MapPickerMode? pickerMode;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
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
  final TextEditingController _destinationController = TextEditingController();

  /// Texto de origen y destino ingresados por el usuario.
  String origin = '';
  String destination = '';

  User? _user;

  final Set<Marker> _markers = {};

  /// Iconos de estación por tipo de transporte y tamaño (`'$type@$size'`),
  /// para reutilizarlos entre las estaciones en vez de decodificar el PNG
  /// una vez por marcador o en cada frame del gesto de zoom.
  final Map<String, BitmapDescriptor> _stationTypeIcons = {};

  /// Último zoom conocido de la cámara (se actualiza en `onCameraMove`,
  /// barato). Se usa cuando el usuario suelta el mapa (`onCameraIdle`).
  double _lastZoom = 14;

  /// Token para descartar renders de estaciones obsoletos: si el usuario
  /// vuelve a mover el mapa mientras se dibuja, solo gana el último.
  int _renderToken = 0;

  /// Última zona consultada a Firestore + sus estaciones, para reutilizarla
  /// cuando el viewport nuevo cae dentro de esta zona (sin re-consultar).
  LatLngBounds? _cachedBounds;
  List<Station> _cachedStations = const [];

  /// Última zona/bucket ya renderizados, para saltar renders redundantes
  /// cuando el usuario suelta el mapa sin haber cambiado nada.
  LatLngBounds? _lastRenderedBounds;
  int _lastRenderedBucket = -1;

  /// Preparado para dibujar rutas más adelante (Hito 2/3, ver
  /// AGENTS.md). Por ahora queda vacío; cuando exista un motor de
  /// cálculo de ruta, se llenaría con un `Polyline` a partir de la
  /// lista de puntos que devuelva ese cálculo.
  final Set<Polyline> _polylines = {};

  /// Plan activo (cuando se abrió el mapa desde una ruta favorita o demo).
  /// Su presencia activa la barra inferior con el botón "Iniciar Viaje".
  TripPlan? _activePlan;

  // ---------------------------------------------------------------------
  // Selección de punto con pin (Hito 2)
  // ---------------------------------------------------------------------

  /// Cuál de los dos puntos se está eligiendo ahora (`null` = no seleccionando).
  MapPickerMode? _pickerMode;

  /// Centro de la cámara en vivo. En modo pin es el punto que se confirma.
  /// `ValueNotifier` para actualizar las coordenadas de la barra sin
  /// reconstruir todo el mapa en cada frame del gesto de cámara.
  final ValueNotifier<LatLng?> _cameraTarget = ValueNotifier<LatLng?>(null);

  /// Puntos ya confirmados (se pasan al motor en [MapPickerMode.destination]).
  LatLng? _pickerOriginPoint;
  LatLng? _pickerDestinationPoint;

  /// `true` una vez que el motor calculó un plan desde esta pantalla. Se usa
  /// para que el botón atrás vuelva a la planificación en vez de salir, sin
  /// afectar a los planes demo que llegan desde `HomeScreen` (que sí salen
  /// con atrás).
  bool _didComputeRoute = false;

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
    _cameraTarget.value = _initialCameraPosition.target;
    _startLocationTracking();
    _initLocationIndicator();
    _startCompassTracking();

    // Plan recibido desde la pantalla de inicio: se pre-llenan los campos,
    // se dibuja la ruta y se habilita "Iniciar Viaje".
    if (widget.initialOrigin.isNotEmpty) {
      origin = widget.initialOrigin;
      _originController.text = widget.initialOrigin;
    }
    if (widget.initialDestination.isNotEmpty) {
      destination = widget.initialDestination;
      _destinationController.text = widget.initialDestination;
    }
    if (widget.plan != null) _activatePlan(widget.plan!);

    // Modo "elegir punto": entra directamente a la selección del campo pedido.
    if (widget.pickerMode != null) {
      _pickerMode = widget.pickerMode;
      if (_pickerMode == MapPickerMode.origin) _originController.clear();
      if (_pickerMode == MapPickerMode.destination) {
        _destinationController.clear();
      }
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _compassSubscription?.cancel();
    _originController.dispose();
    _destinationController.dispose();
    _cameraTarget.dispose();
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
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
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
  // Estaciones según el zoom y el viewport
  // ---------------------------------------------------------------------

  /// Bucket de zoom en el que están las estaciones. Al cruzar de un bucket
  /// a otro se reconstruyen los markers con el nuevo tamaño/visibilidad.
  ///
  /// Límites: 14 (detalle), 12 (ciudad), 10.5 (región). Por debajo de 10.5
  /// desaparecen todas las estaciones.
  int _stationZoomBucket(double zoom) {
    if (zoom >= 14) return 3;
    if (zoom >= 12) return 2;
    if (zoom >= 10.5) return 1;
    return 0;
  }

  /// Tamaño (px) del icono de estación para un tipo en un bucket de zoom.
  /// `null` = el tipo se oculta en ese bucket.
  ///
  /// OMSA desaparece antes que el resto (bajo zoom 12): son las más densas
  /// (~450 estaciones), las que más se apiñan al alejarse.
  double? _stationIconSize(String type, int bucket) {
    final bool isOmsa = type == 'omsa';
    if (isOmsa && bucket < 2) return null;
    if (bucket < 1) return null;
    return switch (bucket) {
      1 => 10,
      2 => 14,
      _ => 20,
    };
  }

  /// Se ejecuta cuando el usuario suelta el mapa (`onCameraIdle`): calcula el
  /// bucket, consulta a Firestore solo las estaciones del viewport (con cache
  /// en memoria) y las dibuja en lotes, sin bloquear la UI.
  Future<void> _onCameraIdle() async {
    final GoogleMapController? controller = _mapController;
    if (controller == null) return;

    // Con un plan activo el mapa muestra la ruta, no el catálogo de estaciones.
    if (_activePlan != null) {
      _removeStationMarkers();
      return;
    }

    final int bucket = _stationZoomBucket(_lastZoom);
    if (bucket == 0) {
      _removeStationMarkers();
      _lastRenderedBucket = 0;
      _lastRenderedBounds = null;
      return;
    }

    final LatLngBounds? bounds = await _visibleRegion(controller);
    if (bounds == null || !mounted) return;

    // Sin cambios desde el último render → no hacer nada.
    if (bucket == _lastRenderedBucket &&
        _boundsContains(_lastRenderedBounds, bounds)) {
      return;
    }

    final int request = ++_renderToken;

    final List<Station> stations = await _stationsForBounds(bounds);
    if (!mounted || request != _renderToken) return;

    final double size = _stationIconSize('metro', bucket)!;
    final List<Station> visible = stations
        .where(
          (Station s) =>
              _stationIconSize(s.transportTypeId ?? '', bucket) != null,
        )
        .toList();

    await _loadStationTypeIcons(visible, size);
    if (!mounted || request != _renderToken) return;

    _lastRenderedBounds = bounds;
    _lastRenderedBucket = bucket;
    await _renderStationMarkersInChunks(visible, size, request);
  }

  /// Devuelve el rectángulo visible del mapa, o `null` si no se puede obtener.
  Future<LatLngBounds?> _visibleRegion(GoogleMapController controller) async {
    try {
      return await controller.getVisibleRegion();
    } on Exception {
      return null;
    }
  }

  /// Devuelve las estaciones del viewport, reutilizando la zona cacheada si
  /// el viewport cae dentro de ella (para no re-consultar al panear).
  Future<List<Station>> _stationsForBounds(LatLngBounds bounds) async {
    final LatLngBounds? cached = _cachedBounds;
    if (cached != null && _boundsContains(cached, bounds)) {
      return _cachedStations;
    }
    final List<Station> stations = await _stationService.getStationsInBounds(
      southWest: GeoPoint(
        bounds.southwest.latitude,
        bounds.southwest.longitude,
      ),
      northEast: GeoPoint(
        bounds.northeast.latitude,
        bounds.northeast.longitude,
      ),
    );
    _cachedBounds = bounds;
    _cachedStations = stations;
    return stations;
  }

  /// `true` si `inner` está completamente dentro de `outer` (con margen de
  /// 1% para evitar re-renders por diferencias de redondeo).
  bool _boundsContains(LatLngBounds? outer, LatLngBounds inner) {
    if (outer == null) return false;
    const double margin = 0.01;
    return inner.southwest.latitude >=
            outer.southwest.latitude * (1 - margin) &&
        inner.northeast.latitude <= outer.northeast.latitude * (1 + margin) &&
        inner.southwest.longitude >= outer.southwest.longitude * (1 - margin) &&
        inner.northeast.longitude <= outer.northeast.longitude * (1 + margin);
  }

  /// Elimina los markers de estación (`station-*`) del mapa.
  void _removeStationMarkers() {
    if (!mounted) return;
    setState(() {
      _markers.removeWhere(
        (Marker m) => m.markerId.value.startsWith('station-'),
      );
    });
  }

  /// Dibuja los markers de estación en lotes (~50 por frame) para no
  /// congelar la UI. Cada lote verifica que el render siga vigente; si el
  /// usuario movió el mapa, se descarta y gana el nuevo.
  Future<void> _renderStationMarkersInChunks(
    List<Station> stations,
    double size,
    int request,
  ) async {
    const int chunkSize = 50;
    _removeStationMarkers();
    for (int i = 0; i < stations.length; i += chunkSize) {
      if (!mounted || request != _renderToken) return;
      final int end = (i + chunkSize < stations.length)
          ? i + chunkSize
          : stations.length;
      setState(() {
        _markers.addAll(
          stations
              .sublist(i, end)
              .map((Station s) => _buildStationMarker(s, size)),
        );
      });
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  /// Carga un `BitmapDescriptor` por cada `transportTypeId` presente que
  /// tenga asset propio (ver [stationIconAsset]). Los tipos sin icono se
  /// dejan fuera: sus marcadores usan el pin por defecto.
  Future<void> _loadStationTypeIcons(
    List<Station> stations,
    double size,
  ) async {
    final types = stations
        .map((Station s) => s.transportTypeId)
        .whereType<String>()
        .toSet();
    for (final type in types) {
      final asset = stationIconAsset(type);
      if (asset == null) continue;
      final String key = '$type@$size';
      if (_stationTypeIcons.containsKey(key)) continue;
      final icon = await BitmapDescriptor.asset(
        ImageConfiguration(size: const Size(40, 40)),
        asset,
        width: size,
        height: size,
      );
      _stationTypeIcons[key] = icon;
    }
  }

  // ---------------------------------------------------------------------
  // Plan de viaje activo
  // ---------------------------------------------------------------------

  /// Activa un plan: dibuja su ruta y sus extremos sobre el mapa y guarda
  /// el plan para habilitar el botón "Iniciar Viaje".
  ///
  /// El plan llega de dos sitios: de la pantalla de inicio (rutas demo) o del
  /// motor del Hito 2 ([plannerControllerProvider]). Para la UI es lo mismo:
  /// solo cambia el origen del plan.
  void _activatePlan(TripPlan plan) {
    setState(() {
      _activePlan = plan;
      // Un plan resuelto reemplaza el modo pin: se sale de la selección y se
      // muestra la ruta + "Iniciar Viaje".
      _pickerMode = null;

      _polylines.clear();
      for (int i = 0; i < plan.legs.length; i++) {
        final leg = plan.legs[i];
        _polylines.add(
          Polyline(
            polylineId: PolylineId('plan-leg-$i'),
            points: leg.path.map((p) => p.toLatLng).toList(),
            color: Color(leg.lineColorHex),
            width: leg.mode.isWalking ? 5 : 8,
            patterns: leg.mode.isWalking
                ? <PatternItem>[PatternItem.dot, PatternItem.gap(14)]
                : const <PatternItem>[],
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            zIndex: 1,
          ),
        );
      }

      // El plan reemplaza el catálogo de estaciones y los marcadores del pin.
      _markers.removeWhere(
        (Marker m) => m.markerId.value.startsWith('station-'),
      );
      _markers.removeWhere(
        (m) =>
            m.markerId == const MarkerId('plan-origin') ||
            m.markerId == const MarkerId('plan-destination') ||
            m.markerId == const MarkerId('picker-origin') ||
            m.markerId == const MarkerId('picker-destination'),
      );
      _markers.removeWhere(
        (m) => m.markerId.value.startsWith('plan-stop-'),
      );
      _markers.addAll(_buildPlanStopMarkers(plan));
      _markers.add(
        Marker(
          markerId: const MarkerId('plan-origin'),
          position: plan.origin.toLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(title: plan.originName, snippet: 'Origen'),
        ),
      );
      _markers.add(
        Marker(
          markerId: const MarkerId('plan-destination'),
          position: plan.destination.toLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: plan.destinationName,
            snippet: 'Destino',
          ),
        ),
      );
    });

    _fitToPlan(plan);
    // Los iconos (assets PNG) se cargan aparte: al terminar, se refrescan los
    // marcadores de las paradas con su icono real.
    _ensurePlanStopIcons(plan);
  }

  /// Marcadores de las estaciones por las que pasa el plan, con el icono de su
  /// tipo de transporte (Metro vs. OMSA, etc.). Una estación de transbordo
  /// aparece en dos tramos: se deduplica por id para no dibujar dos pins.
  ///
  /// Mientras el `BitmapDescriptor` no está cargado se usa el pin por defecto;
  /// [_ensurePlanStopIcons] refresca cuando llega.
  Iterable<Marker> _buildPlanStopMarkers(TripPlan plan) {
    final Set<String> seen = <String>{};
    final List<Marker> markers = <Marker>[];
    for (int legIndex = 0; legIndex < plan.legs.length; legIndex++) {
      final TripLeg leg = plan.legs[legIndex];
      if (leg.mode.isWalking) continue;
      final String iconKey = _planStopIconKey(leg.mode.code);
      final String lineName = leg.lineName;
      for (final TripStop stop in leg.stops) {
        if (!seen.add(stop.id)) continue;
        markers.add(
          Marker(
            markerId: MarkerId('plan-stop-$legIndex-${stop.id}'),
            position: stop.position.toLatLng,
            icon: _stationTypeIcons.containsKey(iconKey)
                ? _stationTypeIcons[iconKey]!
                : BitmapDescriptor.defaultMarker,
            infoWindow: InfoWindow(
              title: stop.name,
              snippet: lineName,
            ),
          ),
        );
      }
    }
    return markers;
  }

  /// Carga los iconos de las estaciones del plan ([_buildPlanStopMarkers]) en
  /// un tamaño fijo y refresca los marcadores cuando llegan.
  Future<void> _ensurePlanStopIcons(TripPlan plan) async {
    final Iterable<String> types = <String>{
      for (final TripLeg leg in plan.legs)
        if (!leg.mode.isWalking) leg.mode.code,
    };
    for (final String type in types) {
      final String? asset = stationIconAsset(type);
      if (asset == null) continue;
      final String key = _planStopIconKey(type);
      if (_stationTypeIcons.containsKey(key)) continue;
      final BitmapDescriptor icon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(40, 40)),
        asset,
        width: 28,
        height: 28,
      );
      _stationTypeIcons[key] = icon;
    }
    if (!mounted) return;
    setState(() {
      final TripPlan? current = _activePlan;
      if (current == null) return;
      _markers.removeWhere(
        (m) => m.markerId.value.startsWith('plan-stop-'),
      );
      _markers.addAll(_buildPlanStopMarkers(current));
    });
  }

  static String _planStopIconKey(String transportTypeId) => 'plan-$transportTypeId';

  /// Encuadra la cámara para que toda la ruta del plan quede visible.
  void _fitToPlan(TripPlan plan) {
    final List<LatLng> all = <LatLng>[
      for (final leg in plan.legs) ...leg.path.map((p) => p.toLatLng),
    ];
    if (all.isEmpty) return;

    double minLat = all.first.latitude, maxLat = all.first.latitude;
    double minLng = all.first.longitude, maxLng = all.first.longitude;
    for (final LatLng p in all) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }

    // Puntos degenerados (ej. solo-a-pie con extremos casi iguales): la vista
    // aérea de un cuadro de 0 m lanza excepción en el plugin.
    if (maxLat - minLat < 1e-6 && maxLng - minLng < 1e-6) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(plan.origin.toLatLng),
      );
      return;
    }

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  void _startTrip() {
    final plan = _activePlan;
    if (plan == null) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => LiveTripScreen(planId: plan.id)),
    );
  }

  // ---------------------------------------------------------------------
  // Helpers de marcadores
  // ---------------------------------------------------------------------

  Marker _buildStationMarker(Station station, double size) {
    final String? type = station.transportTypeId;
    final String? key = type == null ? null : '$type@$size';
    return Marker(
      markerId: MarkerId('station-${station.id}'),
      position: LatLng(station.location.latitude, station.location.longitude),
      icon: key != null && _stationTypeIcons.containsKey(key)
          ? _stationTypeIcons[key]!
          : BitmapDescriptor.defaultMarker,
      infoWindow: InfoWindow(title: station.name),
    );
  }

  Marker _buildOriginMarker(LatLng position) {
    return Marker(
      markerId: const MarkerId('origin'),
      position: position,
      rotation: _heading,
      anchor: const Offset(0.5, 0.5),
      icon:
          _locationIndicatorIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      infoWindow: const InfoWindow(title: 'Origen'),
    );
  }

  Marker _buildDestinationMarker(LatLng position, String label) {
    return Marker(
      markerId: const MarkerId('destination'),
      position: position,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
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
    return LatLng(base.latitude + latOffset, base.longitude + lngOffset);
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

  // ---------------------------------------------------------------------
  // Selección de punto con pin (Hito 2)
  // ---------------------------------------------------------------------

  /// Confirma el punto del centro de la cámara como origen o destino.
  /// Origen → avanza a elegir destino (auto-avance). Destino → calcula la ruta.
  void _confirmPick() {
    final LatLng? target = _cameraTarget.value;
    if (target == null) return;

    if (_pickerMode == MapPickerMode.origin) {
      setState(() {
        _pickerOriginPoint = target;
        _originController.text = _coordinateLabel(target);
        _markers.removeWhere(
          (m) => m.markerId == const MarkerId('picker-origin'),
        );
        _markers.add(
          _pickerMarker(
            'picker-origin',
            target,
            'Origen',
            BitmapDescriptor.hueGreen,
          ),
        );
        _pickerMode = MapPickerMode.destination;
        // Conserva un destino ya elegido (los inputs funcionan todo el tiempo):
        // solo se limpia el campo cuando no hay destino confirmado todavía.
        if (_pickerDestinationPoint == null) _destinationController.clear();
      });
      return;
    }

    // Flujo arrancado por el campo de destino (Home): falta el origen.
    if (_pickerOriginPoint == null) {
      setState(() => _pickerMode = MapPickerMode.origin);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero elige tu punto de partida.')),
      );
      return;
    }

    setState(() {
      _pickerDestinationPoint = target;
      _destinationController.text = _coordinateLabel(target);
      _markers.removeWhere(
        (m) => m.markerId == const MarkerId('picker-destination'),
      );
      _markers.add(
        _pickerMarker(
          'picker-destination',
          target,
          'Destino',
          BitmapDescriptor.hueRed,
        ),
      );
    });
    _computeRoute();
  }

  /// Lanza el motor A→B con los dos puntos confirmados. El resultado llega por
  /// el listener de [plannerControllerProvider] en `build`.
  ///
  /// El modo pin se mantiene durante el cálculo: la barra muestra el spinner y,
  /// si el plan falla, el pin queda para reajustar el punto (o para el diálogo
  /// de distancia a pie).
  void _computeRoute() {
    final LatLng? originLatLng = _pickerOriginPoint;
    final LatLng? destinationLatLng = _pickerDestinationPoint;
    if (originLatLng == null || destinationLatLng == null) return;

    ref
        .read(plannerControllerProvider.notifier)
        .plan(
          origin: originLatLng.toGeoPoint,
          destination: destinationLatLng.toGeoPoint,
        );
  }

  void _showFailure(RoutePlanFailure failure) {
    final String message = switch (failure) {
      RoutePlanFailure.noStationsNearOrigin =>
        'No hay estaciones a menos de tu distancia a pie del origen. '
            'Acércate a una estación del Metro o a una parada de OMSA.',
      RoutePlanFailure.noStationsNearDestination =>
        'No hay estaciones a menos de tu distancia a pie del destino. '
            'Acércate a una estación del Metro o a una parada de OMSA.',
      RoutePlanFailure.noRoute =>
        'No se encontró una ruta entre esos puntos. Prueba con otro origen o destino.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Reacciona a un fallo del motor. Los fallos de distancia a pie abren un
  /// diálogo con opción de planificar igualmente; los de ruta (que no se pueden
  /// "forzar") siguen siendo un SnackBar.
  void _handlePlanFailure(RoutePlanFailure failure) {
    if (failure == RoutePlanFailure.noRoute) {
      _showFailure(failure);
      return;
    }
    _confirmPlanBeyondMaxWalk(failure);
  }

  /// Muestra el diálogo "superas tu distancia máxima a pie" y, si el usuario
  /// acepta, re-planifica con la distancia a pie sin límite.
  Future<void> _confirmPlanBeyondMaxWalk(RoutePlanFailure failure) async {
    final bool isOrigin = failure == RoutePlanFailure.noStationsNearOrigin;
    final double maxWalk =
        ref.read(maxWalkDistanceProvider).valueOrNull ?? kDefaultMaxWalkMeters;
    final String end = isOrigin ? 'punto de partida' : 'destino';

    final bool? accept = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Distancia a pie superada'),
        content: Text(
          'Tu $end está a más de ${Fmt.distance(maxWalk)} a pie de la '
          'estación o parada más cercana, superando tu distancia máxima '
          'configurada. ¿Quieres planificar la ruta de todas formas?',
        ),
        // Un solo `Row` dentro de `actions`: el `OverflowBar` de M3 apila en
        // vertical los botones que no caben (ancho por defecto del diálogo),
        // por eso se fuerzan lado a lado.
        actions: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar ruta'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Planificar ruta'),
              ),
            ],
          ),
        ],
      ),
    );

    if (!mounted || accept != true) return;
    final LatLng? originLatLng = _pickerOriginPoint;
    final LatLng? destinationLatLng = _pickerDestinationPoint;
    if (originLatLng == null || destinationLatLng == null) return;
    ref
        .read(plannerControllerProvider.notifier)
        .plan(
          origin: originLatLng.toGeoPoint,
          destination: destinationLatLng.toGeoPoint,
          overrideMaxWalk: true,
        );
  }

  /// "18.48612, -69.93123" — sin geocodificación inversa, es la descripción
  /// más exacta que se le puede dar al punto confirmado.
  String _coordinateLabel(LatLng point) =>
      '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';

  Future<void> _onLocationButtonPressed() async {
    final current = _currentLocation;
    if (current != null) {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(current, 18));
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
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
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
        builder: (_) =>
            _user != null ? const ProfileScreen() : const LoginScreen(),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final PlannerState plannerState = ref.watch(plannerControllerProvider);

    // Resultado del motor A→B: dibuja el plan calculado o muestra el fallo.
    // ref.listen solo puede usarse dentro de build (no en initState).
    ref.listen(plannerControllerProvider, (
      PlannerState? prev,
      PlannerState next,
    ) {
      if (!mounted) return;
      final TripPlan? plan = next.plan;
      if (plan != null && _activePlan?.id != plan.id) {
        _didComputeRoute = true;
        _activatePlan(plan);
      } else if (next.failure != null && prev?.failure != next.failure) {
        _handlePlanFailure(next.failure!);
      }
    });

    return PopScope(
      // Atrás con un plan calculado (o con origen confirmado) vuelve a la
      // planificación conservando el origen (cambio 6); los planes demo abiertos
      // desde Home siguen saliendo con atrás.
      canPop: !_canInterceptBack(),
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop || !_canInterceptBack()) return;
        _resetToDestinationPick();
      },
      child: Scaffold(
        // El mapa ocupa toda la pantalla; el buscador y el avatar se
        // superponen encima con un Stack.
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: _initialCameraPosition,
              // Mismo estilo oscuro que el mapa del viaje activo (kDarkMapStyle):
              // calles apagadas para que lo único brillante sea la ruta y la
              // posición del usuario.
              style: kDarkMapStyle,
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
                // Red de seguridad: en algunas plataformas el `onCameraIdle`
                // inicial no dispara solo; se programa un primer render.
                Future<void>.delayed(
                  const Duration(milliseconds: 400),
                  _onCameraIdle,
                );
              },
              onCameraMove: (CameraPosition position) {
                _lastZoom = position.zoom;
                // En modo pin, el centro de la cámara es el punto que se elige.
                // Se actualiza sin setState: la barra lo escucha con un
                // ValueListenableBuilder (no reconstruir el mapa por frame).
                _cameraTarget.value = position.target;
              },
              onCameraIdle: _onCameraIdle,
            ),

            // Pin fijo en el centro mientras se elige un punto (estilo Uber).
            if (_pickerMode != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -16),
                      child: const Icon(
                        Icons.location_on,
                        size: 44,
                        color: AppColors.critical,
                        shadows: <Shadow>[
                          Shadow(color: Colors.black, blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                ),
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
                        readOnly: true,
                        onOriginSubmitted: _onOriginSubmitted,
                        onDestinationSubmitted: _onDestinationSubmitted,
                        onOriginTap: _startOriginPick,
                        onDestinationTap: _startDestinationPick,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildProfileAvatar(),
                  ],
                ),
              ),
            ),

            if (_pickerMode != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    // Feedback del punto ya confirmado (cambio 2) + FAB que solo
                    // mueve la cámara a la ubicación actual (cambio 3).
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MyLocationFab(
                        onPressed: _onLocationButtonPressed,
                      ),
                    ),
                    _PickPointBar(
                      mode: _pickerMode!,
                      coordinates: _cameraTarget,
                      onConfirm: _confirmPick,
                    ),
                  ],
                ),
              ),

            if (_activePlan != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MyLocationFab(
                        onPressed: _onLocationButtonPressed,
                      ),
                    ),
                    _StartTripBar(plan: _activePlan!, onStart: _startTrip),
                  ],
                ),
              ),

            // Overlay de cálculo: feedback mientras el motor busca la mejor
            // ruta, con cancelar para volver a elegir los puntos.
            if (plannerState.isComputing)
              Positioned.fill(
                child: _ComputingOverlay(
                  onCancel: () =>
                      ref.read(plannerControllerProvider.notifier).cancel(),
                ),
              ),
          ],
        ),
        floatingActionButton: _activePlan == null && _pickerMode == null
            ? _MyLocationFab(onPressed: _onLocationButtonPressed)
            : null,
      ),
    );
  }

  /// Re-entra al modo de elegir el punto de origen con el pin. Los inputs
  /// funcionan en cualquier momento del flujo (cambio 1): si hay un plan activo
  /// se limpia y se vuelve a elegir el origen.
  void _startOriginPick() {
    if (_pickerMode == MapPickerMode.origin) return;
    setState(() {
      _clearActivePlanState();
      _pickerMode = MapPickerMode.origin;
      _pickerOriginPoint = null;
      _originController.clear();
      _markers.removeWhere(
        (m) => m.markerId == const MarkerId('picker-origin'),
      );
    });
  }

  /// Re-entra al modo de elegir el punto de destino con el pin.
  void _startDestinationPick() {
    if (_pickerMode == MapPickerMode.destination) return;
    setState(() {
      _clearActivePlanState();
      _pickerMode = MapPickerMode.destination;
      _pickerDestinationPoint = null;
      _destinationController.clear();
      _markers.removeWhere(
        (m) => m.markerId == const MarkerId('picker-destination'),
      );
    });
  }

  /// Limpia el plan activo (polilíneas + marcadores). Solo toca estado del
  /// plan: se llama dentro del `setState` del llamador.
  void _clearActivePlanState() {
    _activePlan = null;
    _polylines.clear();
    _markers.removeWhere(
      (m) =>
          m.markerId == const MarkerId('plan-origin') ||
          m.markerId == const MarkerId('plan-destination') ||
          m.markerId.value.startsWith('plan-stop-'),
    );
  }

  /// `true` si el atrás debe volver al flujo de planificación en vez de salir
  /// de la pantalla: hay un origen confirmado o un plan calculado por el motor
  /// (los planes demo abiertos desde Home siguen saliendo con atrás).
  bool _canInterceptBack() {
    if (_pickerOriginPoint != null) return true;
    return _activePlan != null && _didComputeRoute;
  }

  /// Reentra al modo de elegir destino conservando el origen ya confirmado
  /// (cambio 6): se limpia la ruta calculada pero no el punto de partida.
  void _resetToDestinationPick() {
    if (_pickerMode == MapPickerMode.destination) return;
    setState(() {
      _clearActivePlanState();
      _pickerMode = MapPickerMode.destination;
      _pickerDestinationPoint = null;
      _destinationController.clear();
      _markers.removeWhere(
        (m) => m.markerId == const MarkerId('picker-destination'),
      );
    });
  }

  /// Marcador de feedback para un punto confirmado con el pin (cambio 2).
  Marker _pickerMarker(String id, LatLng position, String title, double hue) {
    return Marker(
      markerId: MarkerId(id),
      position: position,
      icon: BitmapDescriptor.defaultMarkerWithHue(hue),
      infoWindow: InfoWindow(title: title),
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
                    _user != null ? Icons.person : Icons.person_outline,
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

/// Barra inferior del modo "elegir punto con el pin" (Hito 2).
///
/// Muestra el centro de la cámara en vivo (coordenadas) y el botón que
/// confirma el punto o —si ya es el destino— lanza el cálculo de la ruta. El
/// atajo "mi ubicación" es un FAB aparte que solo mueve la cámara (cambio 3).
/// Mientras el motor calcula, un overlay a pantalla completa ( [_ComputingOverlay])
/// reemplaza esta barra.
class _PickPointBar extends StatelessWidget {
  const _PickPointBar({
    required this.mode,
    required this.coordinates,
    required this.onConfirm,
  });

  final MapPickerMode mode;
  final ValueNotifier<LatLng?> coordinates;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isOrigin = mode == MapPickerMode.origin;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 8,
      shadowColor: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isOrigin ? Icons.my_location : Icons.flag_rounded,
                  size: 20,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isOrigin
                        ? 'Elige tu ubicación de partida'
                        : 'Elige tu destino',
                    style: text.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ValueListenableBuilder<LatLng?>(
              valueListenable: coordinates,
              builder: (BuildContext context, LatLng? target, Widget? _) {
                if (target == null) return const SizedBox.shrink();
                return Text(
                  '${target.latitude.toStringAsFixed(5)}, '
                  '${target.longitude.toStringAsFixed(5)}',
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onConfirm,
              icon: Icon(
                isOrigin ? Icons.arrow_forward_rounded : Icons.search,
                size: 18,
              ),
              label: Text(isOrigin ? 'Continuar' : 'Calcular ruta'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Overlay a pantalla completa mientras el motor calcula la mejor ruta.
///
/// Da feedback visible ("Calculando la mejor ruta…") y un botón para cancelar
/// que vuelve al pin a elegir los puntos. Se apoya en el estado
/// `isComputing` del planificador: al cancelar, el controlador vuelve a idle y
/// este overlay desaparece solo.
class _ComputingOverlay extends StatelessWidget {
  const _ComputingOverlay({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          elevation: 8,
          shadowColor: Colors.black,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Calculando la mejor ruta…',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Comparando estaciones y transbordos posibles',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón flotante "mi ubicación", en tema oscuro.///
/// Vive en dos sitios según el contexto:
/// · sin plan activo, como `floatingActionButton` del `Scaffold` (posicionado
///   automáticamente sobre la barra de navegación);
/// · con plan activo, dentro de la columna inferior, encima de "Iniciar Viaje",
///   para no tapar la barra sin importar su altura.
class _MyLocationFab extends StatelessWidget {
  const _MyLocationFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FloatingActionButton(
    onPressed: onPressed,
    backgroundColor: AppColors.surface,
    foregroundColor: AppColors.accent,
    elevation: 6,
    highlightElevation: 3,
    shape: const CircleBorder(side: BorderSide(color: AppColors.borderStrong)),
    child: const Icon(Icons.my_location),
  );
}

/// Barra inferior estilo Google Maps: resumen de la ruta + botón
/// "Iniciar Viaje". Solo aparece cuando hay un plan activo en el mapa.
class _StartTripBar extends StatelessWidget {
  const _StartTripBar({required this.plan, required this.onStart});

  final TripPlan plan;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String transfers = plan.transferCount == 0
        ? 'Directo'
        : '${plan.transferCount} transbordo${plan.transferCount == 1 ? '' : 's'}';

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 8,
      shadowColor: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.alt_route_rounded,
                  size: 20,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        plan.originName,
                        style: text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        plan.destinationName,
                        style: text.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${Fmt.distance(plan.totalDistanceMeters)} · '
              '${Fmt.money(plan.totalFareDop)} · $transfers',
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Iniciar Viaje'),
            ),
          ],
        ),
      ),
    );
  }
}
