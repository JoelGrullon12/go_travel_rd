import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/live_trip_controller.dart';
import '../../application/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../domain/models/trip_instruction.dart';
import '../../domain/models/trip_progress.dart';
import 'widgets/arrival_overlay.dart';
import 'widgets/demo_controls.dart';
import 'widgets/instruction_card.dart';
import 'widgets/trip_map.dart';
import 'widgets/trip_sheet.dart';

/// Pantalla del viaje activo — el corazón del Hito 4.
///
/// Junta las dos mitades del hito: la **UI de viaje activo** (mapa que sigue al
/// usuario, tarjeta de instrucción, hoja con el detalle) y la **lógica de
/// emparejamiento de posición** que vive en `domain/tracking/`.
///
/// La pantalla no calcula nada. Escucha el estado, decide qué mostrar y cuándo
/// vibrar. Toda la matemática está probada aparte con `flutter test`.
class LiveTripScreen extends ConsumerStatefulWidget {
  const LiveTripScreen({super.key, required this.planId});

  final String planId;

  @override
  ConsumerState<LiveTripScreen> createState() => _LiveTripScreenState();
}

class _LiveTripScreenState extends ConsumerState<LiveTripScreen> {
  final GlobalKey<TripMapState> _mapKey = GlobalKey<TripMapState>();
  bool _followUser = true;
  bool _arrivalDismissed = false;
  DateTime? _startedAt;

  static const double _sheetMin = 0.16;
  static const double _sheetInitial = 0.34;
  static const double _sheetMax = 0.88;

  @override
  void initState() {
    super.initState();
    // `addPostFrameCallback` porque `start()` modifica un provider y hacerlo
    // durante el primer build lanza en Riverpod.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startedAt = DateTime.now();
      ref.read(liveTripControllerProvider(widget.planId).notifier).start();
    });
  }

  /// Realimentación háptica: solo cuando la instrucción **cambia**, y con
  /// intensidad proporcional a la urgencia.
  ///
  /// Es la parte de la app que funciona con el teléfono en el bolsillo. Vibrar
  /// en cada muestra del GPS entrenaría al usuario a ignorarla, que es
  /// exactamente lo contrario de lo que buscamos.
  void _feedback(TripProgress progress) {
    if (!progress.isNewInstruction) return;
    switch (progress.instruction.urgency) {
      case InstructionUrgency.critical:
        HapticFeedback.heavyImpact();
      case InstructionUrgency.headsUp:
        HapticFeedback.mediumImpact();
      case InstructionUrgency.calm:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final LiveTripState state =
        ref.watch(liveTripControllerProvider(widget.planId));
    final LiveTripController controller =
        ref.read(liveTripControllerProvider(widget.planId).notifier);

    ref.listen<LiveTripState>(
      liveTripControllerProvider(widget.planId),
      (LiveTripState? previous, LiveTripState next) {
        final TripProgress? progress = next.progress;
        if (progress != null) _feedback(progress);
      },
    );

    final TripProgress? progress = state.progress;
    final double screenHeight = MediaQuery.sizeOf(context).height;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: TripMap(
              key: _mapKey,
              geometry: controller.tracker.geometry,
              progress: progress,
              followUser: _followUser,
              bottomPadding: screenHeight * _sheetMin,
              onUserPannedMap: () {
                if (_followUser) setState(() => _followUser = false);
              },
            ),
          ),

          // Velo superior: el mapa detrás de la tarjeta se oscurece un poco
          // para que el texto se lea siempre, pase por encima lo que pase.
          IgnorePointer(
            child: Container(
              height: 260,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0xB3080B14), Color(0x00080B14)],
                ),
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _TopBar(state: state, onBack: () => Navigator.of(context).pop()),
                  const SizedBox(height: Spacing.md),
                  if (state.status == TripStatus.error)
                    _ErrorCard(
                      message: state.errorMessage ?? 'Error desconocido',
                      canRetry: state.canRetry,
                      onRetry: () => controller.start(),
                      onUseSimulator: () =>
                          controller.start(mode: LocationMode.simulated),
                    )
                  else if (progress != null)
                    InstructionCard(instruction: progress.instruction)
                  else
                    const _ConnectingCard(),
                ],
              ),
            ),
          ),

          if (!_followUser && progress != null)
            Positioned(
              right: Spacing.lg,
              bottom: screenHeight * _sheetMin + Spacing.lg,
              child: _RecenterButton(
                onTap: () {
                  setState(() => _followUser = true);
                  _mapKey.currentState?.recenter();
                },
              ),
            ),

          DraggableScrollableSheet(
            initialChildSize: _sheetInitial,
            minChildSize: _sheetMin,
            maxChildSize: _sheetMax,
            snap: true,
            snapSizes: const <double>[_sheetMin, _sheetInitial, _sheetMax],
            builder: (BuildContext context, ScrollController scrollController) =>
                TripSheet(
              scrollController: scrollController,
              geometry: controller.tracker.geometry,
              progress: progress,
              onEndTrip: () async {
                await controller.stop();
                if (context.mounted) Navigator.of(context).pop();
              },
              demoControls: state.isSimulated
                  ? DemoControls(
                      speed: state.simulationSpeed,
                      isPaused: state.status == TripStatus.paused,
                      isDeviating: state.simulatedDeviationMeters > 0,
                      onSpeedChanged: controller.setSimulationSpeed,
                      onPauseToggled: () =>
                          state.status == TripStatus.paused
                              ? controller.resume()
                              : controller.pause(),
                      onDeviationToggled: (bool on) =>
                          controller.setSimulatedDeviation(on ? 220 : 0),
                      onRestart: () {
                        setState(() {
                          _arrivalDismissed = false;
                          _startedAt = DateTime.now();
                        });
                        controller.restart();
                      },
                      onSkipToEnd: () => controller.seekToFraction(0.985),
                    )
                  : _DemoModeButton(
                      onPressed: () => controller.start(
                        mode: LocationMode.simulated,
                      ),
                    ),
            ),
          ),

          if (progress != null && progress.hasArrived && !_arrivalDismissed)
            Positioned.fill(
              child: ArrivalOverlay(
                progress: progress,
                elapsed: DateTime.now()
                    .difference(_startedAt ?? DateTime.now()),
                onClose: () async {
                  await controller.stop();
                  if (context.mounted) Navigator.of(context).pop();
                },
                onRestart: () {
                  setState(() {
                    _arrivalDismissed = false;
                    _startedAt = DateTime.now();
                  });
                  controller.restart();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state, required this.onBack});

  final LiveTripState state;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        _GlassIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Volver',
          onTap: onBack,
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Viaje en curso',
                style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
              Text(
                '${state.plan.originName} → ${state.plan.destinationName}',
                style: text.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (state.isSimulated) const _SimulatedBadge(),
      ],
    );
  }
}

