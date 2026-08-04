import '../../domain/geo/geo_point.dart';
import '../../domain/models/transport_mode.dart';
import '../../domain/models/trip_plan.dart';
import '../metro_stations.dart';

/// Planes de viaje de ejemplo.
///
/// ── POR QUÉ EXISTE ESTE ARCHIVO ───────────────────────────────────────────
/// El Hito 4 (seguimiento en tiempo real) consume el resultado del Hito 2
/// (motor de cálculo de ruta A→B), que todavía no está construido. En vez de
/// bloquearse esperando, este archivo produce [TripPlan]s con el mismo contrato
/// que devolverá el motor real, usando coordenadas reales del Metro de Santo
/// Domingo.
///
/// Cuando el Hito 2 esté listo, se cambia UNA línea:
///   `tripPlanProvider` en lib/application/providers.dart
/// deja de leer de aquí y pasa a leer del motor. Ni el seguimiento ni la UI
/// cambian. Ver README.md §"Integración con el Hito 2".
///
/// ── QUÉ ES APROXIMADO Y QUÉ NO ────────────────────────────────────────────
/// · Coordenadas de estaciones: reales (AGENTS.md §6).
/// · Trazado entre estaciones: recta estación a estación. La vía real curva un
///   poco; a efectos de distancia recorrida y de decidir "bájate ahora" el
///   error es de decenas de metros, por debajo del margen del propio GPS.
/// · Tramos a pie: línea recta. Cuando entre la Directions API de Google se
///   reemplazan por la ruta peatonal real; el resto del código no cambia,
///   porque solo consume la lista de puntos.
/// · Tarifas y frecuencias: valores plausibles puestos por el equipo, no dato
///   oficial de OPRET. Marcar como pendiente de verificar antes de la entrega.
/// ──────────────────────────────────────────────────────────────────────────
abstract final class DemoTripPlans {
  /// Viaje completo con transbordo L1 → L2. Es el caso que ejercita todas las
  /// instrucciones: caminar, abordar, ir en camino, prepararse, transbordar y
  /// llegar.
  static TripPlan villaMellaLosMina() {
    final List<MetroStation> l1 =
        segmentBetween(kMetroLine1, 'l1-01', 'l1-10'); // Mamá Tingó → J.P. Duarte
    final List<MetroStation> l2 =
        segmentBetween(kMetroLine2, 'l2-13', 'l2-19'); // J.P. Duarte → E. Brito

    const GeoPoint origin = GeoPoint(18.549800, -69.899900); // Villa Mella
    const GeoPoint destination = GeoPoint(18.501000, -69.881700); // Los Mina

    return TripPlan(
      id: 'demo-villa-mella-los-mina',
      originName: 'Villa Mella',
      destinationName: 'Los Mina',
      legs: <TripLeg>[
        TripLeg(
          id: 'leg-walk-in',
          mode: TransportMode.walk,
          path: <GeoPoint>[origin, l1.first.position],
          lineColorHex: kWalkColor,
        ),
        _metroLeg(
          id: 'leg-l1',
          stations: l1,
          lineName: 'Metro Línea 1',
          headsign: 'Centro de los Héroes',
          colorHex: kLine1Color,
        ),
        // Transbordo a pie dentro de la estación: los andenes de L1 y L2 en
        // Juan Pablo Duarte están conectados pero no son el mismo punto.
        TripLeg(
          id: 'leg-transfer',
          mode: TransportMode.walk,
          path: <GeoPoint>[l1.last.position, l2.first.position],
          lineColorHex: kWalkColor,
        ),
        _metroLeg(
          id: 'leg-l2',
          stations: l2,
          lineName: 'Metro Línea 2',
          headsign: 'Concepción Bona',
          colorHex: kLine2Color,
        ),
        TripLeg(
          id: 'leg-walk-out',
          mode: TransportMode.walk,
          path: <GeoPoint>[l2.last.position, destination],
          lineColorHex: kWalkColor,
        ),
      ],
    );
  }

