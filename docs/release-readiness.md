# Estabilización: requisitos y pendientes

El cierre móvil requiere instalar backend/finish_journey.sql en staging, comprobar RLS y luego producción. RPC SECURITY INVOKER, únicamente owner/admin; conserva autoría de las atenciones y usa IDs de eventos deterministas. Toda la operación es una transacción; un conflicto aborta el cierre. No modifica triggers existentes. No evalúa pronósticos ni cambia auditoría de ficha. No habilita cierre por trabajadores: el trigger actual exige que el actor de cada evento sea el usuario autenticado. No ejecutar en producción sin probar rollback, cierre completo/parcial, duplicados, permisos, concurrencia y sincronización web.

Outbox: descartar requiere confirmación y no borra historial remoto. No reintentar manualmente creando UUID nuevo si el resultado fue ambiguo. Aún se requiere resolver conflictos de contenido de forma explícita.

Pendientes de producción: WorkManager con sesión segura y concurrencia entre isolates; configuración de campos, edición de eventos, eliminación segura de fotos, reanudación de jornadas, pruebas de integración, accesibilidad, cifrado local y firma de distribución. No se declara lista para publicar.