/// Marca visible de que la posición es simulada.
///
/// Es una cuestión de honestidad: en una demo hay que poder distinguir a
/// simple vista lo que se está midiendo de verdad de lo que se está actuando.
class _SimulatedBadge extends StatelessWidget {
  const _SimulatedBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.xs),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.14),
          borderRadius: Radii.cardSm,
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Text(
          'SIMULADO',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.warning),
        ),
      );
}

/// Botón para pasar el viaje activo al modo demo (posición simulada).
///
/// Vive en el mismo sitio donde antes siempre aparecían los controles de la
/// simulación: en el viaje con GPS real es un solo botón, y al pulsarlo se
/// activa el simulador con todos sus controles y el badge SIMULADO.
class _DemoModeButton extends StatelessWidget {
  const _DemoModeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: Radii.cardMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.science_outlined,
                  size: 16, color: AppColors.textTertiary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'MODO DEMO',
                  style:
                      text.labelSmall?.copyWith(color: AppColors.textTertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Text(
            '¿Sin señal o en un simulador? Activa el modo demo para recorrer '
            'la ruta con una posición simulada.',
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: Spacing.md),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Hacer viaje en modo demo'),
          ),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: AppColors.surfaceGlass,
          shape: const CircleBorder(
            side: BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 20, color: AppColors.textPrimary),
            ),
          ),
        ),
      );
}

class _RecenterButton extends StatelessWidget {
  const _RecenterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.85, end: 1),
        duration: Motion.adapt(context, Motion.standard),
        curve: Motion.overshoot,
        builder: (BuildContext context, double scale, Widget? child) =>
            Transform.scale(scale: scale, child: child),
        child: Semantics(
          button: true,
          label: 'Centrar el mapa en mi posición',
          child: Material(
            color: AppColors.surface,
            shape: const StadiumBorder(
              side: BorderSide(color: AppColors.borderStrong),
            ),
            elevation: 8,
            shadowColor: Colors.black,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: const Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: Spacing.lg, vertical: Spacing.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.my_location_rounded,
                        size: 18, color: AppColors.accent),
                    SizedBox(width: Spacing.sm),
                    Text('Centrar'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _ConnectingCard extends StatelessWidget {
  const _ConnectingCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceGlass,
          borderRadius: Radii.cardLg,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: Spacing.lg),
            Expanded(
              child: Text(
                'Buscando tu posición…',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      );
}

/// Error de ubicación con salida.
///
/// Nunca deja al usuario en un callejón: si el GPS falla, ofrece seguir con el
/// simulador en vez de dejar la pantalla muerta.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.canRetry,
    required this.onRetry,
    required this.onUseSimulator,
  });

  final String message;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback onUseSimulator;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceGlass,
        borderRadius: Radii.cardLg,
        border: Border.all(color: AppColors.critical.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.location_disabled_rounded,
                  color: AppColors.critical, size: 22),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text('No podemos seguirte', style: text.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            message,
            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: Spacing.lg),
          Row(
            children: <Widget>[
              if (canRetry)
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRetry,
                    child: const Text('Reintentar'),
                  ),
                ),
              if (canRetry) const SizedBox(width: Spacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: onUseSimulator,
                  child: const Text('Usar simulador'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
