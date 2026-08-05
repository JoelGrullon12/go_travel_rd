import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/trip_plan.dart';
import 'live_trip_controller.dart';
import 'planner_controller.dart';

/// Fuente de planes de viaje.
///
/// ── SEAM DEL HITO 2 ────────────────────────────────────────────────────────
/// Hoy devuelve una lista vacía: todos los planes llegan del motor A→B
/// ([plannerControllerProvider]) o de rutas personalizadas que se recalculan
/// con el motor al abrirse (Hito 5). Ningún widget ni el motor de seguimiento
/// se enteran: ambos solo conocen [TripPlan].
///
/// ```dart
/// final tripPlansProvider = Provider<List<TripPlan>>((ref) {
///   return ref.watch(routeEngineProvider).lastResults;   // Hito 2
/// });
/// ```
/// ──────────────────────────────────────────────────────────────────────────
final Provider<List<TripPlan>> tripPlansProvider =
    Provider<List<TripPlan>>((ref) => const <TripPlan>[]);

/// Busca un plan por id. Lanza si no existe: un id inválido es un bug de
/// navegación, no un estado que la UI deba manejar.
///
/// Orden de búsqueda:
/// 1. Planes conocidos ([tripPlansProvider]) — hoy vacío; el Hito 5 podría
///    llenarlo con rutas guardadas si se decide serializarlas.
/// 2. Plan calculado por el motor A→B ([plannerControllerProvider]) — así el
///    viaje activo puede arrancar desde un plan recién calculado en el mapa o
///    desde una ruta personalizada recalculada al abrirla.
final ProviderFamily<TripPlan, String> tripPlanProvider =
    Provider.family<TripPlan, String>((ref, String planId) {
  final List<TripPlan> known = ref.watch(tripPlansProvider);
  for (final TripPlan plan in known) {
    if (plan.id == planId) return plan;
  }
  final TripPlan? computed = ref.watch(plannerControllerProvider).plan;
  if (computed != null && computed.id == planId) return computed;
  throw StateError('No existe el plan de viaje "$planId"');
});

/// Controlador del viaje activo, uno por plan.
///
/// `autoDispose` para que al salir de la pantalla se cierre el stream del GPS:
/// dejarlo vivo es la forma más rápida de fundir la batería del usuario.
final AutoDisposeStateNotifierProviderFamily<LiveTripController, LiveTripState,
        String> liveTripControllerProvider =
    StateNotifierProvider.autoDispose
        .family<LiveTripController, LiveTripState, String>((ref, String planId) {
  return LiveTripController(ref.watch(tripPlanProvider(planId)));
});
