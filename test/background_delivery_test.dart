import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ganaderov/core/database/local_cipher.dart';
import 'package:ganaderov/core/database/offline_store.dart';
import 'package:ganaderov/core/sync/background_session.dart';
import 'package:ganaderov/core/sync/background_sync.dart';

import 'photo_test_fixtures.dart';

String tokenFor(String user, int expiry, {String role = 'authenticated'}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': user, 'role': role, 'exp': expiry})}.synthetic-signature';
}

BackgroundCredential credential(
  DateTime now, {
  String project = photoProject,
  String generation = 'one',
}) {
  final expiry = now.millisecondsSinceEpoch ~/ 1000 + 3600;
  return BackgroundCredential(
    userId: photoUser,
    accessToken: tokenFor(photoUser, expiry),
    expiresAt: expiry,
    url: project,
    generation: generation,
  );
}

Map<String, dynamic> animalOperation(
  String id, {
  String action = 'animal.create',
  int? revision,
  String animal = 'a',
}) => {
  'protocolVersion': 1,
  'operationId': id,
  'ownerId': photoOwner,
  'deviceId': '50000000-0000-4000-8000-000000000001',
  'action': action,
  'entityId': animal,
  'baseRevision': revision,
  'capturedAt': DateTime.now().toUtc().toIso8601String(),
  'changes': {
    'fields': {'name': 'Offline animal'},
  },
};

