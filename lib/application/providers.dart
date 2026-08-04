import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/fixtures/demo_trip_plans.dart';
import '../domain/models/trip_plan.dart';
import 'live_trip_controller.dart';

/// Fuente de planes de viaje.
///
/// ── ÚNICA COSTURA CON EL HITO 2 ───────────────────────────────────────────
/// Hoy devuelve planes de ejemplo. Cuando el motor de cálculo A→B esté listo,
/// se sobreescribe este provider (o se cambia su cuerpo) para que devuelva lo
/// que calcule el motor. Ningún widget ni el motor de seguimiento se enteran:
/// ambos solo conocen [TripPlan].
///
/// ```dart
/// final tripPlansProvider = Provider<List<TripPlan>>((ref) {
///   return ref.watch(routeEngineProvider).lastResults;   // Hito 2
/// });
/// ```
/// ──────────────────────────────────────────────────────────────────────────
final Provider<List<TripPlan>> tripPlansProvider =
    Provider<List<TripPlan>>((ref) => DemoTripPlans.all());

/// Busca un plan por id. Lanza si no existe: un id inválido es un bug de
/// navegación, no un estado que la UI deba manejar.
final ProviderFamily<TripPlan, String> tripPlanProvider =
    Provider.family<TripPlan, String>((ref, String planId) {
  return ref.watch(tripPlansProvider).firstWhere(
        (TripPlan plan) => plan.id == planId,
        orElse: () => throw StateError('No existe el plan de viaje "$planId"'),
      );
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
