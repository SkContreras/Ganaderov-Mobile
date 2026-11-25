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
flutter test
flutter analyze
```
