import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/data_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/trip_history_entry.dart';

/// Historial de viajes del usuario (Hito 5).
///
/// Lista los viajes **iniciados** (no los calculados): una ruta solo entra al
/// historial cuando se toca "Iniciar Viaje" en [MapScreen]. El layout replica
/// el de las rutas favoritas de [HomeScreen]: origen → destino, con fecha y
/// costo en el pie. Sin sesión se muestra la invitación a registrarse.
class TripHistoryScreen extends ConsumerStatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  ConsumerState<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends ConsumerState<TripHistoryScreen> {
  @override
  void initState() {
    super.initState();
    // El historial puede haber cambiado al volver de un viaje (se invalida el
    // provider desde MapScreen), pero también se refresca al entrar a la
    // pestaña para no depender solo de la invalidación.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(tripHistoryProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<List<TripHistoryEntry>> history =
        ref.watch(tripHistoryProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              Spacing.xl, Spacing.xl, Spacing.xl, Spacing.xxxl),
          children: <Widget>[
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
                  child: const Icon(Icons.history_rounded,
                      color: AppColors.accent, size: 20),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    'Historial de viajes',
                    style: text.titleLarge?.copyWith(letterSpacing: -0.3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Solo los viajes que comenzaste: calcular una ruta sin iniciarla '
              'no aparece aquí.',
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: Spacing.lg),
            history.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(Spacing.lg),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (Object e, StackTrace _) => _EmptyHistory(
                icon: Icons.error_outline_rounded,
                message: 'No se pudo cargar tu historial. Inténtalo de nuevo.',
              ),
              data: (List<TripHistoryEntry> list) => list.isEmpty
                  ? const _EmptyHistory(
                      icon: Icons.route_outlined,
                      message:
                          'Aún no has hecho viajes. Calcula una ruta en el mapa '
                          'y toca "Iniciar Viaje" para guardarla aquí.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final TripHistoryEntry entry in list)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: Spacing.md),
                            child: _TripHistoryCard(entry: entry),
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

/// Estado cuando el usuario todavía no tiene viajes en el historial.
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.icon, required this.message});

  final IconData icon;
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
          Icon(icon, size: 16, color: AppColors.textTertiary),
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

/// Tarjeta de un viaje del historial: origen → destino + fecha y costo.
///
/// Mismo patrón visual que las tarjetas de rutas favoritas de `HomeScreen`,
/// pero sin acciones (el historial es de solo lectura).
class _TripHistoryCard extends StatelessWidget {
  const _TripHistoryCard({required this.entry});

  final TripHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
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
          Text(
            entry.startName,
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
                  entry.finishName,
                  style:
                      text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: <Widget>[
              Icon(Icons.schedule_rounded,
                  size: 14, color: AppColors.textTertiary),
              const SizedBox(width: Spacing.sm),
              Text(
                _formatDate(entry.date),
                style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
              const Spacer(),
              Text(
                Fmt.money(entry.cost),
                style: text.bodyMedium?.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "10 ago 2026 · 3:42 p. m." — fecha del viaje en es-DO.
  static String _formatDate(DateTime date) =>
      '${Fmt.dateDayMonth(date)} · ${Fmt.clock(date)}';
}
