import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/features/livestock/domain/animal_photos.dart';
void main(){
 test('legacy photos default to centered original',(){final c=PhotoCrop.fromJson({});expect(c.x,50);expect(c.y,50);expect(c.zoom,1);expect(c.valid,isTrue);});
 test('crop range and serialization',(){const c=PhotoCrop(x:93,y:51,zoom:2);expect(c.valid,isTrue);expect(c.changes('a'),{'animalId':'a','cropX':93.0,'cropY':51.0,'cropZoom':2.0});expect(const PhotoCrop(zoom:4).valid,isFalse);});
 test('invalid legacy values normalized',(){final c=PhotoCrop.fromJson({'cropX':-5,'cropY':200,'cropZoom':'NaN'});expect(c.valid,isTrue);expect(c.x,0);expect(c.y,100);expect(c.zoom,1);});
}
