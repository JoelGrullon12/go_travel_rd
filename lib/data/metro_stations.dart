import '../domain/geo/geo_point.dart';

/// Estación del Metro de Santo Domingo.
class MetroStation {
  const MetroStation(this.id, this.name, this.position, this.line,
      {this.isTransfer = false});

  final String id;
  final String name;
  final GeoPoint position;

  /// 'L1' o 'L2'.
  final String line;
  final bool isTransfer;
}

/// Las 39 estaciones del Metro de Santo Domingo, con coordenadas reales.
///
/// Completa el TODO que quedó abierto en AGENTS.md §6.4 (ahí solo estaban
/// cargadas 17 de las 39). Orden: L1 de Norte a Sur, L2 de Oeste a Este —
/// el mismo orden del recorrido, que es lo que necesita el motor de
/// seguimiento para construir la polilínea.
///
/// Fuente de las coordenadas: AGENTS.md §6.2 y §6.3 (fichas por estación de
/// Wikipedia/Wikidata). Cuando el Hito 1 tenga Firestore cargado, este archivo
/// se sustituye por una lectura de la colección `stops` — nada más cambia,
/// porque el resto del código solo consume [GeoPoint].
const List<MetroStation> kMetroLine1 = <MetroStation>[
  MetroStation('l1-01', 'Mamá Tingó', GeoPoint(18.546632, -69.901148), 'L1'),
  MetroStation('l1-02', 'Gregorio Urbano Gilbert', GeoPoint(18.539567, -69.904357), 'L1'),
  MetroStation('l1-03', 'Gregorio Luperón', GeoPoint(18.529433, -69.908412), 'L1'),
  MetroStation('l1-04', 'José Francisco Peña Gómez', GeoPoint(18.525439, -69.916312), 'L1'),
  MetroStation('l1-05', 'Hermanas Mirabal', GeoPoint(18.518139, -69.914997), 'L1'),
  MetroStation('l1-06', 'Máximo Gómez', GeoPoint(18.507556, -69.915861), 'L1'),
  MetroStation('l1-07', 'Los Taínos', GeoPoint(18.499611, -69.915306), 'L1'),
  MetroStation('l1-08', 'Pedro Livio Cedeño', GeoPoint(18.493389, -69.914889), 'L1'),
  MetroStation('l1-09', 'Manuel Arturo Peña Batlle', GeoPoint(18.486087, -69.914369), 'L1'),
  MetroStation('l1-10', 'Juan Pablo Duarte', GeoPoint(18.481460, -69.914679), 'L1', isTransfer: true),
  MetroStation('l1-11', 'Juan Bosch', GeoPoint(18.476753, -69.913875), 'L1'),
  MetroStation('l1-12', 'Casandra Damirón', GeoPoint(18.471276, -69.912039), 'L1'),
  MetroStation('l1-13', 'Joaquín Balaguer', GeoPoint(18.464536, -69.909987), 'L1'),
  MetroStation('l1-14', 'Amín Abel', GeoPoint(18.459237, -69.916465), 'L1'),
  MetroStation('l1-15', 'Francisco Alberto Caamaño', GeoPoint(18.455611, -69.923972), 'L1'),
  MetroStation('l1-16', 'Centro de los Héroes', GeoPoint(18.450806, -69.927694), 'L1'),
];

const List<MetroStation> kMetroLine2 = <MetroStation>[
  MetroStation('l2-01', 'Pablo Adón Guzmán', GeoPoint(18.519738, -70.010415), 'L2'),
  MetroStation('l2-02', 'Freddy Gatón Arce', GeoPoint(18.510472, -70.008250), 'L2'),
  MetroStation('l2-03', '27 de Febrero', GeoPoint(18.502639, -69.999444), 'L2'),
  MetroStation('l2-04', 'Franklin Mieses Burgos', GeoPoint(18.496639, -69.991111), 'L2'),
  MetroStation('l2-05', 'Pedro Martínez', GeoPoint(18.485787, -69.978112), 'L2'),
  MetroStation('l2-06', 'María Montez', GeoPoint(18.478500, -69.968556), 'L2'),
  MetroStation('l2-07', 'Pedro Francisco Bonó', GeoPoint(18.479827, -69.962143), 'L2'),
  MetroStation('l2-08', 'Francisco Gregorio Billini', GeoPoint(18.481508, -69.954594), 'L2'),
  MetroStation('l2-09', 'Ulises Francisco Espaillat', GeoPoint(18.482028, -69.946639), 'L2'),
  MetroStation('l2-10', 'Pedro Mir', GeoPoint(18.483745, -69.940784), 'L2'),
  MetroStation('l2-11', 'Freddy Beras Goico', GeoPoint(18.482596, -69.930911), 'L2'),
  MetroStation('l2-12', 'Juan Ulises García Saleta', GeoPoint(18.481945, -69.920464), 'L2'),
  MetroStation('l2-13', 'Juan Pablo Duarte', GeoPoint(18.481618, -69.915110), 'L2', isTransfer: true),
  MetroStation('l2-14', 'Coronel Rafael Tomás Fernández', GeoPoint(18.481828, -69.906748), 'L2'),
  MetroStation('l2-15', 'Mauricio Báez', GeoPoint(18.487669, -69.904600), 'L2'),
  MetroStation('l2-16', 'Ramón Cáceres', GeoPoint(18.492936, -69.899236), 'L2'),
  MetroStation('l2-17', 'Horacio Vásquez', GeoPoint(18.495722, -69.896222), 'L2'),
  MetroStation('l2-18', 'Manuel de Jesús Galván', GeoPoint(18.499723, -69.889896), 'L2'),
  MetroStation('l2-19', 'Eduardo Brito', GeoPoint(18.503694, -69.884222), 'L2'),
  MetroStation('l2-20', 'Ercilia Pepín', GeoPoint(18.509680, -69.876245), 'L2'),
  MetroStation('l2-21', 'Rosa Duarte', GeoPoint(18.510311, -69.869718), 'L2'),
  MetroStation('l2-22', 'Trina de Moya de Vásquez', GeoPoint(18.509639, -69.863028), 'L2'),
  MetroStation('l2-23', 'Concepción Bona', GeoPoint(18.505222, -69.857722), 'L2'),
];

/// Colores oficiales aproximados de cada línea. Viven con el dato, no con el
/// tema visual: son propiedad de la línea de transporte, no de la app.
const int kLine1Color = 0xFFF0663A;
const int kLine2Color = 0xFF3B82F6;
const int kWalkColor = 0xFF8B94A8;
const int kConchoColor = 0xFFEAB308;

/// Devuelve un sub-recorrido de una línea entre dos estaciones (inclusive),
/// en el orden en que las recorre el tren.
List<MetroStation> segmentBetween(
  List<MetroStation> line,
  String fromId,
  String toId,
) {
  final int from = line.indexWhere((s) => s.id == fromId);
  final int to = line.indexWhere((s) => s.id == toId);
  if (from < 0 || to < 0) return const <MetroStation>[];
  if (from <= to) return line.sublist(from, to + 1);
  return line.sublist(to, from + 1).reversed.toList(growable: false);
}
