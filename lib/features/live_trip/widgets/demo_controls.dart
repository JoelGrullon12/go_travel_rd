import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/motion.dart';

/// Controles del simulador de viaje.
///
/// Van dentro de la hoja, marcados como "modo demo" y visualmente distintos del
/// resto: nadie debe confundir un control de demostración con una función de la
/// app. Existen porque el seguimiento en tiempo real no se puede enseñar de
/// otra forma en un salón de clases — ni probar sin gastar un viaje real por
/// cada corrida.
class DemoControls extends StatelessWidget {
  const DemoControls({
    super.key,
    required this.speed,
    required this.isPaused,
    required this.isDeviating,
    required this.onSpeedChanged,
    required this.onPauseToggled,
    required this.onDeviationToggled,
    required this.onRestart,
    required this.onSkipToEnd,
  });

  final double speed;
  final bool isPaused;
  final bool isDeviating;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onPauseToggled;
  final ValueChanged<bool> onDeviationToggled;
  final VoidCallback onRestart;
  final VoidCallback onSkipToEnd;

  static const List<double> _speeds = <double>[1, 4, 10, 25];

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.science_outlined,
                  size: 16, color: AppColors.textTertiary),
              const SizedBox(width: Spacing.sm),
              Text(
                'MODO DEMO · POSICIÓN SIMULADA',
                style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Velocidad de la simulación',
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: <Widget>[
              for (final double value in _speeds) ...<Widget>[
                Expanded(
                  child: _SpeedChip(
                    label: '${value.toStringAsFixed(0)}×',
                    selected: speed == value,
                    onTap: () => onSpeedChanged(value),
                  ),
                ),
                if (value != _speeds.last) const SizedBox(width: Spacing.sm),
              ],
            ],
          ),
          const SizedBox(height: Spacing.lg),
          SwitchListTile.adaptive(
            value: isDeviating,
            onChanged: onDeviationToggled,
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeThumbColor: AppColors.critical,
            title: Text('Salirme de la ruta', style: text.bodyMedium),
            subtitle: Text(
              'Desvía la posición 220 m para probar la alerta',
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPauseToggled,
                  icon: Icon(
                    isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 18,
                  ),
                  label: Text(isPaused ? 'Seguir' : 'Pausar'),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text('Reiniciar'),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSkipToEnd,
                  icon: const Icon(Icons.fast_forward_rounded, size: 18),
                  label: const Text('Al final'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: 'Velocidad $label',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.adapt(context, Motion.quick),
            curve: Motion.smooth,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: Radii.cardSm,
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.border,
              ),
            ),
            child: Text(
              label,
              style: AppTheme.numeric(
                15,
                color: selected ? AppColors.accent : AppColors.textSecondary,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
}
