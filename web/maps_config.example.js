// Plantilla -> copiar como `web/maps_config.js` (ignorado por git).
//
// Solo hace falta para correr la app en navegador (`flutter run -d chrome`).
// En Android/iOS la key viaja por local.properties / Secrets.xcconfig.
//
// OJO: la key para web es de la "Maps JavaScript API" (producto distinto al
// "Maps SDK for Android"). Hay que habilitarla en Google Cloud Console y
// restringirla por referente HTTP (http://localhost:*).

window.GOOGLE_MAPS_API_KEY = 'PEGA_AQUI_TU_API_KEY';

(function loadGoogleMapsJs() {
  var key = window.GOOGLE_MAPS_API_KEY;
  if (!key || key.indexOf('PEGA_AQUI') === 0) {
    console.warn('[GoTravelRD] Sin API key de Maps JavaScript: el mapa saldra vacio.');
    return;
  }
  var s = document.createElement('script');
  s.src =
    'https://maps.googleapis.com/maps/api/js?key=' +
    encodeURIComponent(key) +
    '&language=es&region=DO&loading=async';
  s.defer = true;
  document.head.appendChild(s);
})();
