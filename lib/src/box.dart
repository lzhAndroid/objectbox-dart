import "dart:ffi";

import "package:ffi/ffi.dart" show allocate, free;

import 'common.dart';
import "store.dart";
import "bindings/bindings.dart";
import "bindings/constants.dart";
import "bindings/flatbuffers.dart";
import "bindings/helpers.dart";
import "bindings/structs.dart";
import "modelinfo/index.dart";
import "query/index.dart";

enum _PutMode {
  Put,
  Insert,
  Update,
}

class Box<T> {
  Store _store;
  Pointer<Void> _cBox;
  ModelEntity _modelEntity;
  ObjectReader<T> _entityReader;
  OBXFlatbuffersManager _fbManager;

  Box(this._store) {
    EntityDefinition<T> entityDefs = _store.entityDef<T>();
    _modelEntity = entityDefs.getModel();
    _entityReader = entityDefs.reader;
    _fbManager = OBXFlatbuffersManager<T>(_modelEntity, entityDefs.writer);

    _cBox = bindings.obx_box(_store.ptr, _modelEntity.id.id);
    checkObxPtr(_cBox, "failed to create box");
  }

  _getOBXPutMode(_PutMode mode) {
    switch (mode) {
      case _PutMode.Put:
        return OBXPutMode.PUT;
      case _PutMode.Insert:
        return OBXPutMode.INSERT;
      case _PutMode.Update:
        return OBXPutMode.UPDATE;
    }
  }

  // if the respective ID property is given as null or 0, a newly assigned ID is returned, otherwise the existing ID is returned
  int put(T object, {_PutMode mode = _PutMode.Put}) {
    var propVals = _entityReader(object);
    if (propVals[_modelEntity.idPropName] == null || propVals[_modelEntity.idPropName] == 0) {
      final id = bindings.obx_box_id_for_put(_cBox, 0); // TODO check error if 0 was returned instead of an ID
      propVals[_modelEntity.idPropName] = id;
    }

    // put object into box and free the buffer
    ByteBuffer buffer = _fbManager.marshal(propVals);
    try {
      checkObx(bindings.obx_box_put(
          _cBox, propVals[_modelEntity.idPropName], buffer.voidPtr, buffer.size, _getOBXPutMode(mode)));
    } finally {
      buffer.free(); // TODO change ByteBuffer to a struct
    }
    return propVals[_modelEntity.idPropName];
  }

  // only instances whose ID property ot null or 0 will be given a new, valid number for that. A list of the final IDs is returned
  List<int> putMany(List<T> objects, {_PutMode mode = _PutMode.Put}) {
    if (objects.isEmpty) return [];

    // read all property values and find number of instances where ID is missing
    var allPropVals = objects.map(_entityReader).toList();
    int missingIdsCount = 0;
    for (var instPropVals in allPropVals) {
      if (instPropVals[_modelEntity.idPropName] == null || instPropVals[_modelEntity.idPropName] == 0) {
        ++missingIdsCount;
      }
    }

    // generate new IDs for these instances and set them
    if (missingIdsCount != 0) {
      int nextId = 0;
      Pointer<Uint64> nextIdPtr = allocate<Uint64>(count: 1);
      try {
        checkObx(bindings.obx_box_ids_for_put(_cBox, missingIdsCount, nextIdPtr));
        nextId = nextIdPtr.value;
      } finally {
        free(nextIdPtr);
      }
      for (var instPropVals in allPropVals) {
        if (instPropVals[_modelEntity.idPropName] == null || instPropVals[_modelEntity.idPropName] == 0) {
          instPropVals[_modelEntity.idPropName] = nextId++;
        }
      }
    }

    // because obx_box_put_many also needs a list of all IDs of the elements to be put into the box,
    // generate this list now (only needed if not all IDs have been generated)
    Pointer<Uint64> allIdsMemory = allocate<Uint64>(count: objects.length);
    try {
      for (int i = 0; i < allPropVals.length; ++i) {
        allIdsMemory.elementAt(i).value = (allPropVals[i][_modelEntity.idPropName] as int);
      }

      // marshal all objects to be put into the box
      var putObjects = ByteBufferArray(allPropVals.map<ByteBuffer>(_fbManager.marshal).toList()).toOBXBytesArray();
      try {
        checkObx(bindings.obx_box_put_many(_cBox, putObjects.ptr, allIdsMemory, _getOBXPutMode(mode)));
      } finally {
        putObjects.free();
      }
    } finally {
      free(allIdsMemory);
    }
    return allPropVals.map((p) => p[_modelEntity.idPropName] as int).toList();
  }

