import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef P = Pointer<Void>;

final class _ApiBase extends Struct {
  external Pointer<NativeFunction<P Function(Uint32)>> getApi;
  external Pointer<NativeFunction<Pointer<Utf8> Function()>> version;
}

@Native<Pointer<_ApiBase> Function()>(
  assetId: 'package:space_ocr/onnxruntime',
  symbol: 'OrtGetApiBase',
)
external Pointer<_ApiBase> _ortGetApiBase();

@Native<
  Void Function(Pointer<Float>, Int64, Int64, Pointer<Int32>, Pointer<Float>)
>(assetId: 'package:space_ocr/ocr_math', symbol: 'ppocr_argmax')
external void ppocrArgmax(
  Pointer<Float> data,
  int rows,
  int columns,
  Pointer<Int32> indices,
  Pointer<Float> scores,
);

@Native<
  Int32 Function(
    Pointer<Float>,
    Int32,
    Int32,
    Float,
    Float,
    Float,
    Pointer<Float>,
    Int32,
  )
>(assetId: 'package:space_ocr/ocr_math', symbol: 'ppocr_boxes')
external int ppocrBoxes(
  Pointer<Float> data,
  int height,
  int width,
  double threshold,
  double boxThreshold,
  double unclip,
  Pointer<Float> boxes,
  int capacity,
);

/// Stable C API v18 table offsets from Microsoft's onnxruntime_c_api.h v1.18.1.
/// The API is requested by version; do not change offsets independently of it.
class OrtRuntime {
  late final Pointer<P> _api;
  late final P env, memory;
  OrtRuntime() {
    final base = _ortGetApiBase();
    _api = base.ref.getApi.asFunction<P Function(int)>()(18).cast<P>();
    if (_api == nullptr) throw StateError('ONNX Runtime C API v18 unavailable');
    final name = 'Space-PP-OCRv6'.toNativeUtf8();
    final out = calloc<P>();
    try {
      check(
        _f(3)
            .cast<
              NativeFunction<P Function(Int32, Pointer<Utf8>, Pointer<P>)>
            >()
            .asFunction<P Function(int, Pointer<Utf8>, Pointer<P>)>()(
          3,
          name,
          out,
        ),
      );
      env = out.value;
      check(
        _f(6)
            .cast<NativeFunction<P Function(P)>>()
            .asFunction<P Function(P)>()(env),
      );
      check(
        _f(69)
            .cast<NativeFunction<P Function(Int32, Int32, Pointer<P>)>>()
            .asFunction<P Function(int, int, Pointer<P>)>()(0, 0, out),
      );
      memory = out.value;
    } finally {
      calloc.free(out);
      calloc.free(name);
    }
  }
  P _f(int index) => _api[index];
  void check(P status) {
    if (status == nullptr) return;
    final message = _f(2)
        .cast<NativeFunction<Pointer<Utf8> Function(P)>>()
        .asFunction<Pointer<Utf8> Function(P)>()(status)
        .toDartString();
    release(93, status);
    throw StateError('ONNX Runtime: $message');
  }

  void release(int index, P pointer) {
    if (pointer != nullptr) {
      _f(index)
          .cast<NativeFunction<Void Function(P)>>()
          .asFunction<void Function(P)>()(pointer);
    }
  }

  OrtModel open(String path) {
    final out = calloc<P>();
    P options = nullptr;
    final modelPath = Platform.isWindows
        ? path.toNativeUtf16().cast<Void>()
        : path.toNativeUtf8().cast<Void>();
    try {
      check(
        _f(10)
            .cast<NativeFunction<P Function(Pointer<P>)>>()
            .asFunction<P Function(Pointer<P>)>()(out),
      );
      options = out.value;
      for (final option in [(24, 2), (25, 1), (23, 99)]) {
        check(
          _f(option.$1)
              .cast<NativeFunction<P Function(P, Int32)>>()
              .asFunction<P Function(P, int)>()(options, option.$2),
        );
      }
      check(
        _f(19)
            .cast<NativeFunction<P Function(P)>>()
            .asFunction<P Function(P)>()(options),
      );
      check(
        _f(7)
            .cast<NativeFunction<P Function(P, P, P, Pointer<P>)>>()
            .asFunction<P Function(P, P, P, Pointer<P>)>()(
          env,
          modelPath,
          options,
          out,
        ),
      );
      return OrtModel._(this, out.value);
    } finally {
      release(100, options);
      calloc.free(out);
      calloc.free(modelPath);
    }
  }

  void close() {
    release(94, memory);
    release(92, env);
  }
}

