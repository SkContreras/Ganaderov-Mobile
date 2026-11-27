import 'dart:typed_data';
import 'inventory.dart';

class AnimalPhoto {
  const AnimalPhoto({required this.id, required this.path, required this.name, required this.primary,this.crop=const PhotoCrop()});
  final PhotoCrop crop;
  final String id, path, name;
  final bool primary;
  static List<AnimalPhoto> fromSnapshot(InventorySnapshot snapshot,String animalId) {
    final row=snapshot.records.where((r)=>r['animal_id']==animalId).firstOrNull;
    final payload=row?['payload'];
    final photos=payload is Map ? payload['photos'] : null;
    if(photos is! List) return [];
    return [
      for(final p in photos.whereType<Map>())
        if(p['id'] is String && (p['animalId']==null||p['animalId']==animalId) && p['storagePath']=='${snapshot.ownerId}/$animalId/${p['id']}')
          AnimalPhoto(id:p['id'] as String,path:p['storagePath'] as String,name:p['name']?.toString()??'Fotografía',primary:p['primary']==true,crop:PhotoCrop.fromJson(p)),
    ];
  }
}
String? imageMime(Uint8List bytes) {
  if(bytes.length>=3 && bytes[0]==255 && bytes[1]==216 && bytes[2]==255) return 'image/jpeg';
  if(bytes.length>=8 && bytes[0]==137 && bytes[1]==80 && bytes[2]==78 && bytes[3]==71 && bytes[4]==13 && bytes[5]==10 && bytes[6]==26 && bytes[7]==10) return 'image/png';
  if(bytes.length>=12 && String.fromCharCodes(bytes.sublist(0,4))=='RIFF' && String.fromCharCodes(bytes.sublist(8,12))=='WEBP') return 'image/webp';
  return null;
}
abstract interface class AnimalPhotoRemoval {
  Future<void> removePhoto(InventorySnapshot snapshot,String animalId,String photoId);
}
abstract interface class AnimalPhotos {
  Future<Uint8List> readPhoto(InventorySnapshot snapshot,String animalId,AnimalPhoto photo);
  Future<void> addPhoto(InventorySnapshot snapshot,String animalId,Uint8List bytes,String name);
  Future<void> primaryPhoto(InventorySnapshot snapshot,String animalId,String photoId);
}

class PhotoCrop {
 const PhotoCrop({this.x=50,this.y=50,this.zoom=1});
 final double x,y,zoom;
 bool get valid=>x.isFinite&&y.isFinite&&zoom.isFinite&&x>=0&&x<=100&&y>=0&&y<=100&&zoom>=1&&zoom<=3;
 factory PhotoCrop.fromJson(Map p){
   double read(Object? v,double fallback,double min,double max){final n=double.tryParse(v?.toString()??'');return n!=null&&n.isFinite?n.clamp(min,max).toDouble():fallback;}
   return PhotoCrop(x:read(p['cropX'],50,0,100),y:read(p['cropY'],50,0,100),zoom:read(p['cropZoom'],1,1,3));
 }
 Map<String,dynamic> changes(String animalId)=>{'animalId':animalId,'cropX':x,'cropY':y,'cropZoom':zoom};
}
abstract interface class AnimalPhotoFraming{
 Future<void> savePhotoCrop(InventorySnapshot snapshot,String animalId,String photoId,PhotoCrop crop);
}

abstract interface class OfflineAnimalPhotos {
  bool get supportsOfflinePhotoChanges;
  Future<InventorySnapshot> refreshPhotoChanges(InventorySnapshot snapshot);
}

/// Replays durable metadata changes for display without modifying the confirmed
/// snapshot. Calling it repeatedly is safe, including after process restart.
InventorySnapshot projectPhotoChanges(
  InventorySnapshot snapshot,
  List<Map<String, dynamic>> changes,
) {
  final records = snapshot.records.map((row) => Map<String, dynamic>.from(row)).toList();
  final states = <String, String>{};
  for (final entry in changes) {
    final operation = entry['operation'];
    if (operation is! Map || operation['ownerId'] != snapshot.ownerId) continue;
    final update = operation['changes'];
    if (update is! Map || update['animalId'] is! String) continue;
    final animalId = update['animalId'] as String;
    final state = entry['state'] as String;
    if (!['pending', 'confirmed', 'conflict', 'rejected'].contains(state)) continue;
    if(states[animalId]!='conflict'&&states[animalId]!='rejected')states[animalId] = state;
    if (state != 'pending' && state != 'confirmed') continue;
    final row = records.where((row) => row['animal_id'] == animalId && row['deleted_at'] == null).firstOrNull;
    if (row == null || row['payload'] is! Map) continue;
    final payload = Map<String, dynamic>.from(row['payload'] as Map);
    final original = payload['photos'];
    if (original is! List) continue;
    final photos = original.whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList();
    final photoId = operation['entityId'];
    final selected = photos.where((p) => p['id'] == photoId && (p['animalId'] == null || p['animalId'] == animalId) && p['storagePath'] == '${snapshot.ownerId}/$animalId/$photoId').firstOrNull;
    switch (operation['action']) {
      case 'photo.create':
        if (selected == null) {
          if (update['primary'] == true) {
            for (final photo in photos) { photo['primary'] = false; }
          }
          photos.add({
            'id': photoId, 'animalId': animalId,
            'storagePath': '${snapshot.ownerId}/$animalId/$photoId',
            'name': update['name'], 'mime': update['mime'],
            'primary': update['primary'] == true,
            'createdAt': operation['capturedAt'],
            'cropX': 50.0, 'cropY': 50.0, 'cropZoom': 1.0,
          });
        }
      case 'photo.crop':
        if (selected != null) {
          for (final field in ['cropX', 'cropY', 'cropZoom']) { selected[field] = update[field]; }
        }
      case 'photo.primary':
        if (selected != null) {
          for (final photo in photos) { photo['primary'] = photo['id'] == photoId; }
        }
      case 'photo.delete':
        photos.removeWhere((photo) => photo['id'] == photoId);
        if (photos.isNotEmpty && !photos.any((p) => p['primary'] == true)) {
          photos.first['primary'] = true;
        }
    }
    payload['photos'] = photos;
    row['payload'] = payload;
  }
  return InventorySnapshot(
    status: snapshot.status, ranchName: snapshot.ranchName, role: snapshot.role,
    records: records, statusOptions: snapshot.statusOptions, statusLabels: snapshot.statusLabels,
    config: snapshot.config, ownerId: snapshot.ownerId, userId: snapshot.userId,
    configRevision: snapshot.configRevision, offline: snapshot.offline,
    cachedAt: snapshot.cachedAt, photoSyncStates: states,
    operationStates:snapshot.operationStates,offlineWritesEnabled:snapshot.offlineWritesEnabled,
  );
}
