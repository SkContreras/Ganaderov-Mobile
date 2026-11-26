# Pesajes y tratamientos

Registros individuales de animales activos para owner/admin/worker. Siete tipos autorizados por el trigger web. Guarda actor autenticado, fecha, peso o etiqueta y notas. Worker modifica exclusivamente events; manager actualiza auditoría de ficha. Lee versión actual antes de agregar y condiciona update por modified_at; reintento con UUID estable mientras permanece abierto el formulario. Sin migraciones.

No incluye corrección/eliminación de eventos, jornadas masivas, advertencias de crecimiento de la web, dosis estructuradas ni modo offline. Si se abandona el formulario tras respuesta ambigua, revisar historial antes de volver a registrar; el UUID no persiste al cerrar. Probar con dos cuentas, verificar payload y sincronización web, conflicto, doble pulsación, rechazo de archivo y actualización del dashboard. No se han ejecutado pruebas de Flutter ni escrito datos reales.
