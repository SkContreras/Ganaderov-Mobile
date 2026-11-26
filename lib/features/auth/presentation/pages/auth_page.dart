import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/auth_gateway.dart';
import '../widgets/ranch_scene.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.auth, required this.mode, required this.onMode});
  final AuthGateway auth;
  final AuthMode mode;
  final ValueChanged<AuthMode> onMode;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false, _hidden = true;
  String? _message;
  bool _error = false;
  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }
  void _focusChanged() => setState(() {});
  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }
  void _switch(AuthMode mode) {
    if (_busy) return;
    _password.clear();
    _confirm.clear();
    setState(() { _message = null; _error = false; _hidden = true; });
    widget.onMode(mode);
  }
  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _message = null; _error = false; });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() {
        _error = true;
        _message = switch (e.code) {
          'invalid_credentials' => 'Correo o contraseña incorrectos.',
          'email_not_confirmed' => 'Confirma tu correo antes de iniciar sesión.',
          'over_email_send_rate_limit' => 'Espera un momento antes de solicitar otro correo.',
          'weak_password' => 'Elige una contraseña más segura.',
          _ => 'No se pudo completar la solicitud. Revisa tus datos e inténtalo nuevamente.',
        };
      });
    } catch (_) {
      if (mounted) setState(() { _error = true; _message = 'No se pudo completar la solicitud. Revisa tu conexión.'; });
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }
  void _info(String message) {
    if (mounted) setState(() { _message = message; _error = false; });
  }
  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    await _perform(() async {
      final email = _email.text.trim(), password = _password.text;
      switch (widget.mode) {
        case AuthMode.login:
          await widget.auth.login(email, password);
          break;
        case AuthMode.register:
          final active = await widget.auth.register(email, password);
          if (!active) _info('Revisa tu correo para confirmar tu cuenta.');
          break;
        case AuthMode.recovery:
          await widget.auth.recover(email);
          _info('Si existe una cuenta con ese correo, recibirás un enlace para cambiar la contraseña.');
          break;
        case AuthMode.reset:
          await widget.auth.reset(password);
          break;
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final login = mode == AuthMode.login;
    final reset = mode == AuthMode.reset;
    final recovery = mode == AuthMode.recovery;
    final confirm = mode == AuthMode.register || reset;
    final title = switch (mode) {
      AuthMode.login => 'Iniciar sesión',
      AuthMode.register => 'Crear cuenta',
      AuthMode.recovery => 'Recuperar contraseña',
      AuthMode.reset => 'Nueva contraseña',
    };
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Icon(Icons.agriculture, color: colors.primary, size: 34),
                        const SizedBox(width: 10),
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Ganaderov', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          Text('GESTIÓN GANADERA INTELIGENTE', style: TextStyle(fontSize: 10, letterSpacing: 1)),
                        ])),
                      ]),
                      const SizedBox(height: 18),
                      RanchScene(hideEyes: _focus.hasFocus),
                      const SizedBox(height: 22),
                      Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(login ? 'Accede a tu cuenta y administra tu rancho.' : recovery ? 'Te enviaremos un enlace a tu correo.' : reset ? 'Elige una nueva contraseña segura.' : 'Comienza a gestionar tu ganado.'),
                      const SizedBox(height: 20),
                      if (!reset) TextFormField(
                        controller: _email, enabled: !_busy,
                        decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder()),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        validator: (v) => (v ?? '').trim().contains('@') ? null : 'Introduce un correo válido.',
                      ),
                      if (!recovery) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password, focusNode: _focus, enabled: !_busy,
                          obscureText: _hidden, autocorrect: false, enableSuggestions: false,
                          autofillHints: [login ? AutofillHints.password : AutofillHints.newPassword],
                          decoration: InputDecoration(labelText: 'Contraseña', prefixIcon: const Icon(Icons.lock_outline), border: const OutlineInputBorder(),
                            suffixIcon: IconButton(tooltip: _hidden ? 'Mostrar contraseña' : 'Ocultar contraseña', onPressed: () => setState(() => _hidden = !_hidden), icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
                          validator: (v) => (v ?? '').isEmpty || (!login && (v ?? '').length < 8) ? (login ? 'Introduce tu contraseña.' : 'Usa al menos 8 caracteres.') : null,
                        ),
                      ],
                      if (confirm) ...[
                        const SizedBox(height: 14),
                        TextFormField(controller: _confirm, enabled: !_busy, obscureText: true, autocorrect: false, enableSuggestions: false,
                          decoration: const InputDecoration(labelText: 'Confirmar contraseña', border: OutlineInputBorder()),
                          validator: (v) => v == _password.text ? null : 'Las contraseñas no coinciden.'),
                      ],
                      if (login) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _busy ? null : () => _switch(AuthMode.recovery), child: const Text('¿Olvidaste tu contraseña?'))),
                      if (_message != null || widget.auth.notice != null) Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(_message ?? widget.auth.notice!, style: TextStyle(color: _error || _message == null ? colors.error : colors.primary)),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _busy ? null : _submit, child: Padding(padding: const EdgeInsets.all(12), child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(title))),
                      if (login) ...[
                        const SizedBox(height: 16),
                        const Center(child: Text('O continúa con')),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(onPressed: _busy ? null : () => _perform(() async { await widget.auth.social(true); _info('Completa el acceso en tu navegador.'); }), icon: const Text('G', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4285F4), fontSize: 20)), label: const Text('Google')),
                        OutlinedButton.icon(onPressed: _busy ? null : () => _perform(() async { await widget.auth.social(false); _info('Completa el acceso en tu navegador.'); }), icon: const Icon(Icons.facebook, color: Color(0xFF1877F2)), label: const Text('Facebook')),
                        TextButton(onPressed: _busy ? null : () => _switch(AuthMode.register), child: const Text('¿No tienes cuenta? Regístrate')),
                      ] else if (!reset) TextButton(onPressed: _busy ? null : () => _switch(AuthMode.login), child: const Text('Volver a iniciar sesión')),
                      if (reset) TextButton(onPressed: _busy ? null : () => _perform(widget.auth.logout), child: const Text('Cancelar y cerrar sesión')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
