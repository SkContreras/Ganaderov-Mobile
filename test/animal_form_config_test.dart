import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/features/livestock/domain/animal_form_config.dart';
void main(){
  test('field settings, labels and custom inactive status',(){
    const c=AnimalFormConfig({'configVersion':4,'modules':{'dates':false},'fields':{'name':{'enabled':false},'tag':{'required':true,'label':'Arete oficial'}},'lists':{'status':[{'value':'Retirado','label':'Retirado','enabled':true,'active':false}]}});
    expect(c.visible(animalFields.firstWhere((f)=>f.id=='name')),isFalse);
    expect(c.visible(animalFields.firstWhere((f)=>f.id=='birthDate')),isFalse);
    expect(c.label(animalFields.first),'Arete oficial');
    expect(c.requiredField(animalFields.first),isTrue);
    expect(c.active('Retirado'),isFalse);
  });
}
