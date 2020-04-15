import "dart:ffi";
import "dart:io";
import 'dart:isolate';
import "dart:async";
import "entity.dart";
import 'objectbox.g.dart';

import "package:test/test.dart";
import "package:ffi/ffi.dart" show allocate, free;

import 'test_env.dart';

final env = TestEnv("isolates");
final store = env.store;
final box = env.box;

put(List<TestEntity> list) {
  print("""put ${list}""");
  box.putMany(list);
}

callbackDart(Pointer<Void> user_data) {
  final ptr = Pointer<Int64>.fromAddress(user_data.address);
  var integer = ptr.value;
  integer++;
  ptr.value = integer;

  print("""callback: adress: ${user_data.address}, value: ${ptr.value}""");
}

main() async {

  final even = List<int>.generate(4, (i) { 2 * i + 2; }).map((i) =>
      TestEntity(id: i, tInt: i)).toList();

  final uneven = List<int>.generate(4, (i) { 2 * i + 1; }).map((i) =>
      TestEntity(id: i, tInt: i)).toList();

  final receivePort = ReceivePort();

  final isoEven =   await Isolate.spawn(put, even, paused: true, onExit: receivePort.sendPort, debugName: "even");
  final isoUneven = await Isolate.spawn(put, uneven, paused: true, onExit: receivePort.sendPort, debugName: "uneven");

  // initialize observer on the main isolate
  final ptr = allocate<Int64>();
  ptr.value = 0;

  final testEntityId = getObjectBoxModel().model.findEntityByName("TestEntity").id.id;
  final callbackPtr = Pointer.fromFunction<obx_observer_single_type_t<Void>>(callbackDart);
  final singleTypeObserver = bindings.obx_observe_single_type(store.ptr, testEntityId, callbackPtr, Pointer.fromAddress(ptr.address));

  isoEven.resume(isoEven.pauseCapability);
  isoUneven.resume(isoUneven.pauseCapability);

  var counter = 0;

  await for (var msg in receivePort) {

    counter++;

    print ("""receivePort counter: ${counter + ptr.value}""");

    if ((counter + ptr.value) > 3) {
      free(ptr);
      bindings.obx_observer_close(singleTypeObserver);

      env.close();
      receivePort.close();
      exit(0);
    }
  }

}

