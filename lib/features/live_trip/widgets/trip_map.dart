import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/motion.dart';
import '../../../domain/geo/geo_point.dart';
import '../../../domain/models/trip_plan.dart';
import '../../../domain/models/trip_progress.dart';
import '../../../domain/tracking/trip_geometry.dart';
import '../../shared/mode_visuals.dart';
import 'map_style.dart';

/// Mapa del viaje activo.
///
/// Dibuja tres capas, en este orden de importancia visual:
///   1. La ruta que **falta**, con el color de cada línea de transporte.
///   2. La ruta ya **recorrida**, apagada — el avance se lee sin leyenda.
///   3. La **posición** del usuario, que es lo único que se mueve.
///
/// La cámara sigue al usuario, pero se suelta en cuanto él toca el mapa: nada
/// más frustrante que intentar mirar adelante y que la vista te arrastre de
/// vuelta. Un botón explícito devuelve el seguimiento.
class TripMap extends StatefulWidget {
  const TripMap({
    super.key,
    required this.geometry,
    required this.progress,
    required this.followUser,
    required this.onUserPannedMap,
    this.bottomPadding = 0,
  });

  final TripGeometry geometry;
  final TripProgress? progress;
  final bool followUser;
  final VoidCallback onUserPannedMap;

  /// Espacio reservado abajo para la hoja: los controles de Google (logo,
  /// brújula) y el encuadre se corren hacia arriba en vez de quedar tapados.
  final double bottomPadding;

  @override
  State<TripMap> createState() => TripMapState();
}

class TripMapState extends State<TripMap> {
  final Completer<GoogleMapController> _controllerReady =
      Completer<GoogleMapController>();
  GoogleMapController? _controller;

  BitmapDescriptor? _userIcon;
  BitmapDescriptor? _stopIcon;
  BitmapDescriptor? _transferIcon;
  BitmapDescriptor? _endpointIcon;

  /// Guarda contra el falso positivo de "el usuario movió el mapa": las
  /// animaciones que dispara la propia app también emiten `onCameraMoveStarted`.
  bool _programmaticMove = false;
  DateTime _lastCameraUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  GeoPoint? _lastCameraTarget;

  @override
  void initState() {
    super.initState();
    _buildIcons();
  }

