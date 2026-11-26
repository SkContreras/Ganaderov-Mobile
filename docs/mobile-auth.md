# Autenticación móvil (Android)

En Supabase Auth > URL Configuration > Redirect URLs, añadir exactamente:

`com.ganaderov.mobile://auth/callback`

Conservar las URLs de la web y los proveedores existentes. No cambiar Site URL ni las credenciales de Google/Facebook. OAuth abre el navegador externo y vuelve por enlace profundo; la interfaz Flutter no usa WebView. El SDK v2 conserva la sesión. La clave publishable se pasa por dart-define; nunca usar service_role. La protección de rutas no sustituye RLS.

Pruebas manuales en emulador: cuenta existente, contraseña incorrecta, registro y confirmación, Google, Facebook, recuperación y nueva contraseña, reinicio de app, cierre de sesión, pérdida de internet. Confirmar que las plantillas de correo respetan la URL de confirmación y que el navegador vuelve a la app. PKCE puede requerir abrir el enlace en el mismo dispositivo. No se han modificado las plantillas ni el backend.

Compilar con el emulador cerrado, usando los mismos dart-define de Supabase del proyecto. Luego instalar app-debug.apk con adb install -r. Ejecutar flutter analyze y flutter test antes de integrar. La ilustración es una adaptación ligera mediante CustomPainter, no una copia exacta ni una animación completa de la web.
