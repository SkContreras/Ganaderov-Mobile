import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/features/livestock/domain/animal_photos.dart';
import 'package:ganaderov/features/livestock/domain/inventory.dart';
void main(){
  test('only photos matching ranch and animal path are accepted',(){
    const s=InventorySnapshot(status:'active',ownerId:'ranch',records:[{'animal_id':'a','payload':{'photos':[{'id':'p','animalId':'a','storagePath':'ranch/a/p','primary':true},{'id':'q','animalId':'a','storagePath':'other/a/q'}]}}]);
    expect(AnimalPhoto.fromSnapshot(s,'a').single.id,'p');
  });
  test('reject unsupported file signatures',(){
    expect(imageMime(Uint8List.fromList([255,216,255])),'image/jpeg');
    expect(imageMime(Uint8List.fromList([1,2,3])),isNull);
  });
}
