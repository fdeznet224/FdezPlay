FdezPlay - Fase 54: Transmitir a Smart TV DLNA

Cambios:
- Agrega módulo DLNA/UPnP sin dependencias externas.
- Agrega botón "Transmitir" en reproductor de películas, series y TV en vivo.
- Busca Smart TVs compatibles en la misma red: Samsung, LG y MediaRenderer DLNA.
- Envía URL directa a la TV usando AVTransport.
- Pausa la reproducción local cuando el contenido se envía correctamente.
- Agrega permisos Android para red local / multicast.

Notas:
- Roku queda fuera porque se desarrollará app nativa.
- Las descargas offline no se transmiten todavía porque la TV no puede acceder al archivo local del celular.
- TV en vivo queda soportado en modo compatible, pero algunas TVs no aceptan canales .ts/m3u8.
- No requiere flutter pub add.

Aplicar:
unzip -o FdezPlay_Cast_DLNA_SmartTV_Fase54.zip -d .
flutter clean
flutter pub get
flutter run
