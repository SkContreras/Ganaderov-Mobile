# Ganaderov

Aplicación móvil para la gestión ganadera, construida con Flutter.

## Arquitectura

El punto de entrada solo inicia la aplicación. La configuración global, las
capacidades compartidas y cada funcionalidad viven separadas para evitar que
`main.dart` se convierta en el lugar donde reside toda la aplicación.

```text
android/
assets/
  fonts/
  icons/
  images/
lib/
  main.dart
  app.dart
  core/
    config/
    database/
    network/
    router/
    sync/
    theme/
    utils/
  features/
    auth/
    dashboard/
    finances/
    health/
    livestock/
    profile/
    reproduction/
    settings/
  shared/
    models/
    services/
    widgets/
test/
```

`core` contiene infraestructura transversal; `shared` contiene piezas
reutilizables sin pertenencia a una funcionalidad concreta. Cada módulo de
`features` puede organizarse por capas según lo necesite:

```text
feature_name/
  data/          # Fuentes de datos, DTO y repositorios concretos
  domain/        # Entidades, contratos y casos de uso
  presentation/  # Pantallas, widgets y estado de UI
```

No es necesario crear todas las capas por adelantado: se añaden cuando la
funcionalidad las requiere. El enrutado central está en
`core/router/app_router.dart`, el tema en `core/theme/app_theme.dart` y la
pantalla inicial está implementada en `features/dashboard/presentation/`.

## Desarrollo

```sh
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-supabase-publishable-key
```

La aplicación requiere `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` al iniciarse. Pasa
los valores de tu proyecto mediante `--dart-define`; no guardes credenciales
reales en el repositorio. La clave publicable está pensada para clientes, pero los
permisos deben protegerse con políticas RLS en Supabase.

## Firma de Android para producción

Los builds `release` no usan la firma de depuración. Para firmarlos, crea un
keystore y configura `android/key.properties` (este archivo está excluido de
Git) con estos campos:

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=../upload-keystore.jks
```

Guarda el keystore y sus contraseñas de forma segura. Sin `key.properties`, el
build `release` queda sin firmar y no está listo para publicar.

## APK de pruebas D4

La variante `d4test` se instala como **Ganaderov Pruebas**, separada de la
aplicación normal. El workflow `Android test APK` construye un APK debug después
de validar un backend local desechable y comprueba paquete, callback y firma.
La configuración productiva está expresamente excluida. Consulta
[la guía de instalación y reproducción](docs/android-test-apk.md), incluida la
conexión por `adb reverse` y la comprobación de que un backend recreado corresponde
al APK. La variante predeterminada sigue siendo `production`.

## Validación

```sh
flutter test
flutter analyze
```

## Captura universal sin conexión

El inventario, los eventos históricos, las jornadas y la configuración utilizan
capturas locales cifradas y dependencias durables. Los borradores dependientes
esperan los recibos confirmados para sellar su revisión antes del primer envío.
Consulta [la guía de uso y validación](docs/universal-completion.md), incluidos
permisos, preparación de revisiones, plazo de 24 horas y resolución de conflictos.
La versión actual de la base local es 12.

## D4: encuadre y galería sin conexión

Con `--dart-define=SYNC_UNIVERSAL_V1=true`, abre las fotografías con conexión
una vez para guardar sus originales y la revisión confirmada de sus metadatos.
Después, propietarios y administradores pueden ajustar el encuadre, elegir la
principal o quitar una fotografía sin conexión mientras la sesión y la copia
local del inventario sigan vigentes. Se conserva el plazo de 24 horas del modo
sin conexión; una revisión desconocida o vencida requiere volver a abrir la
fotografía con conexión. Las imágenes antiguas sin `animalId` interno se aceptan
únicamente cuando su ruta y el padre confirmado corresponden al animal.

Los deslizadores muestran una previsualización y **Guardar** registra una sola
operación. La previsualización y el estado pendiente se reconstruyen desde la
cola cifrada después de cerrar y abrir la aplicación. El inventario confirmado
se guarda por separado y nunca recibe una revisión inventada a partir de esa
previsualización. Se permite **una operación de fotografía sin resolver por
animal**: los controles quedan deshabilitados hasta confirmar el cambio o
resolverlo en **Ajustes → Sincronización**. Esto también se aplica a las fotos
nuevas pendientes de subir. Un conflicto requiere revisión explícita; no se
recalcula automáticamente su revisión. La confirmación mantiene la vista local
hasta completar una descarga del inventario iniciada después del recibo.

Los originales JPEG, PNG y WebP de hasta 10 MiB se conservan sin recortar ni
recomprimir. Su caché está cifrada y separada por proyecto, cuenta y rancho, con
un presupuesto global de 50 MiB de contenido cifrado y expulsión de los archivos
menos utilizados. Las fotografías expulsadas deben abrirse con conexión otra
vez. Los adjuntos pendientes de subir se conservan en la cola hasta confirmarse;
se procesan de uno en uno para limitar la memoria. La decodificación para mostrar
imágenes limita ambos ejes a 320 píxeles en miniaturas, 1200 en la galería/editor
y 2048 en el visor, sin modificar los bytes originales.

D4 introdujo la versión 11 de la base local. El contrato de operaciones compartido está
en `contracts/sync/v1/operation.schema.json` y contiene las mismas 20 acciones
que Web D4. El servidor requiere las migraciones correspondientes del repositorio
Ganaderov; estos cambios de cliente no instalan SQL ni modifican producción.

Pruebas específicas:

```sh
flutter test test/photo_store_test.dart test/photo_repository_test.dart test/photo_gallery_test.dart test/photo_crop_test.dart test/animal_photos_test.dart
```
# Ganaderov-Mobile
