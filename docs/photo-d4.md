# Encuadre directo de fotografías en Android

El selector muestra miniaturas, nombre y señal de foto principal. Para añadir
imágenes se conservan Cámara y Galería, con una sección visual propia y el límite
de 10 MiB. La selección continúa usando el picker nativo y conserva los bytes
originales.

## Ajustar y guardar

- Arrastra la imagen dentro del marco para moverla.
- Usa dos dedos para ampliar o reducir; el punto entre los dedos conserva su lugar.
- Los botones **Acercar fotografía** y **Alejar fotografía** ofrecen el mismo
  control sin hacer el gesto de pinza. Las acciones de accesibilidad del marco
  permiten mover la imagen en cuatro direcciones.
- **Restablecer encuadre** vuelve a 50 % horizontal, 50 % vertical y zoom 1.
- **Guardar** registra una sola operación. **Cancelar**, cerrar el diálogo o volver
  atrás descarta la previsualización sin escribir metadatos.

El zoom se limita a 1–3 y el desplazamiento se ajusta a los bordes de la imagen;
el marco permanece cubierto. Cambiar entre uno y dos dedos conserva el encuadre.
La guía de tercios aparece durante la manipulación. En pantallas pequeñas el
contenido puede desplazarse fuera del marco y las acciones de guardado permanecen
visibles. Arrastrar dentro del marco mueve la fotografía, incluso cuando el
diálogo tiene scroll. El editor toma la proporción real de la foto principal al
abrir, por lo que muestra la misma zona de la imagen que la galería.

## Contrato y recursos

`cropX` y `cropY` siguen siendo porcentajes 0–100; `cropZoom` sigue siendo 1–3.
La representación conserva `cover` más el mismo alineamiento y origen de escala
que Web. La conversión de los gestos usa las dimensiones del marco y de la imagen
para preservar esos valores compartidos. No se genera un archivo recortado ni se
cambian UUID, revisiones, persistencia o protocolo de sincronización.

La edición conserva el inventario con el que se abrió. Si una actualización
cambia la foto confirmada mientras el diálogo está abierto, el repositorio
rechaza el guardado y pide actualizar; no sustituye esa foto silenciosamente.

Las miniaturas se decodifican dentro de 320×320, el editor dentro de 1200×1200 y
el visor del original dentro de 2048×2048, preservando la proporción. El editor
espera a conocer las dimensiones antes de habilitar gestos y Guardar. Conserva el
límite de una operación de fotografía sin resolver por animal y las reglas de
D4 para trabajar offline. Esta modificación no requiere una migración local ni
una nueva dependencia.

## Validación

```sh
flutter test test/photo_crop_geometry_test.dart test/photo_crop_editor_test.dart test/photo_gallery_test.dart test/photo_crop_test.dart test/photo_repository_test.dart
```

Las pruebas comprueban geometría horizontal/vertical, conservación del punto de
pinza, límites, dos punteros reales del harness Flutter, transición a un dedo,
zoom accesible, cancelación, guardado único offline, actualización concurrente
y pantallas pequeñas con texto ampliado. Son pruebas de widget y repositorio;
no sustituyen la verificación de
gestos, lector de pantalla y picker en un teléfono Android físico.
