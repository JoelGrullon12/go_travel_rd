import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_travel_rd/application/providers.dart';
import 'package:go_travel_rd/core/theme/app_colors.dart';
import 'package:go_travel_rd/core/theme/app_theme.dart';
import 'package:go_travel_rd/core/utils/formatters.dart';
import 'package:go_travel_rd/domain/models/trip_plan.dart';
import 'package:go_travel_rd/features/shared/mode_visuals.dart';
import 'package:go_travel_rd/services/auth_service.dart';
import 'package:go_travel_rd/widgets/search_box.dart';

import 'login_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';

/// Pantalla de entrada de la app (estilo Uber × Google Maps).
///
/// Arriba, el buscador de origen/destino; debajo, la lista de rutas
/// favoritas del usuario. Al tocar una ruta o al enviar origen/destino,
/// se abre el mapa. Iniciar el viaje se hace desde el mapa, con un botón
/// tipo "Iniciar Viaje" (ver [MapScreen]).
///
/// Mientras el Hito 5 (favoritos en Firestore) no exista, la lista muestra
/// los trayectos de prueba del Hito 4 con una marca DEMO. Cuando haya
/// favoritos guardados, esta lista se llena desde `usuarios/{uid}/favoritos`
/// y las tarjetas demo desaparecen.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _authService = AuthService();
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = _authService.currentUser;
    _authService.authStateChanges.listen((user) {
      if (mounted) setState(() => _user = user);
    });
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _openMap({TripPlan? plan}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapScreen(
          plan: plan,
          initialOrigin: plan?.originName ?? _originController.text,
          initialDestination:
              plan?.destinationName ?? _destinationController.text,
        ),
      ),
    );
  }

  /// Abre el mapa en modo "elegir punto con el pin" (Hito 2).
  void _openPicker(MapPickerMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapScreen(
          pickerMode: mode,
          initialOrigin: _originController.text,
          initialDestination: _destinationController.text,
        ),
      ),
    );
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _user != null ? const ProfileScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<TripPlan> plans = ref.watch(tripPlansProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              Spacing.xl, Spacing.xl, Spacing.xl, Spacing.xxxl),
          children: <Widget>[
            // ── Encabezado: logo + perfil ──────────────────────────────────
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.16),
                    borderRadius: Radii.cardSm,
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Icon(Icons.navigation_rounded,
                      color: AppColors.accent, size: 20),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    'GoTravel RD',
                    style: text.titleLarge?.copyWith(letterSpacing: -0.3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildProfileAvatar(),
              ],
            ),
            const SizedBox(height: Spacing.xxl),

            // ── Buscador de origen / destino ──────────────────────────────
            // Los campos abren el mapa para marcar el punto con el pin; el
            // teclado no interviene en la elección.
            SearchBox(
              originController: _originController,
              destinationController: _destinationController,
              readOnly: true,
              onOriginSubmitted: (_) => _openMap(),
              onDestinationSubmitted: (_) => _openMap(),
              onOriginTap: () => _openPicker(MapPickerMode.origin),
              onDestinationTap: () => _openPicker(MapPickerMode.destination),
            ),
            const SizedBox(height: Spacing.md),

            // ── Ver todas las estaciones en el mapa ───────────────────────
            OutlinedButton.icon(
              onPressed: _openMap,
              icon: const Icon(Icons.map_rounded, size: 18),
              label: const Text('Ver Mapa'),
            ),
            const SizedBox(height: Spacing.xxl),

            // ── Rutas favoritas ────────────────────────────────────────────
            Row(
              children: <Widget>[
                const Icon(Icons.star_rounded, size: 16, color: AppColors.warning),
                const SizedBox(width: Spacing.sm),
                Text(
                  'TUS RUTAS FAVORITAS',
                  style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Toca una ruta para verla en el mapa y desde ahí iniciar el viaje.',
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: Spacing.md),
            if (plans.isEmpty)
              _EmptyFavorites()
            else
              for (final TripPlan plan in plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.md),
                  child: _PlanCard(
                    plan: plan,
                    onTap: () => _openMap(plan: plan),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileAvatar() {
    return Material(
      color: AppColors.surfaceHigh,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.borderStrong),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _openProfile,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.accentDim,
            backgroundImage: _user?.photoURL != null
                ? NetworkImage(_user!.photoURL!)
                : null,
            child: _user?.photoURL == null
                ? Icon(
                    _user != null ? Icons.person : Icons.person_outline,
                    size: 20,
                    color: AppColors.textPrimary,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// Estado cuando todavía no hay rutas (favoritos del Hito 5 pendientes).
class _EmptyFavorites extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.cardMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.textTertiary),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              'Aún no guardas rutas favoritas. Cuando el Hito 5 esté listo, '
              'las verás aquí.',
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de una ruta: origen → destino, tramos, distancia, tarifa y
/// transbordos. Es un solo botón para que el lector de pantalla anuncie una
/// frase útil en lugar de siete fragmentos sueltos.
class _PlanCard extends StatefulWidget {
  const _PlanCard({required this.plan, required this.onTap});

  final TripPlan plan;
  final VoidCallback onTap;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final TripPlan plan = widget.plan;

    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      label: 'Ver viaje de ${plan.originName} a ${plan.destinationName}',
      value: '${Fmt.distance(plan.totalDistanceMeters)}, '
          '${Fmt.money(plan.totalFareDop)}'
          '${plan.transferCount > 0 ? ', ${plan.transferCount} transbordo'
              '${plan.transferCount == 1 ? '' : 's'}' : ''}',
      onTap: widget.onTap,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.978 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: Radii.cardLg,
              border: Border.all(color: AppColors.border),
              boxShadow: _pressed
                  ? null
                  : const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(plan.originName, style: text.titleLarge),
                          const SizedBox(height: 2),
                          Row(
                            children: <Widget>[
                              const Icon(Icons.south_rounded,
                                  size: 14, color: AppColors.textTertiary),
                              const SizedBox(width: Spacing.sm),
                              Expanded(
                                child: Text(
                                  plan.destinationName,
                                  style: text.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _DemoBadge(),
                  ],
                ),
                const SizedBox(height: Spacing.lg),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    for (int i = 0; i < plan.legs.length; i++) ...<Widget>[
                      _LegChip(leg: plan.legs[i]),
                      if (i != plan.legs.length - 1)
                        const Icon(Icons.chevron_right_rounded,
                            size: 14, color: AppColors.textTertiary),
                    ],
                  ],
                ),
                const SizedBox(height: Spacing.lg),
                Wrap(
                  spacing: Spacing.md,
                  runSpacing: Spacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      Fmt.distance(plan.totalDistanceMeters),
                      style: AppTheme.numeric(15,
                          color: AppColors.textSecondary,
                          weight: FontWeight.w500),
                    ),
                    Text(
                      Fmt.money(plan.totalFareDop),
                      style: AppTheme.numeric(15,
                          color: AppColors.textSecondary,
                          weight: FontWeight.w500),
                    ),
                    if (plan.transferCount > 0)
                      Text(
                        plan.transferCount == 1
                            ? '1 transbordo'
                            : '${plan.transferCount} transbordos',
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.xs),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.14),
          borderRadius: Radii.cardSm,
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Text(
          'DEMO',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.warning),
        ),
      );
}

class _LegChip extends StatelessWidget {
  const _LegChip({required this.leg});

  final TripLeg leg;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(leg.lineColorHex);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: Radii.cardSm,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(iconForMode(leg.mode), size: 13, color: color),
          if (!leg.mode.isWalking) ...<Widget>[
            const SizedBox(width: Spacing.xs),
            Text(
              leg.lineName.replaceFirst('Metro ', ''),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color, letterSpacing: 0.2),
            ),
          ],
        ],
      ),
    );
  }
}
