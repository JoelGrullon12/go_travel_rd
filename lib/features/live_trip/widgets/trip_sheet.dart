import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/models/trip_plan.dart';
import '../../../domain/models/trip_progress.dart';
import '../../../domain/tracking/trip_geometry.dart';
import '../../shared/mode_visuals.dart';
import 'leg_progress_bar.dart';

/// Contenido de la hoja inferior del viaje activo.
///
/// Jerarquía deliberada, de arriba abajo: **cuánto falta** (lo que todo el
/// mundo mira), **por dónde vas**, **qué paradas vienen**, y al final los
/// controles. Lo urgente vive arriba en la tarjeta de instrucción; aquí vive el
/// contexto, que se consulta cuando hay calma.
class TripSheet extends StatelessWidget {
  const TripSheet({
    super.key,
    required this.scrollController,
    required this.geometry,
    required this.progress,
    required this.onEndTrip,
    this.demoControls,
  });

  final ScrollController scrollController;
  final TripGeometry geometry;
  final TripProgress? progress;
  final VoidCallback onEndTrip;
  final Widget? demoControls;

  @override
  Widget build(BuildContext context) {
    final TripPlan plan = geometry.plan;
    final TripProgress? p = progress;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.sheet,
        boxShadow: Shadows.sheet,
      ),
      child: ClipRRect(
        borderRadius: Radii.sheet,
        child: Column(
          children: <Widget>[
            const _Grabber(),
            Expanded(
              child: ListView(
                controller: scrollController,
                // El padding inferior incluye el inset de la barra de
                // navegación del sistema: "Terminar viaje" siempre puede
                // subir por encima de ella al hacer scroll.
                padding: EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.xs,
                  Spacing.lg,
                  Spacing.xxl + MediaQuery.paddingOf(context).bottom,
                ),
                children: <Widget>[
                  _EtaHeader(plan: plan, progress: p),
                  const SizedBox(height: Spacing.lg),
                  LegProgressBar(
                    geometry: geometry,
                    traveledMeters: p?.traveledMeters ?? 0,
                  ),
                  const SizedBox(height: Spacing.md),
                  _TripStats(geometry: geometry, progress: p),
                  const SizedBox(height: Spacing.xl),
                  if (p != null) _UpcomingStops(progress: p),
                  const SizedBox(height: Spacing.xl),
                  _LegOutline(geometry: geometry, progress: p),
                  if (demoControls != null) ...<Widget>[
                    const SizedBox(height: Spacing.xl),
                    demoControls!,
                  ],
                  const SizedBox(height: Spacing.xl),
                  OutlinedButton.icon(
                    onPressed: onEndTrip,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Terminar viaje'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.critical,
                      side: const BorderSide(color: AppColors.border),
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

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        child: Container(
          width: 44,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.borderStrong,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _EtaHeader extends StatelessWidget {
  const _EtaHeader({required this.plan, required this.progress});

  final TripPlan plan;
  final TripProgress? progress;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Duration remaining = progress?.eta.remaining ?? Duration.zero;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'HACIA',
                style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                plan.destinationName,
                style: text.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (progress != null) ...<Widget>[
                const SizedBox(height: Spacing.xs),
                Text(
                  'Llegas ${Fmt.clock(progress!.eta.arrivalAt)}',
                  style: text.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: Spacing.lg),
        Semantics(
          label: 'Tiempo restante',
          value: Fmt.duration(remaining),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                Fmt.durationValue(remaining),
                style: AppTheme.numeric(40, color: AppColors.accent),
              ),
              const SizedBox(width: 4),
              Text(
                Fmt.durationUnit(remaining),
                style: text.labelMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TripStats extends StatelessWidget {
  const _TripStats({required this.geometry, required this.progress});

  final TripGeometry geometry;
  final TripProgress? progress;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double remaining =
        progress?.remainingMeters ?? geometry.totalMeters;

    // `Wrap` y no `Row`: son hasta cuatro datos y la hoja tiene que aguantar
    // pantallas de 375 pt y texto escalado por accesibilidad sin desbordarse.
    return DefaultTextStyle.merge(
      style: text.bodySmall!.copyWith(color: AppColors.textTertiary),
      child: Wrap(
        spacing: Spacing.lg,
        runSpacing: Spacing.xs,
        children: <Widget>[
          Text(Fmt.distance(remaining)),
          Text(Fmt.money(geometry.plan.totalFareDop)),
          if (geometry.plan.transferCount > 0)
            Text(
              geometry.plan.transferCount == 1
                  ? '1 transbordo'
                  : '${geometry.plan.transferCount} transbordos',
            ),
          if (progress?.speedMps != null) Text(Fmt.speed(progress!.speedMps)),
        ],
      ),
    );
  }
}

/// Paradas que faltan del tramo actual, con la próxima destacada.
class _UpcomingStops extends StatelessWidget {
  const _UpcomingStops({required this.progress});

  final TripProgress progress;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final TripLeg leg = progress.currentLeg;
    final List<TripStop> stops = progress.upcomingStops;

    if (stops.isEmpty) {
      return Text(
        leg.mode.isWalking
            ? 'Vas a pie: no hay paradas en este tramo.'
            : 'Ya pasaste la última parada de este tramo.',
        style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
      );
    }

    final Color lineColor = Color(leg.lineColorHex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(iconForMode(leg.mode), size: 16, color: lineColor),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                leg.shortLabel.toUpperCase(),
                style: text.labelSmall?.copyWith(color: lineColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${stops.length} por delante',
              style:
                  text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        for (int i = 0; i < stops.length; i++)
          _StopRow(
            stop: stops[i],
            color: lineColor,
            isNext: i == 0,
            isLast: i == stops.length - 1,
          ),
      ],
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.color,
    required this.isNext,
    required this.isLast,
  });

  final TripStop stop;
  final Color color;
  final bool isNext;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 22,
            child: Column(
              children: <Widget>[
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  width: isNext ? 12 : 8,
                  height: isNext ? 12 : 8,
                  decoration: BoxDecoration(
                    color: isNext ? color : AppColors.surfaceHigh,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: color.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : Spacing.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      stop.name,
                      style: isNext
                          ? text.titleMedium
                          : text.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (stop.isTransfer)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        borderRadius: Radii.cardSm,
                      ),
                      child: Text(
                        'Transbordo',
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  if (isLast && !stop.isTransfer)
                    Text(
                      'Te bajas',
                      style: text.labelSmall?.copyWith(color: color),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resumen del viaje completo tramo por tramo.
class _LegOutline extends StatelessWidget {
  const _LegOutline({required this.geometry, required this.progress});

  final TripGeometry geometry;
  final TripProgress? progress;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final int currentLeg = progress?.currentLegIndex ?? -1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'EL VIAJE COMPLETO',
          style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
        ),
        const SizedBox(height: Spacing.md),
        for (int i = 0; i < geometry.plan.legs.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: Opacity(
              opacity: i < currentLeg ? 0.45 : 1,
              child: Row(
                children: <Widget>[
                  Icon(
                    iconForMode(geometry.plan.legs[i].mode),
                    size: 18,
                    color: Color(geometry.plan.legs[i].lineColorHex),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      geometry.plan.legs[i].mode.isWalking
                          ? 'Caminar ${Fmt.distance(geometry.plan.legs[i].distanceMeters)}'
                          : geometry.plan.legs[i].shortLabel,
                      style: i == currentLeg
                          ? text.titleMedium
                          : text.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (i == currentLeg)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.sm, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.16),
                        borderRadius: Radii.cardSm,
                      ),
                      child: Text(
                        'AHORA',
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.accent),
                      ),
                    )
                  else
                    Text(
                      Fmt.distance(geometry.plan.legs[i].distanceMeters),
                      style: text.bodySmall
                          ?.copyWith(color: AppColors.textTertiary),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
