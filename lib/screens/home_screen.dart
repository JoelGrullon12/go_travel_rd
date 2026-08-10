import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_travel_rd/application/data_providers.dart';
import 'package:go_travel_rd/core/theme/app_colors.dart';
import 'package:go_travel_rd/core/theme/app_theme.dart';
import 'package:go_travel_rd/core/utils/formatters.dart';
import 'package:go_travel_rd/domain/models/trip_plan.dart';
import 'package:go_travel_rd/models/user_route.dart';
import 'package:go_travel_rd/services/auth_service.dart';
import 'package:go_travel_rd/services/user_route_service.dart';
import 'package:go_travel_rd/widgets/search_box.dart';

import 'login_screen.dart';
import 'map_screen.dart';

/// Pantalla de entrada de la app (estilo Uber × Google Maps).
///
/// Arriba, el buscador de origen/destino; debajo, las rutas personalizadas
/// del usuario. Al tocar una ruta o al enviar origen/destino, se abre el mapa.
/// Iniciar el viaje se hace desde el mapa, con un botón tipo "Iniciar Viaje"
/// (ver [MapScreen]).
///
/// Sin sesión la lista se reemplaza por una invitación a registrarse: guardar
/// rutas personalizadas requiere estar identificado (Hito 5).
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

  void _openMap() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapScreen(
          initialOrigin: _originController.text,
          initialDestination: _destinationController.text,
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

  /// Abre el mapa con una ruta personalizada guardada: el mapa lanza el motor
  /// con su origen/destino y dibuja el plan recalculado.
  Future<void> _openSavedRoute(UserRoute route) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MapScreen(savedRoute: route)),
    );
    if (!mounted) return;
    ref.invalidate(userRoutesProvider);
  }

  /// Diálogo para cambiar el nombre de una ruta guardada (Hito 5). Al renombrar
  /// se borra la entrada con el nombre viejo (el CRUD deduplica por nombre) y
  /// se guarda la ruta con el nuevo.
  Future<void> _editRouteName(UserRoute route) async {
    final TextEditingController controller =
        TextEditingController(text: route.name);
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Editar nombre'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre de la ruta',
            hintText: 'Ej. Casa → Trabajo',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == route.name || !mounted) return;

    try {
      final UserRouteService service = UserRouteService();
      await service.deleteRoute(route.name);
      await service.saveRoute(route.copyWith(name: name));
      ref.invalidate(userRoutesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nombre actualizado')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo actualizar el nombre')),
      );
    }
  }

  /// Elimina una ruta guardada tras pedir confirmación.
  Future<void> _deleteRoute(UserRoute route) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Eliminar ruta'),
        content: Text('¿Eliminar "${route.name}"? Esta acción no se puede deshacer.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await UserRouteService().deleteRoute(route.name);
      ref.invalidate(userRoutesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ruta eliminada')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo eliminar la ruta')),
      );
    }
  }

  void _openRegister() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<List<UserRoute>> routes = ref.watch(userRoutesProvider);
    final TripPlan? finishedTrip = ref.watch(finishedTripProvider);

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
              ],
            ),
            const SizedBox(height: Spacing.xxl),

            // ── Viaje terminado ───────────────────────────────────────────
            if (finishedTrip != null) ...<Widget>[
              _FinishedTripCard(
                plan: finishedTrip,
                onClose: () {
                  ref.read(finishedTripProvider.notifier).state = null;
                },
              ),
              const SizedBox(height: Spacing.xxl),
            ],

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
            if (_user == null)
              _SignUpPrompt(onRegister: _openRegister)
            else
              routes.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(Spacing.lg),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (Object e, StackTrace _) => _EmptyFavorites(
                  message: 'No se pudieron cargar tus rutas. Inténtalo de nuevo.',
                ),
                data: (List<UserRoute> list) => list.isEmpty
                    ? _EmptyFavorites(
                        message:
                            'Aún no guardas rutas favoritas. Calcula una ruta '
                            'en el mapa y toca el botón de tres puntos para '
                            'guardarla.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (final UserRoute route in list)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: Spacing.md),
                              child: _UserRouteCard(
                                route: route,
                                onTap: () => _openSavedRoute(route),
                                onEditName: () => _editRouteName(route),
                                onDelete: () => _deleteRoute(route),
                              ),
                            ),
                        ],
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta "Viaje terminado": resumen del último viaje (origen, destino,
/// precio y distancia) con un botón para descartarla. Se muestra en la
/// pantalla principal cuando [finishedTripProvider] tiene un plan.
class _FinishedTripCard extends StatelessWidget {
  const _FinishedTripCard({required this.plan, required this.onClose});

  final TripPlan plan;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.cardLg,
        border: Border.all(color: AppColors.border),
        boxShadow: Shadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.check_circle_rounded,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: Spacing.sm),
              Text('Viaje terminado', style: text.titleMedium),
            ],
          ),
          const SizedBox(height: Spacing.md),
          _TripLine(icon: Icons.trip_origin, label: plan.originName),
          const SizedBox(height: Spacing.xs),
          _TripLine(
            icon: Icons.place_rounded,
            label: plan.destinationName,
            accent: true,
          ),
          const SizedBox(height: Spacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: _SummaryStat(
                  label: 'Precio',
                  value: Fmt.money(plan.totalFareDop),
                ),
              ),
              Expanded(
                child: _SummaryStat(
                  label: 'Distancia',
                  value: Fmt.distance(plan.totalDistanceMeters),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              onPressed: onClose,
              child: const Text('Cerrar'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila origen/destino de la tarjeta de viaje terminado.
class _TripLine extends StatelessWidget {
  const _TripLine({required this.icon, required this.label, this.accent = false});

  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final Color color = accent ? AppColors.accent : AppColors.textTertiary;
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: color),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Stat pequeño (etiqueta + valor) para la fila de precio/distancia.
class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: Spacing.xs),
          Text(value, style: AppTheme.numeric(19)),
        ],
      );
}

