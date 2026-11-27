# Contribuir a Ganaderov Mobile

Gracias por tu interés. Antes de iniciar un cambio amplio, describe el problema y alcance en una issue. Crea una rama desde main, limita el cambio a una responsabilidad y abre un pull request con evidencia.

## Validación

```sh
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```

Para cambios Android, compila y prueba el sabor correspondiente en un dispositivo o emulador. Para sincronización, usa un backend de pruebas autorizado; nunca datos de producción. Conserva compatibilidad de contratos, UUID, revisiones y migraciones locales. No incluyas secretos ni datos personales en commits, capturas o logs.

Describe las pruebas realizadas, limitaciones, cambios de configuración y riesgos. Evita afirmar que una función está validada si solo se revisó su código.
