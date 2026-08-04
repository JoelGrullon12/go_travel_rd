import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Escala de espaciado. Todo el layout sale de estos valores: si un margen no
/// está aquí, es un margen inventado.
abstract final class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

abstract final class Radii {
  static const Radius sm = Radius.circular(10);
  static const Radius md = Radius.circular(16);
  static const Radius lg = Radius.circular(22);
  static const Radius xl = Radius.circular(28);

  static const BorderRadius cardSm = BorderRadius.all(sm);
  static const BorderRadius cardMd = BorderRadius.all(md);
  static const BorderRadius cardLg = BorderRadius.all(lg);
  static const BorderRadius sheet =
      BorderRadius.vertical(top: Radius.circular(28));
}

/// Sombras en capas: una difusa y amplia para el "peso", otra corta y densa
/// para el contacto. Una sola sombra se ve plana y barata.
abstract final class Shadows {
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> sheet = <BoxShadow>[
    BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, -14)),
  ];
}

/// Tema de la app.
///
/// La tipografía usa dos familias con roles distintos, no por decorar:
/// · **Space Grotesk** para números y datos (ETA, distancias, tarifas). Sus
///   cifras son anchas y de altura uniforme: se leen de un vistazo, que es
///   exactamente cómo se mira esta pantalla.
/// · **Inter** para texto corrido e interfaz. Está diseñada para pantalla y
///   aguanta tamaños pequeños sin cerrarse.
///
/// El *tracking* (letter-spacing) cambia con el tamaño, como debe ser: negativo
/// en títulos grandes —las letras se separan visualmente al crecer— y
/// ligeramente positivo en textos chicos, para que respiren.
abstract final class AppTheme {
  static const String display = 'SpaceGrotesk';
  static const String body = 'Inter';

  static ThemeData dark() {
    const ColorScheme scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Color(0xFF04231C),
      secondary: AppColors.info,
      onSecondary: Color(0xFF06182F),
      error: AppColors.critical,
      onError: Color(0xFF2A0A03),
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      outline: AppColors.borderStrong,
    );

    final TextTheme text = TextTheme(
      displaySmall: _t(display, 34, FontWeight.w700, -0.9, 1.05),
      headlineMedium: _t(display, 27, FontWeight.w700, -0.6, 1.12),
      headlineSmall: _t(body, 22, FontWeight.w700, -0.35, 1.2),
      titleLarge: _t(body, 18, FontWeight.w600, -0.2, 1.28),
      titleMedium: _t(body, 16, FontWeight.w600, -0.1, 1.32),
      bodyLarge: _t(body, 15.5, FontWeight.w400, 0, 1.45),
      bodyMedium: _t(body, 14, FontWeight.w400, 0.05, 1.45),
      bodySmall: _t(body, 12.5, FontWeight.w400, 0.15, 1.4),
      labelLarge: _t(body, 14, FontWeight.w600, 0.1, 1.2),
      labelMedium: _t(body, 12, FontWeight.w600, 0.4, 1.2),
      labelSmall: _t(body, 11, FontWeight.w600, 0.7, 1.2),
    ).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      canvasColor: AppColors.canvas,
      fontFamily: body,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: const Color(0xFF04231C),
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
          shape: const RoundedRectangleBorder(borderRadius: Radii.cardMd),
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(0, 52),
          side: const BorderSide(color: AppColors.borderStrong),
          shape: const RoundedRectangleBorder(borderRadius: Radii.cardMd),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: text.labelLarge,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: text.bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: Radii.cardMd),
      ),
    );
  }

  static TextStyle _t(
    String family,
    double size,
    FontWeight weight,
    double tracking,
    double height,
  ) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: tracking,
        height: height,
      );

  /// Estilo para cifras destacadas (ETA, distancia, tarifa).
  static TextStyle numeric(double size, {Color? color, FontWeight? weight}) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        fontWeight: weight ?? FontWeight.w700,
        letterSpacing: size > 28 ? -1.0 : -0.4,
        height: 1.0,
        color: color ?? AppColors.textPrimary,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );
}
