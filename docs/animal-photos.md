# Fotografías privadas

Cámara/galería con image_picker, JPEG/PNG/WebP hasta 10 MB, reducción solicitada a 1600 px, descarga autenticada del bucket animal-photos, ruta owner_id/animal_id/photo_id y metadatos compatibles con la web. Miembros consultan; administradores y propietario agregan y eligen principal. Conserva eventos y proyecciones, actualiza modified_at con condición optimista y animal.updatedAt para sincronización web.

No se elimina ningún objeto desde Android en esta fase: si falla la actualización tras subir, puede quedar un objeto huérfano. La web ya limpia objetos no referenciados durante sincronización, lo que también implica una carrera posible entre subida y limpieza web concurrente. Evitar sincronización simultánea durante pruebas. No se implementa edición de encuadre, eliminación ni caché offline. El emulador requiere cámara virtual o imagen en galería. Verificar subida, lectura desde web, principal, sesión worker y errores de red antes de fusionar.
