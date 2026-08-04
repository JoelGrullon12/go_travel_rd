import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/motion.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/models/trip_plan.dart';
import '../../../domain/models/trip_progress.dart';

/// Pantalla de llegada.
///
/// Contenida a propósito: sin confeti ni celebración. El usuario acaba de
/// bajarse de una guagua y quiere confirmar que llegó y cerrar. Lo que sí hace
/// es **cerrar el ciclo**: dice cuánto duró y cuánto costó, que es la
/// información que uno busca justo al terminar.
class ArrivalOverlay extends StatelessWidget {
  const ArrivalOverlay({
    super.key,
    required this.progress,
    required this.elapsed,
    required this.onClose,
    required this.onRestart,
  });

  final TripProgress progress;
  final Duration elapsed;
  final VoidCallback onClose;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final TripPlan plan = progress.plan;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Motion.adapt(context, Motion.large),
      curve: Motion.enter,
      builder: (BuildContext context, double t, Widget? child) => Opacity(
        opacity: t,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18 * t, sigmaY: 18 * t),
          child: ColoredBox(
            color: AppColors.canvas.withValues(alpha: 0.72 * t),
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 28),
              child: child,
            ),
          ),
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(Spacing.xl),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: Radii.cardLg,
              border: Border.all(color: AppColors.border),
              boxShadow: Shadows.card,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: AppColors.accent, size: 28),
                ),
                const SizedBox(height: Spacing.lg),
                Text('Llegaste', style: text.displaySmall),
                const SizedBox(height: Spacing.xs),
                Text(
                  plan.destinationName,
                  style:
                      text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: Spacing.xl),
                Row(
                  children: <Widget>[
                    _Stat(label: 'Duración', value: Fmt.duration(elapsed)),
                    const SizedBox(width: Spacing.xl),
                    _Stat(
                      label: 'Recorrido',
                      value: Fmt.distance(progress.totalMeters),
                    ),
                    const SizedBox(width: Spacing.xl),
                    _Stat(label: 'Costo', value: Fmt.money(plan.totalFareDop)),
                  ],
                ),
                const SizedBox(height: Spacing.xl),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onRestart,
                        child: const Text('Repetir'),
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: FilledButton(
                        onPressed: onClose,
                        child: const Text('Listo'),
                      ),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