  get(int id) {
    Pointer<Pointer<Void>> dataPtr = allocate<Pointer<Void>>();
    Pointer<Int32> sizePtr = allocate<Int32>();

    // get element with specified id from database
    return _store.runInTransaction(TxMode.Read, () {
      ByteBuffer buffer;
      try {
        checkObx(bindings.obx_box_get(_cBox, id, dataPtr, sizePtr));

        Pointer<Uint8> data = Pointer<Uint8>.fromAddress(dataPtr.value.address);
        var size = sizePtr.value;

        // transform bytes from memory to Dart byte list
        buffer = ByteBuffer(data, size);
      } finally {
        free(dataPtr);
        free(sizePtr);
      }

      return _fbManager.unmarshal(buffer);
    });
  }

  List<T> _getMany(Pointer<Uint64> Function() cCall) {
    return _store.runInTransaction(TxMode.Read, () {
      // OBX_bytes_array*, has two Uint64 members (data and size)
      Pointer<Uint64> bytesArray = cCall();
      try {
        return _fbManager.unmarshalArray(bytesArray);
      } finally {
        bindings.obx_bytes_array_free(bytesArray);
      }
    });
  }

  // returns list of ids.length objects of type T, each corresponding to the location of its ID in the ids array. Non-existant IDs become null
  List<T> getMany(List<int> ids) {
    if (ids.isEmpty) return [];

    return OBX_id_array.executeWith(
        ids,
        (ptr) => _getMany(
            () => checkObxPtr(bindings.obx_box_get_many(_cBox, ptr), "failed to get many objects from box", true)));
  }

  List<T> getAll() {
    return _getMany(() => checkObxPtr(bindings.obx_box_get_all(_cBox), "failed to get all objects from box", true));
  }

  QueryBuilder query(Condition qc) => QueryBuilder<T>(_store, _fbManager, _modelEntity.id.id, qc);

  int count({int limit = 0}) {
    Pointer<Uint64> count = allocate<Uint64>();
    try {
      checkObx(bindings.obx_box_count(_cBox, limit, count));
      return count.value;
    } finally {
      free(count);
    }
  }

  bool isEmpty() {
    Pointer<Uint8> isEmpty = allocate<Uint8>();
    try {
      checkObx(bindings.obx_box_is_empty(_cBox, isEmpty));
      return isEmpty.value > 0 ? true : false;
    } finally {
      free(isEmpty);
    }
  }

  bool contains(int id) {
    Pointer<Uint8> contains = allocate<Uint8>();
    try {
      checkObx(bindings.obx_box_contains(_cBox, id, contains));
      return contains.value > 0 ? true : false;
    } finally {
      free(contains);
    }
  }

  bool containsMany(List<int> ids) {
    Pointer<Uint8> contains = allocate<Uint8>();
    try {
      return OBX_id_array.executeWith(ids, (ptr) {
        checkObx(bindings.obx_box_contains_many(_cBox, ptr, contains));
        return contains.value > 0 ? true : false;
      });
    } finally {
      free(contains);
    }
  }

  bool remove(int id) {
    try {
      checkObx(bindings.obx_box_remove(_cBox, id));
    } on ObjectBoxException catch (ex) {
      if (ex.raw_msg == "code 404") {
        return false;
      }
      rethrow;
    }
    return true;
  }

  int removeMany(List<int> ids) {
    Pointer<Uint64> removedIds = allocate<Uint64>();
    try {
      return OBX_id_array.executeWith(ids, (ptr) {
        checkObx(bindings.obx_box_remove_many(_cBox, ptr, removedIds));
        return removedIds.value;
      });
    } finally {
      free(removedIds);
    }
  }

  int removeAll() {
    Pointer<Uint64> removedItems = allocate<Uint64>();
    try {
      checkObx(bindings.obx_box_remove_all(_cBox, removedItems));
      return removedItems.value;
    } finally {
      free(removedItems);
    }
  }

  get ptr => _cBox;
}
