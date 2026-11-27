# Entrega universal Android en segundo plano

`background_sync.dart` reutiliza `UniversalSync.flush` sobre
`OfflineStore.protected()`. El worker procesa la misma cola cifrada que el primer
plano: conserva UUID, cuerpo, adjuntos, recibos y relaciones de dependencia. Una
dependencia se sella con la revisión del recibo correcto antes de enviar; una
respuesta ambigua no genera un nuevo identificador ni un rebase automático.

## Sesión y permisos

El proceso principal publica una copia de su access token vigente en
`flutter_secure_storage`, vinculada a proyecto, usuario, caducidad y generación.
No copia el refresh token y el worker no abre una sesión persistida ni renueva
credenciales. El registro v2 verifica también el `sub`, `role=authenticated` y
`exp` del JWT; la firma siempre la valida Supabase. La versión previa del registro
se elimina al publicar o cerrar sesión.

El cliente headless usa un callback `accessToken` que relee el almacenamiento
seguro. El transporte vuelve a comprobarlo antes y después de cada petición,
rechaza otros orígenes y redirecciones, y permite únicamente las RPC necesarias
y el bucket `animal-photos`. Antes de cada envío comprueba la membresía y que
el rancho y rol no cambiaron. El servidor mantiene Auth, RLS y permisos de cada
operación. Las operaciones universales sin proyecto comprobable permanecen en
espera de revisión en primer plano.

Logout elimina la credencial antes de `signOut`. Caducidad, cambio de sesión,
revocación o respuestas HTTP 401/403 pausan sin crear un rechazo ni incrementar
intentos. Una petición ya recibida puede terminar en el servidor; el cuerpo y
UUID permanecen disponibles para reconocer su duplicado al reconectar.

## Recursos y coexistencia

El worker renueva el lease SQLite compartido y acota la ejecución a ocho
operaciones y 110 segundos antes de nuevas solicitudes. Procesa originales uno
a uno, con el mismo upload sin sobrescritura y verificación de bytes ante
duplicados del motor principal. Conserva la ruta de eventos RPC anterior cuando
su flag está habilitado; nunca convierte automáticamente una operación vieja
de resultado desconocido en otra nueva.

Una solicitud puede seguir en el servidor tras un timeout o tras expirar un
lease. La idempotencia del servidor sigue siendo necesaria. Los recibos
confirmados no sustituyen la descarga canónica y no descartan una proyección
local antes de su reconciliación.

Activación: `SYNC_BACKGROUND_V1=true` y al menos uno de
`SYNC_UNIVERSAL_V1=true` o `SYNC_EVENT_RPC_V1=true`, contra un backend con el
contrato correspondiente. Las opciones se fijan al compilar. Android puede
posponer WorkManager, y no se promete envío tras force-stop, con sesión expirada
o en un horario exacto.

## Validación

`flutter test test/background_delivery_test.dart` cubre SQLite y AES-GCM reales,
creación seguida de edición dependiente, subida de originales, cierre de sesión
durante una respuesta, revocación, HTTP 401, otro proyecto, lease concurrente y
límite de entrega. Usa un transporte HTTP sintético y no simula una prueba
física del planificador Android o Android Keystore. La comprobación en un
teléfono sigue siendo una prueba distinta.

APIs utilizadas: WorkManager `0.10.10` y las dependencias fijadas por el lock.
Referencias: [WorkManager API](https://pub.dev/documentation/workmanager/0.10.10/workmanager/Workmanager-class.html),
[personalización de tareas](https://docs.page/fluttercommunity/flutter_workmanager/customization)
y [SupabaseClient](https://pub.dev/documentation/supabase/latest/supabase/SupabaseClient-class.html).
