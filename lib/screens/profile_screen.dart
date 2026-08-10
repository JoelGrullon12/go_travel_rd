import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  AppUser? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    final user = await _authService.getUserData(uid);
    if (mounted) {
      setState(() {
        _user = user;
        _loading = false;
      });
    }
  }

  /// Abre la pantalla de preferencias y, si el usuario guardó cambios,
  /// recarga el perfil para reflejar los valores nuevos.
  Future<void> _openEditProfile() async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditProfileScreen(user: _user!),
      ),
    );
    if (saved == true && mounted) _loadUser();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _user == null
              ? const Center(child: Text('No se pudo cargar el perfil'))
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundImage: _user!.photoUrl != null
                            ? NetworkImage(_user!.photoUrl!)
                            : null,
                        child: _user!.photoUrl == null
                            ? const Icon(Icons.person, size: 50)
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _user!.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _user!.email,
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 32),
                      _infoTile(
                          'Transportes preferidos',
                          _user!.favoriteTransportTypeIds.isEmpty
                              ? 'No especificado'
                              : _user!.favoriteTransportTypeIds.join(', ')),
                      _infoTile('Distancia máxima a pie',
                          '${_user!.maxWalkDistance.toInt()} m'),
                      _infoTile('Preferencia de ruta', _preferenceLabel),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: _openEditProfile,
                          child: const Text('Editar Perfil'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () async {
                            await _authService.signOut();
                            if (!context.mounted) return;
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LoginScreen()),
                              (_) => false,
                            );
                          },
                          child: const Text('Cerrar Sesión'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  String get _preferenceLabel {
    switch (_user!.routePreference) {
      case 'price':
        return 'Más barato';
      case 'distance':
        return 'Más corto';
      case 'speed':
        return 'Más rápido';
      default:
        return 'Más rápido';
    }
  }
}
