import 'dart:convert';
import 'dart:typed_data';

import 'package:ganaderov/features/livestock/domain/inventory.dart';

const photoUser = '10000000-0000-4000-8000-000000000001';
const photoOwner = '20000000-0000-4000-8000-000000000001';
const photoProject = 'https://photo-test.supabase.co';
const firstPhoto = '30000000-0000-4000-8000-000000000001';
const secondPhoto = '30000000-0000-4000-8000-000000000002';

Map<String, dynamic> photoData(String id, {bool primary = false}) => {
  'id': id,
  'animalId': 'a',
  'storagePath': '$photoOwner/a/$id',
  'name': id == firstPhoto ? 'Original uno' : 'Original dos',
  'mime': 'image/png',
  'primary': primary,
  'cropX': 50.0,
  'cropY': 50.0,
  'cropZoom': 1.0,
};

InventorySnapshot photoSnapshot({
  bool offline = false,
  String user = photoUser,
  String role = 'owner',
  DateTime? cachedAt,
}) => InventorySnapshot(
  status: 'active',
  userId: user,
  ownerId: photoOwner,
  role: role,
  offline: offline,
  cachedAt: cachedAt ?? DateTime.now(),
  records: [
    {
      'animal_id': 'a',
      'modified_at': '2026-11-01T10:00:00Z',
      'payload': {
        'animal': {'id': 'a', 'name': 'Luna', 'status': 'Activo'},
        'events': [],
        'photos': [
          photoData(firstPhoto, primary: true),
          photoData(secondPhoto),
        ],
      },
    },
  ],
);

Map<String, dynamic> photoEntity(String id, {int revision = 7}) => {
  'revision': revision,
  'parentId': 'a',
  'data': photoData(id, primary: id == firstPhoto),
};

Map<String, dynamic> photoOperation({
  String id = '40000000-0000-4000-8000-000000000001',
  String action = 'photo.crop',
  String photoId = firstPhoto,
}) => {
  'protocolVersion': 1,
  'operationId': id,
  'ownerId': photoOwner,
  'deviceId': '50000000-0000-4000-8000-000000000001',
  'action': action,
  'entityId': photoId,
  'baseRevision': 7,
  'capturedAt': DateTime.now().toUtc().toIso8601String(),
  'changes': {
    'animalId': 'a',
    if (action == 'photo.crop') ...{
      'cropX': 82.0,
      'cropY': 24.0,
      'cropZoom': 2.4,
    },
    if (action == 'photo.primary') 'previousPrimaryId': firstPhoto,
  },
};

// Valid one-pixel PNG. These are the original bytes, never a cropped derivative.
Uint8List photoPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aH1cAAAAASUVORK5CYII=',
);
