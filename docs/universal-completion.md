# Captura universal y trabajo sin conexión

Estas funciones requieren `SYNC_UNIVERSAL_V1=true`, almacenamiento local protegido
y las migraciones del contrato universal correspondiente en el backend. El cliente
no instala SQL ni activa cambios en producción. Las entregas en segundo plano se
documentan en [background-delivery-v1.md](background-delivery-v1.md).

## Preparar el trabajo

Abre el inventario con conexión. La descarga consulta `sync_read_entities` por
lotes de hasta 100 entidades y conserva una revisión únicamente cuando el contenido
devuelto coincide con el inventario. **Preparar trabajo sin conexión** permite
comprobar la preparación explícitamente; si algún dato cambió durante la descarga,
se pide actualizar el inventario. Abre también las jornadas que vas a utilizar.

La copia verificada de la membresía, el inventario y las revisiones duran como
máximo 24 horas. Una entidad sin revisión confirmada, una copia vencida, un cambio
de cuenta/rancho o un permiso insuficiente impiden capturar una modificación.
Los identificadores de versión son siempre revisiones reales del servidor.

## Funciones móviles

| Función | Captura disponible | Permisos |
| --- | --- | --- |
| Fichas | Alta, edición, archivo y restauración | Propietario o administrador |
| Actividades independientes | Alta; corrección de fecha, producto, observaciones y peso; eliminación con motivo | Corrección/eliminación: propietario o administrador |
| Notas y otras actividades | Alta con tipo fijo; notas no vacías | Propietario o administrador |
| Jornadas | Alta, incorporación de animales, asistencia, cierre incompleto/completo y reanudación | Cierre/reanudación y jornadas personalizadas: propietario o administrador |
| Configuración | Módulos, campos, obligatoriedad, etiquetas, niveles, visibilidad y listas compartidas | Propietario o administrador |

Los trabajadores conservan los tipos de captura operativa autorizados. Las
actividades producidas por una jornada se corrigen mediante su jornada. El editor
de historial conserva el tipo y autor original y exige un motivo para cada nueva
corrección o eliminación. Las operaciones antiguas de corrección de peso ya
persistidas siguen enviando exactamente su cuerpo original.

Las fichas nuevas muestran **Por asignar** hasta descargar el ID interno asignado
por el servidor. Para editar otros datos y cambiar a la vez entre activo y archivo,
guarda primero la edición y después el cambio de estado. Cada paso queda separado
y puede depender del anterior sin conexión.

En **Ajustes → Configuración del ganado** se editan los cuatro módulos, los 31
campos y las cinco listas (razas, lotes, potreros, corrales y estados). La
identificación básica y los campos operativos automáticos mantienen sus
restricciones. Los valores internos de las opciones no se renombran; se editan sus
etiquetas. No se elimina ni desactiva una opción utilizada por el inventario local,
y se mantiene al menos un estado activo. El backend vuelve a validar el conjunto
contra su inventario actual. Los niveles del formulario y la visibilidad de las
fichas se aplican también en Mobile; la preferencia de columnas se comparte con la
tabla Web.

## Dependencias y confirmación

Se puede crear una ficha y capturar actividades sobre ella antes de conectarse.
También se puede crear una jornada, registrar asistencias, cerrarla y reanudarla sin
esperar la confirmación de los pasos anteriores. La aplicación guarda cada intención
con UUID estable en un borrador cifrado independiente de la copia confirmada.

Un borrador que depende de otro no se convierte en operación enviable hasta tener
el recibo exitoso de todas sus dependencias. Cuando modifica la misma entidad,
utiliza la revisión exacta de ese recibo. El cuerpo se sella antes de su primer
envío y los reintentos no cambian ni su UUID ni su revisión. Cerrar y abrir la app
conserva las dependencias, los cuerpos sellados y las previsualizaciones.

Una dependencia rechazada, en conflicto o archivada bloquea explícitamente a sus
hijas. **Ajustes → Sincronización** permite inspeccionar los datos capturados y su
motivo de bloqueo. Se pueden archivar borradores que ya no se necesitan; una
resolución manual del padre no enlaza ni descarta automáticamente sus hijas.
Revisa esas capturas y vuelve a registrarlas a partir del estado confirmado cuando
corresponda. No se recalculan revisiones automáticamente para evitar conflictos.

La copia confirmada nunca incorpora la previsualización pendiente. Una descarga
iniciada después de conocer un recibo confirmado puede retirar esa previsualización.
La decisión usa el conjunto de UUID confirmados al iniciar la descarga, sin depender
de comparar relojes del dispositivo.

## Persistencia y compatibilidad

SQLite migra a versión 12. Las tablas `universal_drafts` y `entity_revisions`
autentican proyecto, usuario, rancho y entidad/UUID mediante el cifrado local.
La migración conserva los cuerpos antiguos de la cola. El worker y la app abierta
usan el mismo `UniversalSync.flush`, las mismas dependencias y los mismos adjuntos.
Las filas antiguas sin procedencia de proyecto no se envían desde el worker.

El comportamiento de fotografías D4 permanece documentado en el README: una
operación de fotografía sin resolver por animal, originales cifrados y revisión
real. La ampliación de dependencias de esta entrega cubre fichas, actividades,
configuración y jornadas.

## Validación

```sh
flutter test test/universal_drafts_test.dart test/offline_completion_repository_test.dart test/completion_widgets_test.dart test/background_delivery_test.dart
flutter test
flutter analyze --no-fatal-infos
```

Las pruebas de repositorio ejercitan SQLite y cifrado reales; su transporte simulado
permite verificar que la captura desconectada hace cero solicitudes y que cada
revisión procede del recibo. La integración HTTP adicional vive en
`Ganaderov/tests/integration/mobile/d4_repository_real_test.dart`: utiliza Auth,
RPC, Storage y el repositorio reales contra una instancia local desechable, bloquea
orígenes externos y falla si falta su manifiesto privado de fixtures.
