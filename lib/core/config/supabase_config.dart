import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'secure_session_storage.dart';
import 'test_backend_config.dart';

abstract final class SupabaseConfig {
  static const universalSyncEnabled=bool.fromEnvironment('SYNC_UNIVERSAL_V1');
  static const incrementalSyncEnabled=bool.fromEnvironment('SYNC_INCREMENTAL_V1');
  static const backgroundSyncEnabled = bool.fromEnvironment('SYNC_BACKGROUND_V1');
  static const journeyRpcEnabled = bool.fromEnvironment('SYNC_JOURNEY_RPC_V1');
  static const eventRpcEnabled = bool.fromEnvironment('SYNC_EVENT_RPC_V1');
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static Future<void> initialize() async {
    if(appFlavor=='d4test'){
      TestBackendConfig.parse({
        'profile':const String.fromEnvironment('D4_TEST_PROFILE'),
        'url':url,
        'publishableKey':publishableKey,
        'projectRef':const String.fromEnvironment('D4_TEST_PROJECT_REF'),
        'backendReady':const bool.fromEnvironment('D4_TEST_BACKEND_READY'),
      },enableD4:universalSyncEnabled,debugBuild:kDebugMode);
    }
    if (url.isEmpty || publishableKey.isEmpty) {
      throw StateError(
        'Supabase is not configured. Provide SUPABASE_URL and '
        'SUPABASE_PUBLISHABLE_KEY with --dart-define.',
      );
    }

    await Supabase.initialize(url: url, publishableKey: publishableKey,authOptions:FlutterAuthClientOptions(localStorage:SecureSessionStorage(url)));
  }
}