class OrtModel {
  final OrtRuntime runtime;
  final P session;
  OrtModel._(this.runtime, this.session);
  String metadata(String key) {
    final out = calloc<P>(), allocator = calloc<P>();
    final text = calloc<Pointer<Utf8>>();
    final name = key.toNativeUtf8();
    P meta = nullptr;
    try {
      runtime.check(
        runtime
            ._f(111)
            .cast<NativeFunction<P Function(P, Pointer<P>)>>()
            .asFunction<P Function(P, Pointer<P>)>()(session, out),
      );
      meta = out.value;
      runtime.check(
        runtime
            ._f(78)
            .cast<NativeFunction<P Function(Pointer<P>)>>()
            .asFunction<P Function(Pointer<P>)>()(allocator),
      );
      runtime.check(
        runtime
            ._f(116)
            .cast<
              NativeFunction<
                P Function(P, P, Pointer<Utf8>, Pointer<Pointer<Utf8>>)
              >
            >()
            .asFunction<
              P Function(P, P, Pointer<Utf8>, Pointer<Pointer<Utf8>>)
            >()(meta, allocator.value, name, text),
      );
      if (text.value == nullptr) return '';
      return text.value.toDartString();
    } finally {
      if (text.value != nullptr && allocator.value != nullptr) {
        runtime.check(
          runtime
              ._f(76)
              .cast<NativeFunction<P Function(P, P)>>()
              .asFunction<P Function(P, P)>()(
            allocator.value,
            text.value.cast(),
          ),
        );
      }
      runtime.release(118, meta);
      calloc.free(out);
      calloc.free(allocator);
      calloc.free(text);
      calloc.free(name);
    }
  }

  OrtTensor run(Float32List values, List<int> shape) {
    final data = calloc<Float>(values.length),
        dims = calloc<Int64>(shape.length);
    final input = calloc<P>(), output = calloc<P>();
    final inputNames = calloc<Pointer<Utf8>>(),
        outputNames = calloc<Pointer<Utf8>>();
    inputNames.value = 'x'.toNativeUtf8();
    outputNames.value = 'fetch_name_0'.toNativeUtf8();
    P info = nullptr;
    try {
      data.asTypedList(values.length).setAll(0, values);
      dims.asTypedList(shape.length).setAll(0, shape);
      runtime.check(
        runtime
            ._f(49)
            .cast<
              NativeFunction<
                P Function(P, P, Size, Pointer<Int64>, Size, Int32, Pointer<P>)
              >
            >()
            .asFunction<
              P Function(P, P, int, Pointer<Int64>, int, int, Pointer<P>)
            >()(
          runtime.memory,
          data.cast(),
          values.length * 4,
          dims,
          shape.length,
          1,
          input,
        ),
      );
      runtime.check(
        runtime
            ._f(9)
            .cast<
              NativeFunction<
                P Function(
                  P,
                  P,
                  Pointer<Pointer<Utf8>>,
                  Pointer<P>,
                  Size,
                  Pointer<Pointer<Utf8>>,
                  Size,
                  Pointer<P>,
                )
              >
            >()
            .asFunction<
              P Function(
                P,
                P,
                Pointer<Pointer<Utf8>>,
                Pointer<P>,
                int,
                Pointer<Pointer<Utf8>>,
                int,
                Pointer<P>,
              )
            >()(session, nullptr, inputNames, input, 1, outputNames, 1, output),
      );
      final shapeInfo = calloc<P>(),
          rank = calloc<Size>(),
          outputData = calloc<P>();
      try {
        runtime.check(
          runtime
              ._f(65)
              .cast<NativeFunction<P Function(P, Pointer<P>)>>()
              .asFunction<P Function(P, Pointer<P>)>()(output.value, shapeInfo),
        );
        info = shapeInfo.value;
        runtime.check(
          runtime
              ._f(61)
              .cast<NativeFunction<P Function(P, Pointer<Size>)>>()
              .asFunction<P Function(P, Pointer<Size>)>()(info, rank),
        );
        final dimensions = calloc<Int64>(rank.value);
        try {
          runtime.check(
            runtime
                ._f(62)
                .cast<NativeFunction<P Function(P, Pointer<Int64>, Size)>>()
                .asFunction<P Function(P, Pointer<Int64>, int)>()(
              info,
              dimensions,
              rank.value,
            ),
          );
          runtime.check(
            runtime
                ._f(51)
                .cast<NativeFunction<P Function(P, Pointer<P>)>>()
                .asFunction<P Function(P, Pointer<P>)>()(
              output.value,
              outputData,
            ),
          );
          final result = OrtTensor(
            runtime,
            output.value,
            outputData.value.cast<Float>(),
            List<int>.from(dimensions.asTypedList(rank.value)),
          );
          output.value = nullptr;
          return result;
        } finally {
          calloc.free(dimensions);
        }
      } finally {
        calloc.free(shapeInfo);
        calloc.free(rank);
        calloc.free(outputData);
      }
    } finally {
      runtime.release(99, info);
      runtime.release(96, input.value);
      runtime.release(96, output.value);
      calloc.free(data);
      calloc.free(dims);
      calloc.free(input);
      calloc.free(output);
      calloc.free(inputNames.value);
      calloc.free(outputNames.value);
      calloc.free(inputNames);
      calloc.free(outputNames);
    }
  }

  void close() => runtime.release(95, session);
}

class OrtTensor {
  final OrtRuntime runtime;
  final P value;
  final Pointer<Float> data;
  final List<int> shape;
  OrtTensor(this.runtime, this.value, this.data, this.shape);
  void close() => runtime.release(96, value);
}
