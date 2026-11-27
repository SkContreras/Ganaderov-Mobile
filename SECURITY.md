# Seguridad

## Reportar una vulnerabilidad

Si descubres un problema de seguridad, no publiques tokens, datos de ranchos, fotografías privadas, credenciales ni instrucciones de explotación en una issue pública. Usa el reporte privado de GitHub si está habilitado; de lo contrario, solicita un canal privado al mantenedor [SkContreras](https://github.com/SkContreras) sin incluir detalles sensibles.

Incluye versión, commit, alcance, pasos reproducibles en un entorno autorizado e impacto. No realices pruebas sobre cuentas o ranchos ajenos.

## Principios

- Claves publicables en cliente; claves privilegiadas exclusivamente en servidor.
- RLS y permisos RPC como frontera de autorización.
- Sesiones y datos locales protegidos; no compartir copias de bases reales.
- Verificar integridad y firma de APK antes de distribuir.

No se promete una ventana de soporte o plazo de respuesta que no haya sido establecido por el mantenedor.