/// Invitación a registrarse cuando no hay sesión: guardar rutas requiere estar
/// identificado.
class _SignUpPrompt extends StatelessWidget {
  const _SignUpPrompt({required this.onRegister});

  final VoidCallback onRegister;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.bookmark_add_outlined,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  'Regístrate para guardar rutas personalizadas',
                  style: text.bodyMedium?.copyWith(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: onRegister,
              child: const Text('Registrarse'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado cuando el usuario tiene sesión pero todavía no guarda rutas.
class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites({required this.message});

  final String message;

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
              message,
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Acciones del menú de tres puntos de una ruta guardada.
enum _RouteCardAction { editName, delete }

/// Tarjeta de una ruta personalizada guardada: nombre, origen → destino y
/// acciones (editar nombre, eliminar). Tocar la tarjeta abre el mapa y
/// recalcula la ruta con el motor.
class _UserRouteCard extends StatelessWidget {
  const _UserRouteCard({
    required this.route,
    required this.onTap,
    required this.onEditName,
    required this.onDelete,
  });

  final UserRoute route;
  final VoidCallback onTap;
  final VoidCallback onEditName;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final GeoPoint start = route.startLocation;
    final GeoPoint finish = route.finishLocation;
    final String startLabel = _labelFor(route.startName, start);
    final String finishLabel = _labelFor(route.finishName, finish);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: Radii.cardLg,
          border: Border.all(color: AppColors.border),
          boxShadow: const <BoxShadow>[
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
              children: <Widget>[
                Expanded(
                  child: Text(route.name, style: text.titleLarge),
                ),
                PopupMenuButton<_RouteCardAction>(
                  onSelected: (action) => switch (action) {
                    _RouteCardAction.editName => onEditName(),
                    _RouteCardAction.delete => onDelete(),
                  },
                  icon: const Icon(Icons.more_vert,
                      size: 20, color: AppColors.textSecondary),
                  tooltip: 'Opciones de la ruta',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  itemBuilder: (BuildContext context) =>
                      const <PopupMenuEntry<_RouteCardAction>>[
                    PopupMenuItem<_RouteCardAction>(
                      value: _RouteCardAction.editName,
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.edit_outlined,
                              size: 18, color: AppColors.textPrimary),
                          SizedBox(width: 10),
                          Text('Editar nombre'),
                        ],
                      ),
                    ),
                    PopupMenuItem<_RouteCardAction>(
                      value: _RouteCardAction.delete,
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.delete_outline,
                              size: 18, color: AppColors.textPrimary),
                          SizedBox(width: 10),
                          Text('Eliminar'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              startLabel,
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: <Widget>[
                const Icon(Icons.south_rounded,
                    size: 14, color: AppColors.textTertiary),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    finishLabel,
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
    );
  }

  /// Nombre geocodificado del extremo si la ruta lo guardó; si no (rutas
  /// antiguas), las coordenadas.
  static String _labelFor(String name, GeoPoint point) {
    if (name.trim().isNotEmpty) return name;
    return '${point.latitude.toStringAsFixed(5)}, '
        '${point.longitude.toStringAsFixed(5)}';
  }
}
