import 'package:flutter/material.dart';

/// Vocabulario de movimiento de la app.
///
/// Reglas que se siguen en todas las animaciones:
///
/// · **Nada por encima de ~300 ms** en micro-interacciones. Una transición de
///   400 ms se siente lenta en la mano; solo la cámara del mapa pasa de ahí,
///   porque ahí el movimiento *es* la información.
/// · **Curvas propias, nunca los defaults.** `Curves.easeInOut` es el "Arial"
///   de la animación: no está mal, pero no dice nada.
/// · **El movimiento tiene función.** Cada transición aquí responde una
///   pregunta del usuario: ¿esto es nuevo?, ¿de dónde salió?, ¿ya terminó?
/// · **Respeta "reducir movimiento".** [adapt] devuelve `Duration.zero` cuando
///   el sistema lo pide: el cambio sigue ocurriendo, pero sin desplazamiento.
abstract final class Motion {
  /// Respuesta al toque. Tiene que ser imperceptible como animación.
  static const Duration instant = Duration(milliseconds: 90);

  /// Cambios de estado pequeños: un chip, un ícono, un color.
  static const Duration quick = Duration(milliseconds: 170);

  /// Entrada y salida de contenido: la tarjeta de instrucción, el banner.
  static const Duration standard = Duration(milliseconds: 260);

  /// Cambios de layout grandes: la hoja al expandirse, la vista de llegada.
  static const Duration large = Duration(milliseconds: 340);

  /// Movimiento de cámara del mapa. Es el único que puede pasar de 300 ms:
  /// aquí el recorrido de la animación comunica el desplazamiento real.
  static const Duration camera = Duration(milliseconds: 620);

  /// Entrada: sale rápido y frena largo. Sensación de "llegó y se asentó".
  static const Cubic enter = Cubic(0.16, 1.0, 0.30, 1.0);

  /// Salida: arranca lento y se va rápido. Espejo de [enter], para que ida y
  /// vuelta se sientan el mismo gesto al revés.
  static const Cubic exit = Cubic(0.70, 0.0, 0.84, 0.0);

  /// Transición neutra para cambios continuos (progreso, contadores).
  static const Cubic smooth = Cubic(0.32, 0.72, 0.0, 1.0);

  /// Rebote leve. Solo para lo que se siente físico: la instrucción crítica
  /// que "aparece de golpe". Nunca decorativo.
  static const Cubic overshoot = Cubic(0.34, 1.36, 0.50, 1.0);

  /// Devuelve la duración real considerando la preferencia de accesibilidad.
  static Duration adapt(BuildContext context, Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
          ? Duration.zero
          : duration;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
