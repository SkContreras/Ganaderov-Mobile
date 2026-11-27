import 'dart:convert';

/// Build-time input and startup guard for the separate debug-only test app.
/// The client configuration contains only an anon/publicable key, never a
/// service-role key, user credentials, signing secret, or database password.
class TestBackendConfig {
  const TestBackendConfig._({
    required this.profile,
    required this.url,
    required this.publishableKey,
    required this.projectRef,
    required this.backendReady,
    required this.enableD4,
  });

  // A public project identifier, explicitly excluded from every test profile.
  static const productionProjectRef = 'vptsuhlnhtqxadztgdxn';
  static const localHosts = {'127.0.0.1', 'localhost', '10.0.2.2'};
  final String profile, url, publishableKey, projectRef;
  final bool backendReady, enableD4;

  factory TestBackendConfig.parse(
    Map<String, dynamic> source, {
    bool enableD4 = false,
    bool debugBuild = true,
  }) {
    if (!debugBuild) {
      throw const FormatException('El APK de pruebas sólo admite modo debug.');
    }
    const fields = {
      'profile',
      'url',
      'publishableKey',
      'projectRef',
      'backendReady',
    };
    if (source.keys.any((key) => !fields.contains(key))) {
      throw const FormatException(
        'La configuración cliente contiene campos no permitidos.',
      );
    }
    String text(String name) =>
        source[name] is String ? (source[name] as String).trim() : '';
    final profile = text('profile'), key = text('publishableKey');
    final uri = Uri.tryParse(text('url'));
    final projectRef = text('projectRef');
    final ready = source['backendReady'] == true;
    if (source['backendReady'] != null && source['backendReady'] is! bool) {
      throw const FormatException(
        'backendReady debe ser un booleano del informe de validación.',
      );
    }
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('La URL de pruebas no es un origen válido.');
    }
    if (uri.host == '$productionProjectRef.supabase.co' ||
        projectRef == productionProjectRef) {
      throw const FormatException(
        'El APK de pruebas no puede apuntar a producción.',
      );
    }
    switch (profile) {
      case 'local':
        if (uri.scheme != 'http' ||
            !localHosts.contains(uri.host) ||
            !uri.hasPort ||
            uri.port < 1024 ||
            uri.port > 65535 ||
            projectRef.isNotEmpty) {
          throw const FormatException(
            'El perfil local requiere un puerto explícito en localhost, 127.0.0.1 o 10.0.2.2.',
          );
        }
      case 'hosted':
        if (!RegExp(r'^[a-z0-9]{20}$').hasMatch(projectRef) ||
            uri.scheme != 'https' ||
            uri.host != '$projectRef.supabase.co' ||
            (uri.hasPort && uri.port != 443)) {
          throw const FormatException(
            'El perfil hosted requiere la referencia exacta de un proyecto de staging.',
          );
        }
      default:
        throw const FormatException('Selecciona el perfil local o hosted.');
    }
    if (key.startsWith('sb_publishable_') &&
        key.length > 'sb_publishable_'.length) {
      // Public keys are expected to be recoverable from a client application.
    } else {
      Map<String, dynamic>? claims;
      try {
        final parts = key.split('.');
        if (parts.length == 3) {
          claims = Map<String, dynamic>.from(
            jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
            ) as Map,
          );
        }
      } catch (_) {
        // Never include key material in a validation error or build log.
      }
      if (claims == null ||
          claims['role'] != 'anon' ||
          (profile == 'hosted' &&
              claims['ref'] != null &&
              claims['ref'] != projectRef)) {
        throw const FormatException(
          'Sólo se admite una clave publicable o un JWT anon del entorno de pruebas.',
        );
      }
    }
    if (enableD4 && !ready) {
      throw const FormatException(
        'D4 requiere un backend desechable validado antes de activar SYNC_UNIVERSAL_V1.',
      );
    }
    return TestBackendConfig._(
      profile: profile,
      url: text('url').replaceFirst(RegExp(r'/$'), ''),
      publishableKey: key,
      projectRef: projectRef,
      backendReady: ready,
      enableD4: enableD4,
    );
  }

  Map<String, String> get dartDefines => {
    'SUPABASE_URL': url,
    'SUPABASE_PUBLISHABLE_KEY': publishableKey,
    'D4_TEST_PROFILE': profile,
    'D4_TEST_PROJECT_REF': projectRef,
    'D4_TEST_BACKEND_READY': '$backendReady',
    'SYNC_UNIVERSAL_V1': '$enableD4',
    'SYNC_INCREMENTAL_V1': 'false',
    'SYNC_BACKGROUND_V1': 'false',
    'SYNC_JOURNEY_RPC_V1': 'false',
    'SYNC_EVENT_RPC_V1': 'false',
  };

  /// Safe to include beside the APK. The publishable key is deliberately omitted.
  Map<String, dynamic> get buildInfo => {
    'profile': profile,
    'apiUrl': url,
    'projectRef': projectRef,
    'backendReady': backendReady,
    'applicationId': 'com.ganaderov.mobile.d4test',
    'authCallback': 'com.ganaderov.mobile.d4test://auth/callback',
    'debugBuild': true,
    'syncUniversalV1': enableD4,
    'syncIncrementalV1': false,
    'syncBackgroundV1': false,
    'syncJourneyRpcV1': false,
    'syncEventRpcV1': false,
  };
}
