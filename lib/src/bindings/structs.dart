import 'dart:ffi';
import "dart:typed_data";
import "package:ffi/ffi.dart";

// Note: IntPtr seems to be the the correct representation for size_t: "Represents a native pointer-sized integer in C."

class OBX_id_array extends Struct<OBX_id_array> {
  /*
    typedef struct OBX_id_array {
      obx_id* ids;
      size_t count;
    };
   */

  Pointer<Uint64> _itemsPtr;

  @IntPtr() // size_t
  int length;

  /// Get a copy of the list
  List<int> items() => Uint64List.view(_itemsPtr.asExternalTypedData(count: length).buffer).toList();

  /// Execute the given function, managing the resources consistently
  static R executeWith<R>(List<int> items, R Function(Pointer<OBX_id_array>) fn) {
    // allocate a temporary structure
    final ptr = Pointer<OBX_id_array>.allocate();

    // fill it with data
    OBX_id_array array = ptr.load();
    array.length = items.length;
    array._itemsPtr = Pointer<Uint64>.allocate(count: array.length);
    for (int i = 0; i < items.length; ++i) {
      array._itemsPtr.elementAt(i).store(items[i]);
    }

    // call the function with the structure and free afterwards
    try {
      return fn(ptr);
    } finally {
      array._itemsPtr.free();
      ptr.free();
    }
  }
}

class ByteBuffer {
  Pointer<Uint8> _ptr;
  int _size;

  ByteBuffer(this._ptr, this._size);

  ByteBuffer.allocate(Uint8List dartData, [bool align = true]) {
    _ptr = Pointer<Uint8>.allocate(count: align ? ((dartData.length + 3.0) ~/ 4.0) * 4 : dartData.length);
    for (int i = 0; i < dartData.length; ++i) {
      _ptr.elementAt(i).store(dartData[i]);
    }
    _size = dartData.length;
  }

  ByteBuffer.fromOBXBytes(Pointer<Uint64> obxPtr) {
    // extract fields from "struct OBX_bytes"
    _ptr = Pointer<Uint8>.fromAddress(obxPtr.load<int>());
    _size = obxPtr.elementAt(1).load<int>();
  }

  get ptr => _ptr;

  get voidPtr => Pointer<Void>.fromAddress(_ptr.address);

  get address => _ptr.address;

  get size => _size;

  Uint8List get data {
    var buffer = Uint8List(size);
    for (int i = 0; i < size; ++i) {
      buffer[i] = _ptr.elementAt(i).load<int>();
    }
    return buffer;
  }

  free() => _ptr.free();
}

class _SerializedByteBufferArray {
  Pointer<Uint64> _outerPtr,
      _innerPtr; // outerPtr points to the instance itself, innerPtr points to the respective OBX_bytes_array.bytes

  _SerializedByteBufferArray(this._outerPtr, this._innerPtr);

  get ptr => _outerPtr;

  free() {
    _innerPtr.free();
    _outerPtr.free();
  }
}

class ByteBufferArray {
  List<ByteBuffer> _buffers;

  ByteBufferArray(this._buffers);

  ByteBufferArray.fromOBXBytesArray(Pointer<Uint64> bytesArray) {
    _buffers = [];
    Pointer<Uint64> bufferPtrs = Pointer<Uint64>.fromAddress(bytesArray.load<int>()); // bytesArray.bytes
    int numBuffers = bytesArray.elementAt(1).load<int>(); // bytesArray.count
    for (int i = 0; i < numBuffers; ++i) {
      _buffers.add(ByteBuffer.fromOBXBytes(bufferPtrs.elementAt(2 * i)));
    } // 2 * i, because each instance of "struct OBX_bytes" has .data and .size
  }

  _SerializedByteBufferArray toOBXBytesArray() {
    Pointer<Uint64> bufferPtrs = Pointer<Uint64>.allocate(count: _buffers.length * 2);
    for (int i = 0; i < _buffers.length; ++i) {
      bufferPtrs.elementAt(2 * i).store(_buffers[i].ptr.address as int);
      bufferPtrs.elementAt(2 * i + 1).store(_buffers[i].size as int);
    }

    Pointer<Uint64> outerPtr = Pointer<Uint64>.allocate(count: 2);
    outerPtr.store(bufferPtrs.address);
    outerPtr.elementAt(1).store(_buffers.length);
    return _SerializedByteBufferArray(outerPtr, bufferPtrs);
  }

  get buffers => _buffers;
}

class OBX_int8_array /* extends Struct<OBX_int8_array> */ {
  Pointer<Uint8> _itemsPtr;

