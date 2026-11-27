# Android: recuperación de red y WorkManager

`ForegroundSync` mantiene el reintento al recuperar red, reanudar la aplicación
y mediante su temporizador en primer plano. Connectivity no prueba por sí sola
que Supabase sea accesible.

Con `SYNC_BACKGROUND_V1=true` y `SYNC_UNIVERSAL_V1=true`, WorkManager abre la base
cifrada y reutiliza `UniversalSync.flush`, incluidos adjuntos y dependencias.
La ruta anterior de eventos RPC también está disponible si se compila
`SYNC_EVENT_RPC_V1=true`. Sin un motor habilitado se cancela el trabajo propio y
se elimina la credencial de entrega.

El trabajo periódico solicita red disponible y un intervalo mínimo de quince
minutos. Android decide cuándo ejecutarlo: no es una promesa de puntualidad, de
ejecución tras force-stop ni de ejecución con credenciales caducadas. No se
guardan tokens en `inputData`, logs o SQLite.

La implementación y las pruebas de autorización están descritas en
[background-delivery-v1.md](background-delivery-v1.md). Esta versión reemplaza
la antigua prueba que sólo programaba un callback sin entregar datos.