  @override
  void didUpdateWidget(TripMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.followUser && widget.progress != null) {
      _followCamera(widget.progress!);
    }
  }

  Future<void> _buildIcons() async {
    final BitmapDescriptor? user = await _circleBitmap(
      diameter: 46,
      fill: AppColors.accent,
      ring: Colors.white,
      ringWidth: 5,
    );
    final BitmapDescriptor? stop = await _circleBitmap(
      diameter: 22,
      fill: AppColors.canvas,
      ring: Colors.white70,
      ringWidth: 4,
    );
    final BitmapDescriptor? transfer = await _circleBitmap(
      diameter: 32,
      fill: Colors.white,
      ring: AppColors.canvas,
      ringWidth: 5,
    );
    final BitmapDescriptor? endpoint = await _circleBitmap(
      diameter: 30,
      fill: AppColors.canvas,
      ring: AppColors.accent,
      ringWidth: 6,
    );
    if (!mounted) return;
    setState(() {
      _userIcon = user;
      _stopIcon = stop;
      _transferIcon = transfer;
      _endpointIcon = endpoint;
    });
  }

  /// Dibuja un marcador circular en tiempo de ejecución.
  ///
  /// Se generan por código en vez de empaquetar PNGs: así los marcadores usan
  /// los colores reales del tema y de cada línea, y no hay que mantener nueve
  /// imágenes en tres densidades. Si el dibujado falla (algún navegador viejo),
  /// devuelve `null` y el mapa cae a los marcadores por defecto.
  Future<BitmapDescriptor?> _circleBitmap({
    required double diameter,
    required Color fill,
    required Color ring,
    required double ringWidth,
  }) async {
    try {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final double radius = diameter / 2;
      canvas.drawCircle(
        Offset(radius, radius),
        radius,
        Paint()..color = ring,
      );
      canvas.drawCircle(
        Offset(radius, radius),
        radius - ringWidth,
        Paint()..color = fill,
      );
      final ui.Image image = await recorder
          .endRecording()
          .toImage(diameter.ceil(), diameter.ceil());
      final ByteData? bytes =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return null;
      return BitmapDescriptor.bytes(bytes.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  Set<Polyline> _buildPolylines() {
    final TripPlan plan = widget.geometry.plan;
    final Set<Polyline> lines = <Polyline>{};

    for (int i = 0; i < plan.legs.length; i++) {
      final TripLeg leg = plan.legs[i];
      lines.add(
        Polyline(
          polylineId: PolylineId('leg-$i'),
          points: leg.path.map((GeoPoint p) => p.toLatLng).toList(),
          color: Color(leg.lineColorHex),
          width: leg.mode.isWalking ? 5 : 8,
          // Los tramos a pie van punteados: la distinción entre "caminas" y
          // "te montas" es la más importante del viaje.
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

    final TripProgress? progress = widget.progress;
    if (progress != null && progress.traveledMeters > 1) {
      lines.add(
        Polyline(
          polylineId: const PolylineId('traveled'),
          points: widget.geometry
              .sliceUpTo(progress.traveledMeters)
              .map((GeoPoint p) => p.toLatLng)
              .toList(),
          color: AppColors.trailDone,
          width: 8,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 2,
        ),
      );
    }
    return lines;
  }

  Set<Marker> _buildMarkers() {
    final TripPlan plan = widget.geometry.plan;
    final Set<Marker> markers = <Marker>{};

    for (final TripLeg leg in plan.legs) {
      for (final TripStop stop in leg.stops) {
        markers.add(
          Marker(
            markerId: MarkerId('stop-${leg.id}-${stop.id}'),
            position: stop.position.toLatLng,
            icon: (stop.isTransfer ? _transferIcon : _stopIcon) ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
            anchor: const Offset(0.5, 0.5),
            zIndexInt: 3,
            infoWindow: InfoWindow(
              title: stop.name,
              snippet: stop.isTransfer ? 'Transbordo · ${leg.shortLabel}' : leg.shortLabel,
            ),
          ),
        );
      }
    }

    markers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: plan.destination.toLatLng,
        icon: _endpointIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 4,
        infoWindow: InfoWindow(title: plan.destinationName, snippet: 'Destino'),
      ),
    );

    final TripProgress? progress = widget.progress;
    if (progress != null) {
      // Fuera de ruta mostramos la posición CRUDA, no la pegada a la línea:
      // pegarla ahí escondería justo el problema que hay que comunicar.
      final GeoPoint userPoint =
          progress.offRoute ? progress.rawPosition : progress.match.snapped;
      markers.add(
        Marker(
          markerId: const MarkerId('user'),
          position: userPoint.toLatLng,
          icon: _userIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          anchor: const Offset(0.5, 0.5),
          flat: true,
          zIndexInt: 10,
        ),
      );
    }
    return markers;
  }

  /// Mueve la cámara con el usuario, pero con freno.
  ///
  /// Sin límite, cada muestra del GPS (2–3 por segundo) dispararía una
  /// animación de cámara que corta a la anterior: el mapa "tiembla". Se anima
  /// solo si pasó tiempo suficiente Y el usuario se movió lo bastante como para
  /// que se note.
  Future<void> _followCamera(TripProgress progress) async {
    final GoogleMapController? controller = _controller;
    if (controller == null) return;

    final GeoPoint target =
        progress.offRoute ? progress.rawPosition : progress.match.snapped;
    final DateTime now = DateTime.now();
    final bool tooSoon =
        now.difference(_lastCameraUpdate) < const Duration(milliseconds: 850);
    final bool barelyMoved = _lastCameraTarget != null &&
        (target.lat - _lastCameraTarget!.lat).abs() < 0.00005 &&
        (target.lng - _lastCameraTarget!.lng).abs() < 0.00005;
    if (tooSoon || barelyMoved) return;

    _lastCameraUpdate = now;
    _lastCameraTarget = target;
    _programmaticMove = true;

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target.toLatLng,
          zoom: 16.2,
          // Inclinar la cámara y orientarla al rumbo convierte el mapa en una
          // vista "hacia adelante": lo que está arriba en pantalla es lo que
          // viene. Con reducir movimiento activo se deja plano y al norte.
          tilt: Motion.reduced(context) ? 0 : 45,
          bearing: Motion.reduced(context) ? 0 : (progress.headingDegrees ?? 0),
        ),
      ),
    );

    // Ventana en la que ignoramos `onCameraMoveStarted`: es nuestra animación.
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      _programmaticMove = false;
    });
  }

  /// Encuadra el viaje completo. Se usa al abrir la pantalla.
  Future<void> frameWholeTrip() async {
    final GoogleMapController? controller = _controller;
    if (controller == null) return;
    final List<GeoPoint> points = widget.geometry.points;
    if (points.isEmpty) return;

    double minLat = points.first.lat, maxLat = points.first.lat;
    double minLng = points.first.lng, maxLng = points.first.lng;
    for (final GeoPoint p in points) {
      minLat = p.lat < minLat ? p.lat : minLat;
      maxLat = p.lat > maxLat ? p.lat : maxLat;
      minLng = p.lng < minLng ? p.lng : minLng;
      maxLng = p.lng > maxLng ? p.lng : maxLng;
    }
    _programmaticMove = true;
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        64,
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      _programmaticMove = false;
    });
  }

  /// Vuelve a centrar en el usuario (botón "centrar").
  Future<void> recenter() async {
    final TripProgress? progress = widget.progress;
    if (progress == null) return;
    _lastCameraUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    _lastCameraTarget = null;
    await _followCamera(progress);
  }

  @override
  Widget build(BuildContext context) {
    final GeoPoint start = widget.geometry.plan.origin;
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: start.toLatLng, zoom: 14),
      style: kDarkMapStyle,
      polylines: _buildPolylines(),
      markers: _buildMarkers(),
      // El punto azul nativo está apagado: dibujamos el nuestro sobre la
      // posición **pegada a la ruta**, que es la que el motor considera real.
      // Tener dos puntos distintos en pantalla confundiría.
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      tiltGesturesEnabled: false,
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      onMapCreated: (GoogleMapController controller) {
        _controller = controller;
        if (!_controllerReady.isCompleted) _controllerReady.complete(controller);
        frameWholeTrip();
      },
      onCameraMoveStarted: () {
        if (!_programmaticMove && widget.followUser) widget.onUserPannedMap();
      },
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