  // @IntPtr()() // size_t
  int count;

  List<int> items() => Int8List.view(_itemsPtr.asExternalTypedData(count: count).buffer).toList();

  OBX_int8_array.fromAddress(int address) {
    final structPtr = Pointer<Uint64>.fromAddress(address); // bootstrap
    _itemsPtr = Pointer<Uint8>.fromAddress(structPtr.load()); // 1st memory location contains a vector*
    count = structPtr.elementAt(1).load<int>(); // 2nd mem loc contains the scalar count
  }
}

class OBX_int16_array /* extends Struct<OBX_int16_array> */ {
  Pointer<Int16> _itemsPtr;

  // @IntPtr()() // size_t
  int count;

  List<int> items() => Int16List.view(_itemsPtr.asExternalTypedData(count: count).buffer).toList();

  OBX_int16_array.fromAddress(int address) {
    final structPtr = Pointer<Uint64>.fromAddress(address); // bootstrap
    _itemsPtr = Pointer<Int16>.fromAddress(structPtr.load()); // 1st memory location contains a vector*
    count = structPtr.elementAt(1).load<int>(); // 2nd mem loc contains the scalar count
  }
}

class OBX_int32_array /* extends Struct<OBX_int32_array> */ {
  Pointer<Int32> _itemsPtr;

  // @IntPtr()() // size_t
  int count;

  List<int> items() => Int32List.view(_itemsPtr.asExternalTypedData(count: count).buffer).toList();

  OBX_int32_array.fromAddress(int address) {
    final structPtr = Pointer<Uint64>.fromAddress(address); // bootstrap
    _itemsPtr = Pointer<Int32>.fromAddress(structPtr.load()); // 1st memory location contains a vector*
    count = structPtr.elementAt(1).load<int>(); // 2nd mem loc contains the scalar count
  }
}

class OBX_int64_array /* extends Struct<OBX_int64_array> */ {
  Pointer<Int64> _itemsPtr;

  // @IntPtr()() // size_t
  int count;

  List<int> items() => Int64List.view(_itemsPtr.asExternalTypedData(count: count).buffer).toList();

  OBX_int64_array.fromAddress(int address) {
    final structPtr = Pointer<Uint64>.fromAddress(address); // bootstrap
    _itemsPtr = Pointer<Int64>.fromAddress(structPtr.load()); // 1st memory location contains a vector*
    count = structPtr.elementAt(1).load<int>(); // 2nd mem loc contains the scalar count
  }
}

class OBX_string_array /* extends Struct<OBX_string_array> */ {

  Pointer<Pointer<Uint8>> _itemsPtr;

  // @IntPtr()() // size_t
  int count;

  List<String> items() {
    final list = <String>[];
    for (int i=0; i<count; i++) {
      list.add(Utf8.fromUtf8(_itemsPtr.elementAt(i).load().cast<Utf8>()));
    }
    return list;
  }

  OBX_string_array.fromAddress(int address) {
    final structPtr = Pointer<Uint64>.fromAddress(address); // bootstrap
    _itemsPtr = Pointer<Pointer<Uint8>>.fromAddress(structPtr.load()); // 1st memory location contains a vector*
    count = structPtr.elementAt(1).load<int>(); // 2nd mem loc contains the scalar count
  }
}

class OBX_float_array /* extends Struct<OBX_float_array> */ {

  Pointer<Float> _itemsPtr;

  // @IntPtr()() // size_t
  int count;

  List<double> items() => Float32List.view(_itemsPtr.asExternalTypedData(count: count).buffer).toList();

  OBX_float_array.fromAddress(int address) {
    final structPtr = Pointer<Uint64>.fromAddress(address); // bootstrap
    _itemsPtr = Pointer<Float>.fromAddress(structPtr.load()); // 1st memory location contains a vector*
    count = structPtr.elementAt(1).load<int>(); // 2nd mem loc contains the scalar count
  }
}


class OBX_double_array /* extends Struct<OBX_double_array> */ {

  Pointer<Double> _itemsPtr;

  // @IntPtr()() // size_t
  int count;

  List<double> items() => Float64List.view(_itemsPtr.asExternalTypedData(count: count).buffer).toList();

  OBX_double_array.fromAddress(int address) {
    final structPtr = Pointer<Uint64>.fromAddress(address); // bootstrap
    _itemsPtr = Pointer<Double>.fromAddress(structPtr.load()); // 1st memory location contains a vector*
    count = structPtr.elementAt(1).load<int>(); // 2nd mem loc contains the scalar count
  }
}