import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';

/// A bounded copy of the foreground access credential, never a refresh token.
/// The server still verifies its signature, membership and operation permissions.
class BackgroundCredential {
  const BackgroundCredential({
    required this.userId,
    required this.accessToken,
    required this.expiresAt,
    required this.url,
    required this.generation,
  });

  final String userId, accessToken, url, generation;
  final int expiresAt;

  bool usableAt(DateTime now) =>
      expiresAt * 1000 > now.millisecondsSinceEpoch + 60000;

  bool sameGrant(BackgroundCredential other) =>
      userId == other.userId &&
      url == other.url &&
      generation == other.generation &&
      expiresAt == other.expiresAt &&
      accessToken == other.accessToken;

  Map<String, dynamic> toJson() => {
    'schemaVersion': 2,
    'userId': userId,
    'accessToken': accessToken,
    'expiresAt': expiresAt,
    'url': url,
    'generation': generation,
  };

  static BackgroundCredential? parse(
    String? raw, {
    required String project,
    DateTime? now,
  }) {
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['schemaVersion'] != 2 ||
          data['url'] != project ||
          data['userId'] is! String ||
          (data['userId'] as String).isEmpty ||
          data['accessToken'] is! String ||
          data['generation'] is! String ||
          (data['generation'] as String).isEmpty ||
          data['expiresAt'] is! int) {
        return null;
      }
      final token = data['accessToken'] as String;
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      // These checks bind the local queue to the actual credential. They do not
      // replace the signature verification performed by Supabase.
      if (claims is! Map ||
          claims['sub'] != data['userId'] ||
          claims['role'] != 'authenticated' ||
          claims['exp'] is! int ||
          data['expiresAt'] > claims['exp']) {
        return null;
      }
      final credential = BackgroundCredential(
        userId: data['userId'] as String,
        accessToken: token,
        expiresAt: data['expiresAt'] as int,
        url: project,
        generation: data['generation'] as String,
      );
      return credential.usableAt(now ?? DateTime.now()) ? credential : null;
    } catch (_) {
      return null;
    }
  }
}

class BackgroundSession {
  static const _storage = FlutterSecureStorage();
  static const _key = 'ganaderov.background.access.v2';
  static const _legacyKey = 'ganaderov.background.access.v1';

  static bool get enabled =>
      SupabaseConfig.backgroundSyncEnabled &&
      (SupabaseConfig.universalSyncEnabled || SupabaseConfig.eventRpcEnabled);

  static Future<void> clear() async {
    await _storage.delete(key: _key);
    await _storage.delete(key: _legacyKey);
  }

  static Future<void> publish(Session? session) async {
    if (!enabled || session == null || session.expiresAt == null) {
      await clear();
      return;
    }
    final value = BackgroundCredential(
      userId: session.user.id,
      accessToken: session.accessToken,
      expiresAt: session.expiresAt!,
      url: SupabaseConfig.url,
      generation: const Uuid().v4(),
    );
    final encoded = jsonEncode(value.toJson());
    if (BackgroundCredential.parse(encoded, project: SupabaseConfig.url) ==
        null) {
      await clear();
      return;
    }
    await _storage.write(key: _key, value: encoded);
    await _storage.delete(key: _legacyKey);
  }

  static Future<BackgroundCredential?> read() async =>
      BackgroundCredential.parse(
        await _storage.read(key: _key),
        project: SupabaseConfig.url,
      );
}

// Serialize foreground publication. Logout awaits deletion after any earlier
// publication, so an old callback cannot recreate the credential afterwards.
class BackgroundSessionPublisher {
  Future<void> _tail = Future.value();

  Future<void> update(Session? session) {
    final next = _tail
        .catchError((Object _) {})
        .then((_) => BackgroundSession.publish(session));
    _tail = next;
    return next;
  }
}
