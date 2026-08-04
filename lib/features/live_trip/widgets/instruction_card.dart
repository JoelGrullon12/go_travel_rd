import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/motion.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/models/trip_instruction.dart';
import '../../shared/mode_visuals.dart';

/// La tarjeta de instrucción: el elemento más importante de la pantalla.
///
/// Todo lo demás en el viaje activo es contexto; esto es lo que el usuario
/// tiene que leer en los dos segundos que mira el teléfono dentro de la guagua.
/// De ahí las decisiones:
///
/// · **Una sola frase en imperativo**, grande. Sin subordinadas.
/// · **Superficie translúcida** con desenfoque: flota sobre el mapa sin
///   ocultarlo, y se lee que hay mapa debajo.
/// · **La urgencia cambia el color del acento, no del fondo.** Un fondo rojo a
///   pantalla completa asusta; un acento rojo informa.
/// · **El color nunca es el único canal**: el ícono y el texto también cambian,
///   para que funcione con daltonismo.
/// · **La animación solo ocurre cuando cambia la instrucción**, no cuando
///   cambia la distancia. Si parpadeara cada metro sería inservible.
class InstructionCard extends StatefulWidget {
  const InstructionCard({super.key, required this.instruction});

  final TripInstruction instruction;

  @override
  State<InstructionCard> createState() => _InstructionCardState();
}

class _InstructionCardState extends State<InstructionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(InstructionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instruction.urgency != widget.instruction.urgency) {
      _syncPulse();
    }
  }

  /// El latido solo existe en instrucciones críticas ("bájate ahora"). Es la
  /// única animación en bucle de la app: si todo latiera, nada llamaría la
  /// atención.
  void _syncPulse() {
    if (widget.instruction.urgency == InstructionUrgency.critical) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TripInstruction instruction = widget.instruction;
    final Color accent = colorForUrgency(instruction.urgency);
    final bool reduced = Motion.reduced(context);

    return Semantics(
      // `liveRegion` hace que TalkBack/VoiceOver lean la instrucción nueva sola,
      // sin que el usuario tenga que buscarla. En una app de navegación esto no
      // es un extra: es la forma de usarla sin mirar.
      liveRegion: true,
      label: '${instruction.title}. ${instruction.detail}',
      child: AnimatedSwitcher(
        duration: Motion.adapt(context, Motion.standard),
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        transitionBuilder: (Widget child, Animation<double> animation) {
          if (reduced) return FadeTransition(opacity: animation, child: child);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.18),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        // La `key` es la identidad de la instrucción: mientras no cambie, la
        // tarjeta se actualiza en sitio (la distancia baja) sin re-animarse.
        child: _Card(
          key: ValueKey<String>(instruction.key),
          instruction: instruction,
          accent: accent,
          pulse: _pulse,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.instruction,
    required this.accent,
    required this.pulse,
  });

  final TripInstruction instruction;
  final Color accent;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: pulse,
      builder: (BuildContext context, Widget? child) {
        final double glow = 0.30 + pulse.value * 0.45;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: Radii.cardLg,
            boxShadow: <BoxShadow>[
              ...Shadows.card,
              if (instruction.urgency == InstructionUrgency.critical)
                BoxShadow(
                  color: accent.withValues(alpha: glow * 0.5),
                  blurRadius: 34,
                  spreadRadius: -6,
                ),
            ],
          ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: Radii.cardLg,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceGlass,
              borderRadius: Radii.cardLg,
              border: Border.all(color: accent.withValues(alpha: 0.34)),
            ),
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.lg,
              Spacing.lg,
              Spacing.lg,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _IconBadge(
                  icon: iconForInstruction(instruction.kind),
                  color: accent,
                ),
                const SizedBox(width: Spacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        instruction.title,
                        style: text.headlineSmall?.copyWith(height: 1.15),
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        instruction.detail,
                        style: text.bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (instruction.distanceMeters != null) ...<Widget>[
                  const SizedBox(width: Spacing.md),
                  _DistanceReadout(
                    meters: instruction.distanceMeters!,
                    color: accent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Icon(icon, color: color, size: 24),
      );
}

class _DistanceReadout extends StatelessWidget {
  const _DistanceReadout({required this.meters, required this.color});

  final double meters;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final String value = Fmt.distance(meters);
    final int split = value.lastIndexOf(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value.substring(0, split),
          style: AppTheme.numeric(26, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          value.substring(split + 1),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}
