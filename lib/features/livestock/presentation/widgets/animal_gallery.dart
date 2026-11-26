import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import '../../domain/inventory.dart';
import '../../domain/animal_photos.dart';

class AnimalGallery extends StatefulWidget {
  const AnimalGallery({super.key,required this.snapshot,required this.animal,required this.repository,required this.onChanged});
  final InventorySnapshot snapshot;
  final InventoryAnimal animal;
  final AnimalPhotos repository;
  final Future<void> Function() onChanged;
  @override State<AnimalGallery> createState()=>_AnimalGalleryState();
}
class _AnimalGalleryState extends State<AnimalGallery>{
  bool _busy=false;
  String? _error;
  final _picker=ImagePicker();
  Future<void> _run(Future<void> Function() action) async {
    if(_busy)return;
    setState((){_busy=true;_error=null;});
    try{await action();}
    on StateError catch(e){if(mounted)setState(()=>_error=e.message.toString());}
    catch(_){if(mounted)setState(()=>_error='No se pudo confirmar la operación. Actualiza la ficha antes de repetirla.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _pick(ImageSource source)=>_run(() async{
    final file=await _picker.pickImage(source:source,maxWidth:1600,maxHeight:1600,imageQuality:85);
    if(file==null||!mounted)return;
    if(await file.length()>10*1024*1024)throw StateError('La imagen supera 10 MB.');
    final bytes=await file.readAsBytes();
    if(!mounted)return;
    await widget.repository.addPhoto(widget.snapshot,widget.animal.id,bytes,file.name);
    if(mounted)await widget.onChanged();
  });
  @override Widget build(BuildContext context){
    final photos=AnimalPhoto.fromSnapshot(widget.snapshot,widget.animal.id);
    final ordered=[...photos.where((p)=>p.primary),...photos.where((p)=>!p.primary)];
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('Fotografías (${photos.length})',style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:8),
      if(ordered.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(24),child:Column(children:[Icon(Icons.photo_outlined,size:42),Text('Sin fotografías')]))),
      if(ordered.isNotEmpty) _PrivatePhoto(key:ValueKey('hero-${ordered.first.id}'),snapshot:widget.snapshot,animalId:widget.animal.id,photo:ordered.first,repository:widget.repository,height:190),
      if(ordered.isNotEmpty) const SizedBox(height:8),
      if(ordered.isNotEmpty) SizedBox(height:120,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:ordered.length,separatorBuilder:(_,_)=>const SizedBox(width:8),itemBuilder:(context,i){
        final photo=ordered[i];
        return SizedBox(width:100,child:Column(children:[
          Expanded(child:_PrivatePhoto(key:ValueKey(photo.id),snapshot:widget.snapshot,animalId:widget.animal.id,photo:photo,repository:widget.repository,height:78)),
          if(widget.snapshot.canManage)IconButton(tooltip:photo.primary?'Foto principal':'Elegir como principal',onPressed:_busy||photo.primary?null:()=>_run(()async{await widget.repository.primaryPhoto(widget.snapshot,widget.animal.id,photo.id);if(mounted)await widget.onChanged();}),icon:Icon(photo.primary?Icons.star:Icons.star_border)),
        ]));
      })),
      if(widget.snapshot.canManage)Wrap(spacing:8,children:[
        OutlinedButton.icon(onPressed:_busy?null:()=>_pick(ImageSource.camera),icon:const Icon(Icons.camera_alt_outlined),label:const Text('Cámara')),
        OutlinedButton.icon(onPressed:_busy?null:()=>_pick(ImageSource.gallery),icon:const Icon(Icons.photo_library_outlined),label:const Text('Galería')),
      ]),
      if(_busy)const LinearProgressIndicator(),
      if(_error!=null)Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    ]);
  }
}
class _PrivatePhoto extends StatefulWidget{
  const _PrivatePhoto({super.key,required this.snapshot,required this.animalId,required this.photo,required this.repository,required this.height});
  final InventorySnapshot snapshot;
  final String animalId;
  final AnimalPhoto photo;
  final AnimalPhotos repository;
  final double height;
  @override State<_PrivatePhoto> createState()=>_PrivatePhotoState();
}
class _PrivatePhotoState extends State<_PrivatePhoto>{
  late Future<Uint8List> _bytes;
  @override void initState(){super.initState();_load();}
  void _load(){_bytes=widget.repository.readPhoto(widget.snapshot,widget.animalId,widget.photo);}
  @override Widget build(BuildContext context)=>SizedBox(height:widget.height,width:double.infinity,child:ClipRRect(borderRadius:BorderRadius.circular(12),child:FutureBuilder<Uint8List>(future:_bytes,builder:(context,s){
    if(s.hasError)return Center(child:IconButton(tooltip:'Reintentar fotografía',onPressed:()=>setState(_load),icon:const Icon(Icons.broken_image_outlined)));
    if(!s.hasData)return const Center(child:CircularProgressIndicator());
    return InkWell(onTap:()=>showDialog<void>(context:context,builder:(context)=>Dialog(child:InteractiveViewer(child:Image.memory(s.data!,fit:BoxFit.contain)))),child:Image.memory(s.data!,fit:BoxFit.cover,cacheWidth:1200,errorBuilder:(_,_,_)=>const Center(child:Icon(Icons.broken_image_outlined))));
  })));
}
