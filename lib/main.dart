import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_travel_rd/firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/theme/app_theme.dart';
import 'screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Necesario para formatear horas en español ("3:42 p. m.") con `intl`.
  await initializeDateFormatting('es');

  // Barra de estado transparente: el mapa llega hasta arriba.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF080B14),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ProviderScope(child: GoTravelApp()));
}

class GoTravelApp extends StatelessWidget {
  const GoTravelApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GoTravel RD',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        // La app es dark-first por decisión de diseño (ver AppColors): el modo
        // claro no está afinado y mostrarlo a medias sería peor que no tenerlo.
        themeMode: ThemeMode.dark,
        darkTheme: AppTheme.dark(),
        locale: const Locale('es'),
        supportedLocales: const <Locale>[Locale('es'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (BuildContext context, Widget? child) {
          // Tope al escalado de texto: respetamos la preferencia del usuario
          // (accesibilidad) pero por encima de 1.35 la tarjeta de instrucción
          // se desborda y deja de cumplir su función.
          final MediaQueryData media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.35,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const MainShellScreen(),
      );
}
