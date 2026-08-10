import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/data_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'trip_history_screen.dart';

/// Altura de la barra de navegación flotante.
const double _kNavBarHeight = 60;

/// Pantalla principal con barra de navegación flotante (Hito 5).
///
/// Reemplaza a [HomeScreen] como punto de entrada de la app: tres pestañas —
/// inicio, historial de viajes y usuario — con una barra redondeada que flota
/// sobre el contenido. La información del usuario ya no se muestra desde un
/// avatar en el mapa/inicio: vive en la pestaña de usuario.
///
/// El contenido de cada pestaña se mantiene vivo con [IndexedStack] (no se
/// pierde scroll ni estado al cambiar de pestaña).
class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  final _authService = AuthService();
  User? _user;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _user = _authService.currentUser;
    _authService.authStateChanges.listen((user) {
      if (mounted) {
        setState(() => _user = user);
        // Los `FutureProvider` dependientes del usuario cachean su resultado y
        // no se enteran de que cambió la sesión: sin esta invalidación, las
        // rutas/historial/preferencias de un usuario recién logueado no se
        // cargan hasta reiniciar la app (que recrea el container).
        ref.invalidate(userRoutesProvider);
        ref.invalidate(tripHistoryProvider);
        ref.invalidate(maxWalkDistanceProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(bottom: _kNavBarHeight + Spacing.lg),
              child: IndexedStack(
                index: _index,
                children: <Widget>[
                  const HomeScreen(),
                  const TripHistoryScreen(),
                  if (_user != null) const ProfileScreen() else const _ProfilePrompt(),
                ],
              ),
            ),
          ),
          Positioned(
            left: Spacing.xl,
            right: Spacing.xl,
            bottom: bottomInset + Spacing.lg,
            child: _FloatingNavBar(
              index: _index,
              onSelected: (int i) => setState(() => _index = i),
            ),
          ),
        ],
      ),
    );
  }
}

/// Invitación a iniciar sesión desde la pestaña de usuario cuando no hay
/// sesión activa.
class _ProfilePrompt extends StatelessWidget {
  const _ProfilePrompt();

  void _openLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.person_outline_rounded,
                  size: 56, color: AppColors.textTertiary),
              const SizedBox(height: Spacing.lg),
              Text(
                'Tu perfil te espera',
                textAlign: TextAlign.center,
                style: text.titleLarge,
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Inicia sesión para ver tus datos, preferencias y guardar '
                'tus rutas.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: Spacing.xl),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () => _openLogin(context),
                  child: const Text('Iniciar sesión'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra de navegación inferior flotante (píldora redondeada).
///
/// Flota sobre el contenido con un margen: fondo elevado, borde y sombra.
/// El ítem seleccionado se marca con el color accent y un fondo tenue.
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kNavBarHeight,
      padding: const EdgeInsets.all(Spacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.borderStrong),
        boxShadow: Shadows.card,
      ),
      child: Row(
        children: <Widget>[
          _NavItem(
            icon: Icons.home_rounded,
            label: 'Inicio',
            selected: index == 0,
            onTap: () => onSelected(0),
          ),
          _NavItem(
            icon: Icons.history_rounded,
            label: 'Historial',
            selected: index == 1,
            onTap: () => onSelected(1),
          ),
          _NavItem(
            icon: Icons.person_rounded,
            label: 'Usuario',
            selected: index == 2,
            onTap: () => onSelected(2),
          ),
        ],
      ),
    );
  }
}

/// Ítem individual de la barra flotante: icono + etiqueta.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color color =
        selected ? AppColors.accent : AppColors.textTertiary;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: text.labelSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