http.Response jsonResponse(Object? value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
Map<String, dynamic> membership({
  String status = 'active',
  String role = 'owner',
}) => {'status': status, 'owner_id': photoOwner, 'role': role};
Map<String, dynamic> receipt(
  Map operation, {
  int revision = 1,
  String status = 'applied',
}) => {
  'protocolVersion': 1,
  'operationId': operation['operationId'],
  'status': status,
  'revision': revision,
  'code': 'OK',
  'serverReceivedAt': DateTime.now().toUtc().toIso8601String(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'credential rejects expiry, a different project, user and privileged role',
    () {
      final now = DateTime.now(), good = credential(DateTime.now());
      final body = good.toJson();
      expect(
        BackgroundCredential.parse(
          jsonEncode(body),
          project: photoProject,
          now: now,
        ),
        isNotNull,
      );
      final variants = <Map<String, dynamic>>[
        {...body, 'userId': 'another-user'},
        {...body, 'url': 'https://other.supabase.co'},
        {...body, 'generation': ''},
        {...body, 'schemaVersion': 1},
        {...body, 'expiresAt': now.millisecondsSinceEpoch ~/ 1000 + 59},
        {...body, 'expiresAt': good.expiresAt + 1},
        {
          ...body,
          'accessToken': tokenFor(
            photoUser,
            good.expiresAt,
            role: 'service_role',
          ),
        },
        {...body, 'accessToken': 'not-a-jwt'},
      ];
      for (final value in variants) {
        expect(
          BackgroundCredential.parse(
            jsonEncode(value),
            project: photoProject,
            now: now,
          ),
          isNull,
        );
      }
      expect(good.sameGrant(credential(now, generation: 'rotated')), isFalse);
    },
  );

  group('headless universal delivery with real encrypted SQLite', () {
    late OfflineStore db;
    late DateTime now;
    BackgroundCredential? grant;
    late List<http.Request> requests;
    late Future<http.Response> Function(http.Request) handler;

    setUp(() {
      db = OfflineStore(NativeDatabase.memory(), LocalCipher(Uint8List(32)));
      now = DateTime.now();
      grant = credential(now);
      requests = [];
      handler = (request) async {
        if (request.url.path.endsWith('/get_my_ranch_context')) {
          return jsonResponse(membership());
        }
        final operation =
            (jsonDecode(request.body) as Map)['p_operation'] as Map;
        return jsonResponse(receipt(operation));
      };
    });
    tearDown(() async {
      await db.close();
    });

    Future<bool> deliver({int limit = 8}) => deliverBackgroundQueues(
      store: db,
      project: photoProject,
      publishableKey: 'sb_publishable_test',
      readCredential: () async => grant,
      universalEnabled: true,
      eventRpcEnabled: false,
      clock: () => now,
      maxOperations: limit,
      httpClient: MockClient((request) async {
        requests.add(request);
        final result = await handler(request);
        return http.Response.bytes(result.bodyBytes, result.statusCode,
          headers: result.headers, request: request);
      }),
    );
    Future<void> capture(
      Map<String, dynamic> op, {
      List<String> dependencies = const [],
      String? revisionFrom,
      String project = photoProject,
    }) => db.captureUniversalDraft(
      photoUser,
      photoOwner,
      project,
      op,
      dependencies: dependencies,
      revisionFrom: revisionFrom,
    );
    List<Map> sent() => requests
        .where((r) => r.url.path.endsWith('/sync_apply_operation'))
        .map((r) => (jsonDecode(r.body) as Map)['p_operation'] as Map)
        .toList();

    test('delivers create and dependent edit with the first server receipt revision', () async {
      final create = animalOperation('60000000-0000-4000-8000-000000000001');
      final edit = animalOperation(
        '60000000-0000-4000-8000-000000000002',
        action: 'animal.update',
      );
      await capture(create);
      await capture(
        edit,
        dependencies: [create['operationId'] as String],
        revisionFrom: create['operationId'] as String,
      );
      handler = (request) async {
        if (request.url.path.endsWith('/get_my_ranch_context')) {
          return jsonResponse(membership());
        }
        final op = (jsonDecode(request.body) as Map)['p_operation'] as Map;
        return jsonResponse(
          receipt(op, revision: op['action'] == 'animal.create' ? 7 : 8),
        );
      };
      expect(await deliver(), isTrue);
      expect(sent().map((op) => op['operationId']), [
        create['operationId'],
        edit['operationId'],
      ]);
      expect(sent().last['baseRevision'], 7);
      expect(await db.universalPending(photoUser, photoOwner), isEmpty);
      expect(
        requests.every(
          (r) => r.headers['authorization'] == 'Bearer ${grant!.accessToken}',
        ),
        isTrue,
      );
      expect(requests.any((r) => r.url.path.startsWith('/auth/')), isFalse);
      final stored = await db
          .customSelect('SELECT payload FROM universal_outbox')
          .get();
      expect(
        stored.every(
          (r) => !r.read<String>('payload').contains('Offline animal'),
        ),
        isTrue,
      );
    });

    test(
      'uploads the original before photo.create using the same queue',
      () async {
        await db.save(photoSnapshot(), project: photoProject);
        final op = {
          ...photoOperation(action: 'photo.create'),
          'baseRevision': null,
          'entityId': '30000000-0000-4000-8000-000000000003',
          'changes': {
            'animalId': 'a',
            'mime': 'image/png',
            'name': 'original.png',
            'primary': false,
          },
        };
        final original = photoPng();
        await db.enqueuePhotoOperation(
          photoUser,
          photoOwner,
          photoProject,
          op,
          attachment: base64Encode(original),
          verify: () {},
        );
        handler = (request) async {
          if (request.url.path.endsWith('/get_my_ranch_context')) {
            return jsonResponse(membership());
          }
          if (request.url.path.startsWith('/storage/')) {
            expect(request.headers['x-upsert'], 'false');
            expect(request.bodyBytes, containsAllInOrder(original));
            return jsonResponse({
              'Key': 'animal-photos/$photoOwner/a/${op['entityId']}',
            });
          }
          return jsonResponse(
            receipt((jsonDecode(request.body) as Map)['p_operation'] as Map),
          );
        };
        expect(await deliver(), isTrue);
        expect(
          requests.where((r) => r.url.path.startsWith('/storage/')).length,
          1,
        );
        expect(sent().single, op);
        expect(await db.universalPending(photoUser, photoOwner), isEmpty);
      },
    );

    test(
      'logout during a response retains the UUID, body and pending state',
      () async {
        final op = animalOperation('60000000-0000-4000-8000-000000000003');
        await capture(op);
        handler = (request) async {
          if (request.url.path.endsWith('/get_my_ranch_context')) {
            return jsonResponse(membership());
          }
          grant = null;
          return jsonResponse(
            receipt((jsonDecode(request.body) as Map)['p_operation'] as Map),
          );
        };
        expect(await deliver(), isTrue);
        final pending = await db.universalPending(photoUser, photoOwner);
        expect(pending.single['operation'], op);
        expect(pending.single['attempts'], 0);
      },
    );

    test(
      'membership revocation before sending pauses without a false rejection',
      () async {
        await capture(animalOperation('60000000-0000-4000-8000-000000000004'));
        var membershipReads = 0;
        handler = (request) async => jsonResponse(
          membership(status: ++membershipReads == 1 ? 'active' : 'unassigned'),
        );
        expect(await deliver(), isTrue);
        expect(sent(), isEmpty);
        expect(
          (await db.universalPending(photoUser, photoOwner)).single['attempts'],
          0,
        );
      },
    );

    test(
      'HTTP 401 pauses the queue without fabricating a terminal receipt',
      () async {
        await capture(animalOperation('60000000-0000-4000-8000-000000000005'));
        handler = (request) async =>
            request.url.path.endsWith('/get_my_ranch_context')
            ? jsonResponse(membership())
            : jsonResponse({'message': 'expired'}, status: 401);
        expect(await deliver(), isTrue);
        expect(
          (await db.universalPending(photoUser, photoOwner)).single['attempts'],
          0,
        );
      },
    );

    test(
      'expired credentials and different projects never make an HTTP request',
      () async {
        await capture(animalOperation('60000000-0000-4000-8000-000000000006'));
        grant = credential(now, project: 'https://other.supabase.co');
        expect(await deliver(), isTrue);
        expect(requests, isEmpty);
        grant = credential(now.subtract(const Duration(hours: 2)));
        expect(await deliver(), isTrue);
        expect(requests, isEmpty);
        expect(
          (await db.universalPending(photoUser, photoOwner)).single['attempts'],
          0,
        );
      },
    );

    test('a queue from another project stays pending', () async {
      await capture(
        animalOperation('60000000-0000-4000-8000-000000000007'),
        project: 'https://other.supabase.co',
      );
      expect(await deliver(), isTrue);
      expect(sent(), isEmpty);
      expect(
        (await db.universalPending(photoUser, photoOwner)).single['attempts'],
        0,
      );
    });

    test('an existing foreground lease prevents a competing sender', () async {
      await capture(animalOperation('60000000-0000-4000-8000-000000000008'));
      expect(
        await db.acquireDeliveryLease('foreground', now.millisecondsSinceEpoch),
        isTrue,
      );
      expect(await deliver(), isTrue);
      expect(requests, isEmpty);
      expect((await db.universalPending(photoUser, photoOwner)).length, 1);
    });

    test('each wake is bounded and keeps the remainder durable', () async {
      for (var n = 10; n < 13; n++) {
        await capture(
          animalOperation(
            '60000000-0000-4000-8000-0000000000$n',
            animal: 'a$n',
          ),
        );
      }
      expect(await deliver(limit: 2), isTrue);
      expect(sent().length, 2);
      expect((await db.universalPending(photoUser, photoOwner)).length, 1);
    });
  });
}