  /// Viaje corto de una sola línea. Útil para probar el flujo completo rápido.
  static TripPlan maximoGomezMalecon() {
    final List<MetroStation> l1 =
        segmentBetween(kMetroLine1, 'l1-06', 'l1-16'); // Máximo Gómez → C. Héroes

    const GeoPoint origin = GeoPoint(18.509900, -69.917200);
    const GeoPoint destination = GeoPoint(18.448200, -69.929700); // Malecón

    return TripPlan(
      id: 'demo-maximo-gomez-malecon',
      originName: 'Av. Máximo Gómez',
      destinationName: 'Malecón (Centro de los Héroes)',
      legs: <TripLeg>[
        TripLeg(
          id: 'leg-walk-in',
          mode: TransportMode.walk,
          path: <GeoPoint>[origin, l1.first.position],
          lineColorHex: kWalkColor,
        ),
        _metroLeg(
          id: 'leg-l1',
          stations: l1,
          lineName: 'Metro Línea 1',
          headsign: 'Centro de los Héroes',
          colorHex: kLine1Color,
        ),
        TripLeg(
          id: 'leg-walk-out',
          mode: TransportMode.walk,
          path: <GeoPoint>[l1.last.position, destination],
          lineColorHex: kWalkColor,
        ),
      ],
    );
  }

  /// Viaje en transporte **sin paradas fijas** (concho por la 27 de Febrero).
  ///
  /// Existe para probar que las instrucciones no asumen que siempre hay
  /// paradas: aquí no se puede decir "faltan 3 paradas", solo distancia.
  static TripPlan nacoVillaConsuelo() {
    const GeoPoint origin = GeoPoint(18.485900, -69.941800); // Naco
    const GeoPoint destination = GeoPoint(18.484100, -69.912600); // Villa Consuelo

    // El recorrido sigue la Av. 27 de Febrero, que es por donde corre la L2:
    // reutilizamos esas coordenadas como trazado de la avenida.
    const List<GeoPoint> avenida = <GeoPoint>[
      GeoPoint(18.483745, -69.940784),
      GeoPoint(18.482596, -69.930911),
      GeoPoint(18.481945, -69.920464),
      GeoPoint(18.481700, -69.914900),
    ];

    return TripPlan(
      id: 'demo-naco-villa-consuelo',
      originName: 'Naco',
      destinationName: 'Villa Consuelo',
      legs: <TripLeg>[
        TripLeg(
          id: 'leg-walk-in',
          mode: TransportMode.walk,
          path: <GeoPoint>[origin, avenida.first],
          lineColorHex: kWalkColor,
        ),
        TripLeg(
          id: 'leg-concho',
          mode: TransportMode.concho,
          path: avenida,
          lineName: 'Concho 27 de Febrero',
          headsign: 'Parque Enriquillo',
          lineColorHex: kConchoColor,
          fareDop: 35,
          headwayMinutes: 4,
        ),
        TripLeg(
          id: 'leg-walk-out',
          mode: TransportMode.walk,
          path: <GeoPoint>[avenida.last, destination],
          lineColorHex: kWalkColor,
        ),
      ],
    );
  }

  static List<TripPlan> all() => <TripPlan>[
        villaMellaLosMina(),
        maximoGomezMalecon(),
        nacoVillaConsuelo(),
      ];

  static TripLeg _metroLeg({
    required String id,
    required List<MetroStation> stations,
    required String lineName,
    required String headsign,
    required int colorHex,
  }) =>
      TripLeg(
        id: id,
        mode: TransportMode.metro,
        path: stations.map((s) => s.position).toList(growable: false),
        lineName: lineName,
        headsign: headsign,
        lineColorHex: colorHex,
        stops: stations
            .map(
              (s) => TripStop(
                id: s.id,
                name: s.name,
                position: s.position,
                isTransfer: s.isTransfer,
              ),
            )
            .toList(growable: false),
        // Tarifa única del Metro de Santo Domingo (pendiente de verificar con
        // OPRET antes de la entrega final).
        fareDop: 20,
        headwayMinutes: 5,
      );
}
