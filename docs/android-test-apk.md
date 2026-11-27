# Ganaderov Pruebas: APK D4

Este paquete instala **Ganaderov Pruebas**, con identificador
`com.ganaderov.mobile.d4test`. Puede convivir con la aplicación normal. Es un APK
debug para probar el backend indicado en `build-info.json`; no es un release
firmado para distribución en tiendas.

## Qué contiene el artefacto

- `ganaderov-d4test.apk`: aplicación instalable, con firma debug comprobada.
- `SHA256SUMS`: huella del APK.
- `signing-certificate.txt`: certificado público usado para firmarlo.
- `build-info.json`: commits Mobile y Web, perfil, URL, flags y huella de la
  configuración del backend. No contiene la clave cliente.
- `verify_test_backend.py`: compara el backend recreado con el que requiere el APK.
- `configure_local_supabase.py`: configura el callback del backend local.

El APK sólo incorpora la clave publicable/anon necesaria para conectarse como
cliente. El constructor rechaza claves `secret`, `service_role`, tokens de usuario,
campos adicionales y la referencia productiva `vptsuhlnhtqxadztgdxn`. El perfil
local admite HTTP únicamente para `127.0.0.1`, `localhost` y `10.0.2.2`, con puerto
explícito. El perfil hospedado exige HTTPS y la referencia exacta de staging.

## Usar el APK con el backend local

**El backend desechable de GitHub Actions se apaga al terminar el build.** El APK
con perfil `local` necesita que reproduzcas el backend en tu computadora y lo
conectes al teléfono. No contiene un servidor y no apunta a un servicio de
staging permanente.

Requisitos: Docker en ejecución, Supabase CLI **2.75.0**, Python 3, `psql`, Git y
Android Platform Tools (`adb`). En Windows puede ejecutarse el backend desde WSL2
con Docker Desktop y usar `adb` desde PowerShell para el teléfono USB.

1. Extrae el artefacto y abre `build-info.json`. Conserva su `webBackendCommit` y
   `apiUrl`; se debe usar ese commit y ese puerto, no la versión más reciente por
   suposición.
2. Clona el repositorio Web en una carpeta de pruebas y cambia a ese commit:

   ```sh
   git clone https://github.com/SkContreras/Ganaderov.git Ganaderov-D4-local
   cd Ganaderov-D4-local
   git checkout <webBackendCommit-de-build-info.json>
   supabase init
   python3 <ruta-al-artefacto>/configure_local_supabase.py supabase/config.toml
   supabase start -x studio,imgproxy,edge-runtime,logflare,vector,supavisor,realtime,inbucket
   ```

3. Instala el esquema y las migraciones cuyo orden y hashes se comprueban en el
   manifiesto del commit. Estos comandos apuntan exclusivamente al PostgreSQL
   local en el puerto 54322:

   ```sh
   export PGHOST=127.0.0.1 PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres
   python3 scripts/check-backend-release.py --paths --include-base > /tmp/d4-migrations.txt
   while IFS= read -r sql; do
     psql -X -v ON_ERROR_STOP=1 -f "$sql" || exit 1
   done < /tmp/d4-migrations.txt
   psql -X -v ON_ERROR_STOP=1 -c "NOTIFY pgrst, 'reload schema';"
   ```

4. Ejecuta el mismo harness HTTP. Prueba Auth, RLS, operaciones D2/D3/D4,
   revocación y Storage, y sólo produce un perfil listo para D4 cuando termina
   correctamente:

   ```sh
   umask 077
   supabase status -o json > /tmp/d4-supabase-status.json
   GANADEROV_DISPOSABLE_DB=YES \
   GANADEROV_SUPABASE_STATUS=/tmp/d4-supabase-status.json \
   python3 tests/integration/http_e2e.py --keep-fixtures --output /tmp/d4-http
   python3 <ruta-al-artefacto>/verify_test_backend.py \
     <ruta-al-artefacto>/build-info.json /tmp/d4-http/client-config.json
   ```

   El último comando debe confirmar coincidencia. Si falla, la URL o la clave
   del backend recreado no coinciden con las del APK, o el harness no pasó.
   Genera otro APK con el nuevo `client-config.json` verificado. No se asume que
   dos instancias de Supabase generen claves iguales.

