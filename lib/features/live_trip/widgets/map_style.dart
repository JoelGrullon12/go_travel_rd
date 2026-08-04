/// Estilo oscuro del mapa.
///
/// No es un tema comprado: está afinado para esta app. El mapa baja de
/// intensidad —calles apagadas, sin puntos de interés, sin tráfico de carreteras
/// destacado— para que lo único brillante en pantalla sea **la ruta del viaje y
/// la posición del usuario**. Un mapa a todo color compite con la línea que
/// importa, y en movimiento eso cuesta segundos de lectura.
const String kDarkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0b1120"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#7c8aa5"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0b1120"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#1c2436"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#94a3bd"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#111c22"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#141b2b"}]},
  {"featureType":"road","elementType":"labels","stylers":[{"visibility":"simplified"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#5d6b85"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#18202f"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#1e2839"}]},
  {"featureType":"road.local","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#050912"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#334158"}]}
]
''';
