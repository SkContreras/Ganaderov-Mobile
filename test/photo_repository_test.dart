import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/core/database/offline_store.dart';
import 'package:ganaderov/core/sync/universal_sync.dart';
import 'package:ganaderov/features/livestock/data/supabase_inventory_repository.dart';
import 'package:ganaderov/features/livestock/domain/animal_photos.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'photo_test_fixtures.dart';

Future<void> session(SupabaseClient client, [String user = photoUser]) async {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final jwt =
      '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': user, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 7200})}.fixture';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': jwt,
      'token_type': 'bearer',
      'expires_in': 7200,
      'refresh_token': 'fixture-refresh',
      'user': {
        'id': user,
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}

class NoDeliveryRepository extends SupabaseInventoryRepository {
  NoDeliveryRepository(super.client, {required super.store})
    : super(universalEnabled: true, project: photoProject);
  int deliveries = 0;
  @override
  Future<void> syncEvents({bool manual = false}) async {
    deliveries++;
  }
}

void main() {
  late OfflineStore db;
  late SupabaseClient client;
  late NoDeliveryRepository repository;
  late List<http.Request> network;
  late Future<http.Response> Function(http.Request) handle;
  setUp(() async {
    db = OfflineStore(NativeDatabase.memory());
    network = [];
    handle = (_) async =>
        throw http.ClientException('No network allowed during capture');
    client = SupabaseClient(
      photoProject,
      'sb_publishable_fixture',
      httpClient: MockClient((request) async {
        network.add(request);
        final response = await handle(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await session(client);
    repository = NoDeliveryRepository(client, store: db);
    await db.save(photoSnapshot(), project: photoProject);
    for (final id in [firstPhoto, secondPhoto]) {
      await db.savePhotoMetadata(
        photoUser,
        photoOwner,
        photoProject,
        id,
        photoEntity(id),
      );
    }
  });
  tearDown(() async {
    await client.dispose();
    await db.close();
  });

  for (final action in ['crop', 'primary', 'delete']) {
    test(
      '$action captures offline with zero HTTP and reconstructs its persistent preview',
      () async {
        final snapshot = photoSnapshot(offline: true);
        switch (action) {
          case 'crop':
            await repository.savePhotoCrop(
              snapshot,
              'a',
              firstPhoto,
              const PhotoCrop(x: 82, y: 24, zoom: 2.4),
            );
          case 'primary':
            await repository.primaryPhoto(snapshot, 'a', secondPhoto);
          case 'delete':
            await repository.removePhoto(snapshot, 'a', firstPhoto);
        }
        expect(network, isEmpty);
        expect(repository.deliveries, 0);
        final pending =
            (await db.universalPending(
                  photoUser,
                  photoOwner,
                )).single['operation']
                as Map;
        expect(pending['baseRevision'], 7);
        expect(pending['action'], 'photo.$action');
        final restarted = NoDeliveryRepository(client, store: db);
        final preview = await restarted.refreshPhotoChanges(snapshot);
        final photos = AnimalPhoto.fromSnapshot(preview, 'a');
        expect(preview.photoSyncStates['a'], 'pending');
        if (action == 'crop') expect(photos.first.crop.zoom, 2.4);
        if (action == 'primary')
          expect(photos.singleWhere((photo) => photo.primary).id, secondPhoto);
        if (action == 'delete') expect(photos.single.id, secondPhoto);
        await expectLater(
          repository.savePhotoCrop(
            preview,
            'a',
            secondPhoto,
            const PhotoCrop(x: 25),
          ),
          throwsStateError,
        );
        expect(network, isEmpty);
      },
    );
  }

  test(
    'known online revision also captures locally before background delivery',
    () async {
      await repository.savePhotoCrop(
        photoSnapshot(),
        'a',
        firstPhoto,
        const PhotoCrop(zoom: 2),
      );
      expect(network, isEmpty);
      expect(repository.deliveries, 1);
      expect(await db.universalPending(photoUser, photoOwner), hasLength(1));
    },
  );

  for (final refreshMetadata in [false, true]) {
    test(
      'photo changed while the crop editor was open rejects the initial snapshot (metadata refreshed: $refreshMetadata)',
      () async {
        final opened = photoSnapshot(offline: true);
        final refreshed = photoSnapshot();
        final photos =
            (refreshed.records.single['payload'] as Map)['photos'] as List;
        (photos.first as Map)['cropX'] = 90;
        await db.save(refreshed, project: photoProject);
        if (refreshMetadata) {
          final entity = photoEntity(firstPhoto, revision: 8);
          (entity['data'] as Map)['cropX'] = 90;
          await db.savePhotoMetadata(
            photoUser,
            photoOwner,
            photoProject,
            firstPhoto,
            entity,
          );
        }
        await expectLater(
          repository.savePhotoCrop(
            opened,
            'a',
            firstPhoto,
            const PhotoCrop(x: 32, y: 68, zoom: 1.6),
          ),
          throwsStateError,
        );
        expect(await db.universalPending(photoUser, photoOwner), isEmpty);
        expect(network, isEmpty);
      },
    );
  }

  test('missing revision, expired inventory, wrong project and worker cannot enqueue offline', () async {
    await db.customStatement('DELETE FROM photo_metadata');
    await expectLater(
      repository.primaryPhoto(photoSnapshot(offline: true), 'a', secondPhoto),
      throwsStateError,
    );
    await expectLater(
      repository.savePhotoCrop(
        photoSnapshot(
          offline: true,
          cachedAt: DateTime.now().subtract(const Duration(hours: 25)),
        ),
        'a',
        firstPhoto,
        const PhotoCrop(),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.removePhoto(
        photoSnapshot(offline: true, role: 'worker'),
        'a',
        firstPhoto,
      ),
      throwsStateError,
    );
    await db.savePhotoMetadata(
      photoUser,
      photoOwner,
      photoProject,
      firstPhoto,
      photoEntity(firstPhoto),
    );
    await db.save(photoSnapshot(), project: 'different-project');
    await expectLater(
      repository.removePhoto(photoSnapshot(offline: true), 'a', firstPhoto),
      throwsStateError,
    );
    expect(await db.universalPending(photoUser, photoOwner), isEmpty);
    expect(network, isEmpty);
  });

  test('cached original remains byte-identical offline and wrong user cannot read it', () async {
    final snapshot = photoSnapshot(offline: true);
    final photo = AnimalPhoto.fromSnapshot(snapshot, 'a').first;
    await db.savePhotoOriginal(
      photoUser,
      photoOwner,
      photoProject,
      photo.path,
      photoPng(),
    );
    expect(await repository.readPhoto(snapshot, 'a', photo), photoPng());
    await session(client, 'another-user');
    await expectLater(
      repository.readPhoto(snapshot, 'a', photo),
      throwsStateError,
    );
    expect(network, isEmpty);
  });

  test(
    'observed membership revocation blocks subsequent cached reads and writes',
    () async {
      final snapshot = photoSnapshot();
      final photo = AnimalPhoto.fromSnapshot(snapshot, 'a').first;
      await db.savePhotoOriginal(
        photoUser,
        photoOwner,
        photoProject,
        photo.path,
        photoPng(),
      );
      await db.customStatement('DELETE FROM photo_metadata');
      handle = (_) async => http.Response(
        jsonEncode({'status': 'pending'}),
        200,
        headers: {'content-type': 'application/json'},
      );
      await expectLater(
        repository.readPhoto(snapshot, 'a', photo),
        throwsStateError,
      );
      await db.savePhotoMetadata(
        photoUser,
        photoOwner,
        photoProject,
        firstPhoto,
        photoEntity(firstPhoto),
      );
      await expectLater(
        repository.removePhoto(snapshot, 'a', firstPhoto),
        throwsStateError,
      );
      await expectLater(
        repository.readPhoto(snapshot, 'a', photo),
        throwsStateError,
      );
      expect(network, hasLength(1));
      expect(await db.universalPending(photoUser, photoOwner), isEmpty);
    },
  );

  test('account change during download prevents returning or caching the old account bytes', () async {
    final download = Completer<http.Response>(), started = Completer<void>();
    handle = (request) async {
      if (request.url.path.endsWith('get_my_ranch_context'))
        return http.Response(
          jsonEncode({
            'status': 'active',
            'owner_id': photoOwner,
            'role': 'owner',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      started.complete();
      return download.future;
    };
    final snapshot = photoSnapshot(),
        photo = AnimalPhoto.fromSnapshot(photoSnapshot(), 'a').first;
    final result = repository.readPhoto(snapshot, 'a', photo);
    final assertion = expectLater(result, throwsStateError);
    await started.future;
    await session(client, 'another-user');
    download.complete(
      http.Response.bytes(
        photoPng(),
        200,
        headers: {'content-type': 'image/png'},
      ),
    );
    await assertion;
    expect(
      await db.readPhotoOriginal(
        photoUser,
        photoOwner,
        photoProject,
        photo.path,
      ),
      isNull,
    );
  });

  test('retry reuses the operation UUID; a different project and an unknown origin never send', () async {
    await repository.savePhotoCrop(
      photoSnapshot(offline: true),
      'a',
      firstPhoto,
      const PhotoCrop(x: 80),
    );
    final operation =
        (await db.universalPending(photoUser, photoOwner)).single['operation']
            as Map;
    final sync = UniversalSync(client, db, photoProject);
    await UniversalSync(
      client,
      db,
      'other-project',
    ).flush(photoUser, photoOwner, 'holder', manual: true);
    expect(network, isEmpty);
    final bodies = <Map>[];
    handle = (request) async {
      final op = (jsonDecode(request.body) as Map)['p_operation'] as Map;
      bodies.add(op);
      if (bodies.length == 1) throw http.ClientException('connection dropped');
      return http.Response(
        jsonEncode({
          'protocolVersion': 1,
          'operationId': op['operationId'],
          'status': 'applied',
          'revision': 8,
          'code': 'OK',
          'serverReceivedAt': DateTime.now().toUtc().toIso8601String(),
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    };
    await sync.flush(photoUser, photoOwner, 'holder', manual: true);
    await sync.flush(photoUser, photoOwner, 'holder', manual: true);
    expect(bodies, [operation, operation]);
    expect(await db.universalPending(photoUser, photoOwner), isEmpty);
    await db.enqueueUniversal(
      photoUser,
      photoOwner,
      photoOperation(id: 'unscoped-legacy'),
    );
    await sync.flush(photoUser, photoOwner, 'holder', manual: true);
    expect(bodies, hasLength(2));
    expect(
      (await db.reviewUniversal(photoUser, photoOwner)).single['state'],
      'rejected',
    );
  });
}
