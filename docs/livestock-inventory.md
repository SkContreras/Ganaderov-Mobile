# Inventario móvil — consulta

Utiliza el mismo repositorio de lectura para dashboard e inventario, filtrado por owner_id del contexto verificado y RLS existente. Activos y archivo respetan estados personalizados; las eliminaciones lógicas no aparecen. Búsqueda local sobre campos comunes, fichas y pesajes ordenados por fecha, historial de actividades. No guarda caché persistente. Las fotos privadas, configuración completa de visibilidad de campos, edición, altas, baja/reactivación y escrituras offline quedan pendientes. La ficha usa una selección fija de campos registrados, no reproduce aún todos los módulos configurables de la web.

Pruebas: flutter analyze, flutter test y comparación con inventario web sincronizado, cuenta worker, estados personalizados, eliminación lógica, búsqueda, navegación de ficha, desconexión y cierre de sesión. No se modifican tablas ni políticas.
