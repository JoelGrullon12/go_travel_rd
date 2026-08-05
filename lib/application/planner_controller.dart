import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/geo/geo_point.dart';
import '../domain/models/trip_plan.dart';
import '../domain/routing/route_engine.dart';
import '../models/route.dart';
import 'data_providers.dart';

/// Estado del planificador A→B: el plan calculado (si lo hay), si está
/// calculando, y el motivo de fallo (si falló).
class PlannerState {
  const PlannerState({
    this.plan,
    this.isComputing = false,
    this.failure,
  });

  final TripPlan? plan;
  final bool isComputing;
  final RoutePlanFailure? failure;
}

/// Planificador A→B (Hito 2): junta rutas de Firestore + preferencia de
/// distancia a pie del usuario y delega el cálculo al [RouteEngine].
class PlannerController extends Notifier<PlannerState> {
  @override
  PlannerState build() => const PlannerState();

  Future<void> plan({
    required GeoPoint origin,
    required GeoPoint destination,
  }) async {
    state = const PlannerState(isComputing: true);
    try {
      final List<Route> routes = await ref.read(routesProvider.future);
      final double maxWalk = await ref.read(maxWalkDistanceProvider.future);
      final RoutePlanOutcome outcome = const RouteEngine().plan(
        origin: origin,
        destination: destination,
        routes: routes,
        maxWalkMeters: maxWalk,
      );
      state = PlannerState(plan: outcome.plan, failure: outcome.failure);
    } catch (_) {
      // Firestore sin conexión, índice pendiente, etc.: se muestra como un
      // fallo genérico "no se encontró una ruta" en lugar de crashear.
      state = const PlannerState(failure: RoutePlanFailure.noRoute);
    }
  }

  void clear() => state = const PlannerState();
}

final NotifierProvider<PlannerController, PlannerState>
    plannerControllerProvider =
    NotifierProvider<PlannerController, PlannerState>(PlannerController.new);
