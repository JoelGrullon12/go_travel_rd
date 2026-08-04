import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/trip_plan.dart';
import '../../../domain/tracking/trip_geometry.dart';

/// Barra de progreso segmentada por tramo.
///
/// Una barra única diría "vas por el 40 %", que no significa nada cuando el
/// viaje tiene cinco tramos distintos. Segmentada dice algo útil de un vistazo:
/// **en qué tramo vas, cuánto le falta, y cuántos quedan** — cada segmento con
/// el color de su línea y de ancho proporcional a su distancia real.
class LegProgressBar extends StatelessWidget {
  const LegProgressBar({
    super.key,
    required this.geometry,
    required this.traveledMeters,
    this.height = 10,
  });

  final TripGeometry geometry;
  final double traveledMeters;
  final double height;

  @override
  Widget build(BuildContext context) {
    final TripPlan plan = geometry.plan;
    return Semantics(
      label: 'Progreso del viaje',
      value:
          '${((traveledMeters / (geometry.totalMeters == 0 ? 1 : geometry.totalMeters)) * 100).round()} por ciento',
      child: SizedBox(
        height: height,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < plan.legs.length; i++) ...<Widget>[
              Expanded(
                flex: _flexFor(i),
                child: _Segment(
                  color: Color(plan.legs[i].lineColorHex),
                  fraction: _fractionOf(i),
                  height: height,
                  isFirst: i == 0,
                  isLast: i == plan.legs.length - 1,
                ),
              ),
              if (i != plan.legs.length - 1) const SizedBox(width: 3),
            ],
          ],
        ),
      ),
    );
  }

  /// Ancho proporcional a la distancia, con un mínimo: un transbordo de 60 m
  /// dentro de una estación desaparecería, y es justo el punto donde el usuario
  /// tiene que hacer algo.
  int _flexFor(int legIndex) {
    final double meters =
        geometry.legEndMeters[legIndex] - geometry.legStartMeters[legIndex];
    return (meters.clamp(120, double.infinity)).round();
  }

  double _fractionOf(int legIndex) {
    final double start = geometry.legStartMeters[legIndex];
    final double end = geometry.legEndMeters[legIndex];
    final double length = end - start;
    if (length <= 0) return traveledMeters >= end ? 1 : 0;
    return ((traveledMeters - start) / length).clamp(0.0, 1.0);
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.color,
    required this.fraction,
    required this.height,
    required this.isFirst,
    required this.isLast,
  });

  final Color color;
  final double fraction;
  final double height;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.horizontal(
      left: Radius.circular(isFirst ? height / 2 : 2),
      right: Radius.circular(isLast ? height / 2 : 2),
    );
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: color.withValues(alpha: 0.22)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction,
            child: ColoredBox(color: color),
          ),
          if (fraction > 0 && fraction < 1)
            // Punta luminosa en la posición exacta: el ojo la encuentra sin
            // buscar, y da la sensación de que el viaje está vivo.
            Align(
              alignment: Alignment(fraction * 2 - 1, 0),
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.9),
                      blurRadius: 8,
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
