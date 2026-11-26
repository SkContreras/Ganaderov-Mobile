import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../features/livestock/domain/event_draft.dart';
import '../../features/livestock/domain/inventory.dart';

class PendingEvent {
  const PendingEvent({required this.userId,required this.ownerId,required this.animalId,required this.draft,this.attempts=0,this.error='',this.nextAt=0,this.operation,this.state='pending'});
  final String userId,ownerId,animalId,error;
  final EventDraft draft;
  final int attempts,nextAt;
  final Map<String,dynamic>? operation;
  final String state;
}
abstract interface class OutboxAccess {
  Future<List<PendingEvent>> pendingEvents();
  Future<void> syncEvents({bool manual=false});
  Future<void> discardPending(PendingEvent event);
}
abstract class EventOutbox extends ChangeNotifier implements OutboxAccess {}
class ForegroundSync with WidgetsBindingObserver {
  ForegroundSync(this.run);
  final Future<void> Function() run;
  Timer? _timer;
  bool _running=false;
  void start(){
    WidgetsBinding.instance.addObserver(this);
    _resume();
  }
  void _resume(){
    _timer?.cancel();
    _timer=Timer.periodic(const Duration(seconds:30),(_)=>_tick());
    _tick();
  }
  Future<void> _tick()async{
    if(_running)return;
    _running=true;
    try{await run();}catch(_){/* Queue remains durable. */}finally{_running=false;}
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed){_resume();}else{_timer?.cancel();}
  }
  void dispose(){_timer?.cancel();WidgetsBinding.instance.removeObserver(this);}
}
InventorySnapshot outboxScope(PendingEvent p)=>InventorySnapshot(status:'active',role:'worker',ownerId:p.ownerId,userId:p.userId);