5. Activa la depuración USB del teléfono, conéctalo y autoriza la computadora.
   Para la URL usual `http://127.0.0.1:54321`, ejecuta:

   ```sh
   adb devices
   adb reverse tcp:54321 tcp:54321
   adb install -r <ruta-al-artefacto>/ganaderov-d4test.apk
   ```

   Si `apiUrl` usa otro puerto, sustituye ambos valores. En un emulador, un APK
   construido explícitamente para `10.0.2.2` utiliza ese alias del host.
   El callback autorizado es
   `com.ganaderov.mobile.d4test://auth/callback`.

6. Abre **Ganaderov Pruebas** e inicia sesión con una cuenta sintética del
   `fixtures.private.json` generado por tu propio harness local. Ese archivo
   contiene datos privados de pruebas y no se incluye en el artefacto público.
   Para probar offline, abre la galería con conexión primero, desactiva la
   conectividad y guarda un encuadre; el estado pendiente debe sobrevivir al
   reinicio. Reactiva la conexión para sincronizar.

La firma debug puede cambiar entre ejecuciones independientes de CI. Si Android
rechaza una actualización por firma distinta, desinstala sólo **Ganaderov
Pruebas** y vuelve a instalarla; se perderán los datos locales de esa aplicación
de pruebas. La aplicación normal usa otro identificador.

## Construcción reproducible

El workflow **Android test APK** se ejecuta al hacer push a
`feat/d4-test-apk`. Fija un commit Web, verifica su manifiesto, crea un Supabase
local desechable y exige que su harness HTTP pase antes de activar D4. Luego
genera la configuración cliente desde esa instancia, ejecuta las pruebas Flutter
y compila la variante debug `d4test`.

También admite ejecución manual con el JSON cliente de una instancia ya
verificada. El input `enable_d4_sync` es `false` por defecto y requiere
`backendReady: true` para activarse. Ejemplo de formato, con una clave ficticia:

```json
{
  "profile": "local",
  "url": "http://127.0.0.1:54321",
  "publishableKey": "CLAVE_ANON_DEL_BACKEND_DESECHABLE",
  "backendReady": true
}
```

Para `hosted`, añade `projectRef` y usa
`https://<projectRef>.supabase.co`; debe ser staging, nunca producción.

El build usa Flutter **3.50.1**, Dart **3.14.0**, Java **17**, Android API **36**,
Build Tools **36.0.0**, NDK **28.2.13676358** y el lock de dependencias. El mínimo
de Android proviene de esa versión de Flutter: API **24**. Para reproducirlo
localmente con el SDK Android instalado:

```sh
flutter pub get --enforce-lockfile
mkdir -p .test-apk
D4_CLIENT_CONFIG_FILE=/ruta/client-config.json ENABLE_D4_SYNC=true \
  dart run tool/prepare_test_apk.dart .test-apk/defines.json .test-apk/build-info.json
flutter build apk --debug --flavor d4test --no-pub \
  --dart-define-from-file .test-apk/defines.json
```

El resultado estará en
`build/app/outputs/flutter-apk/app-d4test-debug.apk`. La reproducción fija fuentes,
configuración y herramientas; la firma debug y metadatos temporales pueden
cambiar los bytes del APK entre máquinas. La variante predeterminada sigue
siendo `production`, con el identificador y la política HTTPS de Ganaderov.

## Parámetros de compilación

| Parámetro | Uso en el APK de pruebas |
|---|---|
| `SUPABASE_URL` | URL exacta del backend verificado |
| `SUPABASE_PUBLISHABLE_KEY` | Clave publicable o JWT con rol `anon` |
| `D4_TEST_PROFILE` | `local` o `hosted` |
| `D4_TEST_PROJECT_REF` | Referencia de staging; vacío para local |
| `D4_TEST_BACKEND_READY` | Evidencia de que el harness terminó correctamente |
| `SYNC_UNIVERSAL_V1` | D4 explícitamente activado tras la validación |
| `SYNC_INCREMENTAL_V1` | `false` |
| `SYNC_BACKGROUND_V1` | `false` |
| `SYNC_JOURNEY_RPC_V1` | `false`; los flujos de prueba usan el motor universal |
| `SYNC_EVENT_RPC_V1` | `false`; los flujos de prueba usan el motor universal |

No hay contraseñas de usuario, claves de servicio ni claves de firma de
producción en estos parámetros. Los permisos reales continúan verificándose en
Auth, RLS y las funciones del servidor de pruebas.
