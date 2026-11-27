import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/config/test_backend_config.dart';

String fixtureJwt(String role, {String? ref}) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'HS256'})}.${encode({'role': role, 'ref': ?ref})}.fixture';
}

Map<String, dynamic> localConfig() => {
  'profile': 'local',
  'url': 'http://127.0.0.1:54321',
  'publishableKey': fixtureJwt('anon'),
  'backendReady': false,
};

void main() {
  test('local configuration leaves every sync flag off by default and does not expose its key in metadata', () {
    final config = TestBackendConfig.parse(localConfig());
    expect(config.dartDefines['SUPABASE_URL'], 'http://127.0.0.1:54321');
    for (final flag in config.dartDefines.keys.where(
      (key) => key.startsWith('SYNC_'),
    )) {
      expect(config.dartDefines[flag], 'false');
    }
    expect(
      jsonEncode(config.buildInfo),
      isNot(contains(config.publishableKey)),
    );
    expect(config.buildInfo['applicationId'], 'com.ganaderov.mobile.d4test');
  });
  test('D4 is opt-in and requires the validated backend report', () {
    expect(
      () => TestBackendConfig.parse(localConfig(), enableD4: true),
      throwsFormatException,
    );
    final config = TestBackendConfig.parse({
      ...localConfig(),
      'backendReady': true,
    }, enableD4: true);
    expect(config.dartDefines['SYNC_UNIVERSAL_V1'], 'true');
    expect(config.dartDefines['SYNC_INCREMENTAL_V1'], 'false');
    expect(config.dartDefines['SYNC_BACKGROUND_V1'], 'false');
  });
  test('production reference is rejected even when declared as the expected hosted project', () {
    final config = {
      ...localConfig(),
      'profile': 'hosted',
      'url': 'https://${TestBackendConfig.productionProjectRef}.supabase.co',
      'projectRef': TestBackendConfig.productionProjectRef,
      'backendReady': true,
    };
    expect(
      () => TestBackendConfig.parse(config, enableD4: true),
      throwsFormatException,
    );
    expect(
      () => TestBackendConfig.parse({
        ...localConfig(),
        'url':
            'http://${TestBackendConfig.productionProjectRef}.supabase.co:54321',
      }),
      throwsFormatException,
    );
  });
  test('local backend accepts only explicit loopback/emulator ports in a debug build', () {
    for (final host in ['localhost', '127.0.0.1', '10.0.2.2']) {
      expect(
        TestBackendConfig.parse({...localConfig(), 'url': 'http://$host:54321'})
            .profile,
        'local',
      );
    }
    for (final url in [
      'http://192.168.0.2:54321',
      'http://example.com:54321',
      'http://127.0.0.1',
      'http://127.0.0.1:54321/rest/v1',
      'http://user:password@127.0.0.1:54321',
      'http://127.0.0.1:54321?target=prod',
    ]) {
      expect(
        () => TestBackendConfig.parse({...localConfig(), 'url': url}),
        throwsFormatException,
      );
    }
    expect(
      () => TestBackendConfig.parse(localConfig(), debugBuild: false),
      throwsFormatException,
    );
  });
  test('server keys, user tokens, unknown fields and malformed credentials are rejected', () {
    for (final key in [
      'sb_secret_never-allowed',
      fixtureJwt('service_role'),
      fixtureJwt('authenticated'),
      'not-a-key',
    ]) {
      expect(
        () =>
            TestBackendConfig.parse({...localConfig(), 'publishableKey': key}),
        throwsFormatException,
      );
    }
    expect(
      () => TestBackendConfig.parse({
        ...localConfig(),
        'service_role': 'must-not-be-present',
      }),
      throwsFormatException,
    );
    expect(
      () => TestBackendConfig.parse({...localConfig(), 'backendReady': 'true'}),
      throwsFormatException,
    );
  });
  test(
    'hosted profile binds HTTPS to the audited staging ref and anon claim',
    () {
      const ref = 'abcdefghijklmnopqrst';
      final input = {
        ...localConfig(),
        'profile': 'hosted',
        'url': 'https://$ref.supabase.co/',
        'projectRef': ref,
        'publishableKey': fixtureJwt('anon', ref: ref),
      };
      expect(TestBackendConfig.parse(input).url, 'https://$ref.supabase.co');
      expect(
        TestBackendConfig.parse({
          ...input,
          'publishableKey': 'sb_publishable_fixture',
        }).profile,
        'hosted',
      );
      expect(
        () => TestBackendConfig.parse({
          ...input,
          'publishableKey': fixtureJwt('anon', ref: 'other-ref'),
        }),
        throwsFormatException,
      );
      expect(
        () => TestBackendConfig.parse({
          ...input,
          'url': 'http://$ref.supabase.co',
        }),
        throwsFormatException,
      );
    },
  );
}
