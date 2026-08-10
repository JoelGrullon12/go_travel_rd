import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/data_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../models/transport_type.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

/// Pantalla de edición de preferencias del usuario (Hito 5).
///
/// Se abre desde [ProfileScreen] con el [AppUser] actual y permite editar:
/// · tipo de transporte preferido (radio, un solo tipo, desde
///   `transportTypes`; "Ninguno" lo limpia);
/// · preferencia de viaje (`routePreference`): más rápido / más barato /
///   más corto;
/// · distancia máxima a pie (input numérico, 100–5000 m).
///
/// Al guardar persiste solo esos campos con `AuthService.updateUserData` y
/// devuelve `true` por [Navigator.pop] para que la pantalla de perfil recargue.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, required this.user});

  final AppUser user;

  static const double minWalkMeters = 100;
  static const double maxWalkMeters = 5000;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  static const List<(String, String)> _preferenceOptions = <(String, String)>[
    ('speed', 'Más rápido'),
    ('price', 'Más barato'),
    ('distance', 'Más corto'),
  ];

  final _formKey = GlobalKey<FormState>();
  final _maxWalkController = TextEditingController();

  String? _selectedTransportTypeId;
  late String _routePreference;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedTransportTypeId = widget.user.favoriteTransportTypeId;
    _routePreference =
        AppUser.normalizeRoutePreference(widget.user.routePreference);
    _maxWalkController.text = widget.user.maxWalkDistance.toInt().toString();
  }

  @override
  void dispose() {
    _maxWalkController.dispose();
    super.dispose();
  }

  /// Nombre legible del tipo seleccionado: el `name` de `transportTypes`
  /// cuando se conoce, o el id crudo si la colección aún no cargó.
  String _transportLabel(List<TransportType> types) {
    final String? selected = _selectedTransportTypeId;
    if (selected == null) return 'Ninguno';
    for (final TransportType t in types) {
      if (t.id == selected) return t.name;
    }
    return selected;
  }

  /// Abre el selector de tipo de transporte (radio: un solo tipo a la vez).
  Future<void> _pickTransportTypes() async {
    final List<TransportType> types =
        ref.read(transportTypesProvider).valueOrNull ?? const <TransportType>[];
    if (types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay tipos de transporte disponibles.'),
        ),
      );
      return;
    }

    String? result = _selectedTransportTypeId;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Tipo de transporte preferido'),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  RadioGroup<String>(
                    groupValue: result,
                    onChanged: (String? value) => setDialogState(() {
                      result = value == null || value.isEmpty ? null : value;
                    }),
                    child: Column(
                      children: <Widget>[
                        const RadioListTile<String>(
                          value: '',
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text('Ninguno'),
                        ),
                        for (final TransportType type in types)
                          RadioListTile<String>(
                            value: type.id,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(type.name),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() => _selectedTransportTypeId = result);
    }
  }

  String? _validateMaxWalk(String? value) {
    final int? parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'Ingresa un número válido';
    if (parsed < EditProfileScreen.minWalkMeters) {
      return 'El mínimo es ${EditProfileScreen.minWalkMeters.toInt()} m';
    }
    if (parsed > EditProfileScreen.maxWalkMeters) {
      return 'El máximo es ${EditProfileScreen.maxWalkMeters.toInt()} m';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final double maxWalk =
        double.parse(_maxWalkController.text.trim()).clamp(
              EditProfileScreen.minWalkMeters,
              EditProfileScreen.maxWalkMeters,
            );
    try {
      await AuthService().updateUserData(widget.user.uid, <String, dynamic>{
        'favoriteTransportTypeId': _selectedTransportTypeId,
        'routePreference': _routePreference,
        'maxWalkDistance': maxWalk,
      });
      ref.invalidate(maxWalkDistanceProvider);
      ref.invalidate(userPreferencesProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron guardar las preferencias')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<TransportType> transportTypes =
        ref.watch(transportTypesProvider).valueOrNull ?? const <TransportType>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Editar preferencias')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(Spacing.xl),
          children: <Widget>[
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Preferencias de viaje',
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  InkWell(
                    key: const Key('transport-types-field'),
                    borderRadius: Radii.cardSm,
                    onTap: _saving ? null : _pickTransportTypes,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Tipo de transporte preferido',
                        helperText: 'Elige uno: el motor lo favorece en la ruta',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        _transportLabel(transportTypes),
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  DropdownButtonFormField<String>(
                    key: const Key('route-preference-field'),
                    initialValue: _routePreference,
                    decoration: const InputDecoration(
                      labelText: 'Preferencia de viaje',
                      border: OutlineInputBorder(),
                    ),
                    dropdownColor: AppColors.surfaceHigh,
                    items: <DropdownMenuItem<String>>[
                      for (final (String value, String label)
                          in _preferenceOptions)
                        DropdownMenuItem<String>(
                          value: value,
                          child: Text(label),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (String? value) {
                            if (value != null) {
                              setState(() => _routePreference = value);
                            }
                          },
                  ),
                  const SizedBox(height: Spacing.lg),
                  TextFormField(
                    key: const Key('max-walk-field'),
                    controller: _maxWalkController,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(
                        EditProfileScreen.maxWalkMeters.toInt().toString().length,
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Distancia máxima a pie (metros)',
                      helperText: 'Entre 100 y 5000 m',
                      suffixText: 'm',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateMaxWalk,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.xxl),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const Key('save-preferences-button'),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : const Text('Guardar preferencias'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
