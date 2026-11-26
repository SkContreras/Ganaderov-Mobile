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

## Validación

```sh
flutter test
flutter analyze
```
# Ganaderov-Mobile
