# Dashboard con datos reales

Solo lectura mediante la sesión del usuario. Usa get_my_ranch_context, ranch_animal_configs y animal_sync_records. Aplica owner_id obtenido del contexto y RLS existente; comprueba nuevamente la membresía antes de mostrar datos. Excluye borrados, aplica estados personalizados y cuenta animales con al menos un evento weight. Paginación por animal_id. Las últimas cinco actividades corresponden a animales activos sincronizados.

No se guarda caché persistente ni se muestran cifras antiguas tras un error; refrescar deslizando o con el botón. El modo offline, creación de ranchos y el inventario móvil siguen pendientes. No se implementa fallback de cuentas legacy para evitar mostrar datos sin membresía verificable. Las consultas no constituyen una instantánea transaccional si hay escrituras simultáneas.

Validar con cuentas owner/admin/worker, sin rancho y pendiente, inventario vacío, animales archivados, estados personalizados, múltiples pesos y más de 200 filas. Comparar con la web después de sincronizarla. Probar desconexión, reintento y cierre de sesión durante carga. No hay migraciones ni cambios de RLS.
