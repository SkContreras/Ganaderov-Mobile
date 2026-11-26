# Navegación principal

Cinco ramas persistentes mediante StatefulShellRoute.indexedStack: Inicio, Ganado, Jornadas, Análisis y Ajustes. En pantallas anchas se usa NavigationRail. Las rutas están protegidas por la misma sesión de autenticación. Ajustes muestra el correo de la sesión y permite cerrar sesión local con confirmación.

Los indicadores del dashboard son marcadores (—), no datos reales. Ganado, Jornadas y Análisis son pantallas de preparación explícitas; no consultan ni escriben datos. No se modifica Supabase ni la web.

Validación: flutter analyze; flutter test; en Android probar cada pestaña, volver al inicio, rotar, cerrar sesión, iniciar sesión de nuevo y verificar que no aparezcan pantallas protegidas sin sesión.
