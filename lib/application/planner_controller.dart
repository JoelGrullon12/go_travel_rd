import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/geo/geo_point.dart';
import '../domain/models/trip_plan.dart';
import '../domain/routing/route_engine.dart';
import '../models/route.dart';
import 'data_providers.dart';

/// Estado del planificador A→B: el plan calculado (si lo hay), si está
/// calculando, y el motivo de fallo (si falló).
class PlannerState {
  const PlannerState({this.plan, this.isComputing = false, this.failure});

  final TripPlan? plan;
  final bool isComputing;
  final RoutePlanFailure? failure;
}

/// Argumentos del cálculo A→B. Record posicional: `compute()` pasa el mensaje
/// como un solo argumento al callback del aislado.
typedef _PlanRequest = ({
  GeoPoint origin,
  GeoPoint destination,
  List<Route> routes,
  double maxWalkMeters,
});

/// Punto de entrada para `compute()`: el motor corre fuera del hilo de UI
/// (aislado de fondo en Android/iOS; en web y en tests Flutter lo ejecuta en
/// el mismo hilo de forma síncrona, y el motor ya es instantáneo ahí).
///
/// Debe ser una función top-level: `compute` la copia a otro aislado.
RoutePlanOutcome _planInIsolate(_PlanRequest request) {
  return const RouteEngine().plan(
    origin: request.origin,
    destination: request.destination,
    routes: request.routes,
    maxWalkMeters: request.maxWalkMeters,
  );
}

/// Planificador A→B (Hito 2): junta rutas de Firestore + preferencia de
/// distancia a pie del usuario y delega el cálculo al [RouteEngine], en un
/// aislado de fondo para no congelar la UI.
class PlannerController extends Notifier<PlannerState> {
  /// Token de generación: cada [plan] (o [cancel]) lo incrementa. Un cálculo
  /// que ya fue superado por otro —o cancelado— descarta su resultado.
  int _requestId = 0;

  @override
  PlannerState build() => const PlannerState();

  Future<void> plan({
    required GeoPoint origin,
    required GeoPoint destination,
    bool overrideMaxWalk = false,
  }) async {
    final int requestId = ++_requestId;
    state = const PlannerState(isComputing: true);

    // Duración mínima visible del estado "calculando": garantiza que el
    // overlay renderice y el botón cancelar tenga una ventana real, incluso
    // cuando el motor termina en milisegundos.
    final Future<void> minVisible = Future<void>.delayed(
      const Duration(milliseconds: 300),
    );

    try {
      final List<Route> routes = await ref.read(routesProvider.future);

      if (!overrideMaxWalk) {
        final double maxWalk = await ref.read(maxWalkDistanceProvider.future);
        final RoutePlanOutcome outcome = await compute(
          _planInIsolate,
          (
            origin: origin,
            destination: destination,
            routes: routes,
            maxWalkMeters: maxWalk,
          ),
        );
        await minVisible;
        if (requestId != _requestId) return;
        state = PlannerState(plan: outcome.plan, failure: outcome.failure);
        return;
      }

      // Con override, la distancia a pie deja de ser un límite del usuario y se
      // calcula en dos fases: primero con un tope acotado (5 km) y, solo si ni
      // así hay estaciones alcanzables, con distancia infinita. Así el caso
      // común se mantiene liviano y la expansión total queda para puntos remotos.
      //
      // Fase 1: tope acotado.
      RoutePlanOutcome outcome = await compute(
        _planInIsolate,
        (
          origin: origin,
          destination: destination,
          routes: routes,
          maxWalkMeters: kOverrideWalkCapMeters,
        ),
      );
      await minVisible;
      if (requestId != _requestId) return;

      // Fase 2: solo si la fase 1 falló por distancia. Un noRoute de la fase 1
      // no se reintenta: una estación lejana no conecta redes disconectadas.
      if (outcome.failure case RoutePlanFailure.noStationsNearOrigin ||
          RoutePlanFailure.noStationsNearDestination) {
        outcome = await compute(
          _planInIsolate,
          (
            origin: origin,
            destination: destination,
            routes: routes,
            maxWalkMeters: double.infinity,
          ),
        );
      }
      state = PlannerState(plan: outcome.plan, failure: outcome.failure);
    } catch (_) {
      // Firestore sin conexión, índice pendiente, etc.: se muestra como un
      // fallo genérico "no se encontró una ruta" en lugar de crashear.
      if (requestId != _requestId) return;
      state = const PlannerState(failure: RoutePlanFailure.noRoute);
    }
  }

  /// Cancela el cálculo en curso: se descarta el resultado pendiente y el
  /// planificador vuelve a idle (el pin del mapa queda para re-elegir).
  void cancel() {
    _requestId++;
    state = const PlannerState();
  }

  void clear() => state = const PlannerState();
}

final NotifierProvider<PlannerController, PlannerState>
    plannerControllerProvider = NotifierProvider<PlannerController, PlannerState>(
  PlannerController.new,
);
