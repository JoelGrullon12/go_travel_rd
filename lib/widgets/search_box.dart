import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Caja flotante con los campos de origen y destino, estilo Uber.
///
/// Es un widget "tonto" (dumb widget): no maneja el estado del mapa,
/// solo expone callbacks para que [MapScreen] reaccione a lo que el
/// usuario escribe. Así se mantiene la separación entre UI de
/// búsqueda y lógica del mapa.
class SearchBox extends StatelessWidget {
  const SearchBox({
    super.key,
    required this.originController,
    required this.destinationController,
    required this.onOriginSubmitted,
    required this.onDestinationSubmitted,
    this.onOriginTap,
    this.onDestinationTap,
    this.readOnly = false,
  });

  final TextEditingController originController;
  final TextEditingController destinationController;
  final ValueChanged<String> onOriginSubmitted;
  final ValueChanged<String> onDestinationSubmitted;

  /// Al tocar el campo de origen/destino (con [readOnly], que no abre el
  /// teclado). Se usa para entrar al flujo de "marcar punto en el mapa".
  final VoidCallback? onOriginTap;
  final VoidCallback? onDestinationTap;

  /// Cuando `true`, los campos son de solo lectura: el punto se elige en el
  /// mapa, no escribiendo. El teclado nunca se abre.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SearchField(
            controller: originController,
            hintText: '¿Dónde estás?',
            icon: Icons.my_location,
            iconColor: AppColors.accent,
            onSubmitted: onOriginSubmitted,
            readOnly: readOnly,
            onTap: onOriginTap,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Divider(height: 1, color: AppColors.border),
          ),
          _SearchField(
            controller: destinationController,
            hintText: '¿A dónde vas?',
            icon: Icons.location_on,
            iconColor: AppColors.textSecondary,
            onSubmitted: onDestinationSubmitted,
            readOnly: readOnly,
            onTap: onDestinationTap,
          ),
        ],
      ),
    );
  }
}

/// Campo de texto individual (origen o destino), reutilizado para no
/// duplicar el mismo diseño dos veces dentro de [SearchBox].
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.iconColor,
    required this.onSubmitted,
    this.readOnly = false,
    this.onTap,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final Color iconColor;
  final ValueChanged<String> onSubmitted;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            onTap: onTap,
            textInputAction: TextInputAction.search,
            onSubmitted: onSubmitted,
            cursorColor: AppColors.accent,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: AppColors.textTertiary),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
