library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as image;

import 'src/ort.dart';

class OcrLine {
  final String text;
  final double confidence, x, y, height;
  const OcrLine(this.text, this.confidence, this.x, this.y, this.height);
  Map<String, Object> toJson() => {
    'text': text,
    'confidence': confidence,
    'x': x,
    'y': y,
    'height': height,
  };
}

class PpocrResult {
  final String text;
  final double confidence;
  final List<Map<String, dynamic>> lines;
  const PpocrResult(this.text, this.confidence, this.lines);
  factory PpocrResult.fromJson(Map j) => PpocrResult(
    j['text'] as String,
    (j['confidence'] as num).toDouble(),
    (j['lines'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList(),
  );
}

/// One persistent isolate owns all native handles. Idle shutdown explicitly
/// releases sessions and the environment before terminating the isolate.
class PpocrWorker {
  SendPort? _port;
  Isolate? _isolate;
  Timer? _idle;
  Future<void> _tail = Future.value();
  Future<PpocrResult> recognize(
    String path,
    String detector,
    String recognizer,
  ) {
    final completer = Completer<PpocrResult>();
    _idle?.cancel();
    _tail = _tail.catchError((Object _) {}).then((_) async {
      try {
        if (_port == null) {
          final ready = ReceivePort();
          _isolate = await Isolate.spawn(_worker, ready.sendPort);
          _port = await ready.first as SendPort;
          ready.close();
        }
        final reply = ReceivePort();
        _port!.send({
          'path': path,
          'detector': detector,
          'recognizer': recognizer,
          'reply': reply.sendPort,
        });
        final result = await reply.first as Map;
        reply.close();
        if (result['error'] != null) {
          throw StateError(result['error'] as String);
        }
        completer.complete(PpocrResult.fromJson(result));
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    _tail.whenComplete(() => _idle = Timer(const Duration(seconds: 25), close));
    return completer.future;
  }

  Future<void> close() async {
    _idle?.cancel();
    await _tail;
    final port = _port;
    if (port == null) return;
    _port = null;
    final reply = ReceivePort();
    port.send({'shutdown': true, 'reply': reply.sendPort});
    await reply.first;
    reply.close();
    _isolate?.kill();
    _isolate = null;
  }
}

void _worker(SendPort ready) async {
  final messages = ReceivePort();
  ready.send(messages.sendPort);
  OrtRuntime? runtime;
  _Pipeline? pipeline;
  String loaded = '';
  await for (final raw in messages) {
    final task = raw as Map;
    final reply = task['reply'] as SendPort;
    if (task['shutdown'] == true) {
      pipeline?.close();
      runtime?.close();
      reply.send(true);
      messages.close();
      return;
    }
    try {
      runtime ??= OrtRuntime();
      final signature = '${task['detector']}|${task['recognizer']}';
      if (signature != loaded) {
        pipeline?.close();
        pipeline = null;
        pipeline = _Pipeline(
          runtime,
          task['detector'] as String,
          task['recognizer'] as String,
        );
        loaded = signature;
      }
      reply.send(pipeline!.recognize(task['path'] as String));
    } catch (e) {
      reply.send({'error': e.toString()});
    }
  }
}

class _Pipeline {
  final OrtRuntime runtime;
  late OrtModel detector, recognizer;
  late List<String> characters;
  _Pipeline(this.runtime, String det, String rec) {
    detector = runtime.open(det);
    try {
      recognizer = runtime.open(rec);
      final dictionary = recognizer.metadata('character');
      if (dictionary.isEmpty) {
        throw StateError('PP-OCRv6 character dictionary is missing');
      }
      characters = ['', ...dictionary.split('\n'), ' '];
    } catch (_) {
      detector.close();
      rethrow;
    }
  }
  void close() {
    detector.close();
    recognizer.close();
  }

  Map<String, Object?> recognize(String path) {
    final bytes = File(path).readAsBytesSync();
    var source = image.decodeImage(bytes);
    if (source == null) throw StateError('无法解码发票图片');
    source = image.bakeOrientation(source);
    if (source.width * source.height > 48000000) {
      throw StateError('图片像素过大，请先缩小原图');
    }
    final scale = math.min(1.0, 1600 / math.max(source.width, source.height));
    final width = math.max(32, (source.width * scale / 32).round() * 32),
        height = math.max(32, (source.height * scale / 32).round() * 32);
    final resized = image.copyResize(
      source,
      width: width,
      height: height,
      interpolation: image.Interpolation.linear,
    );
    final detection = detector.run(_normalize(resized), [1, 3, height, width]);
    final regions = <List<double>>[];
    try {
      if (detection.shape.length != 4) {
        throw StateError('PP-OCRv6 detection output shape is invalid');
      }
      final h = detection.shape[2], w = detection.shape[3];
      final boxes = calloc<Float>(600 * 9);
      try {
        final count = ppocrBoxes(detection.data, h, w, .3, .5, 1.6, boxes, 600);
        if (count < 0) throw StateError('票面文字区域计算失败');
        if (count > 600) throw StateError('票面文字区域过多，请拆分图片');
        for (var i = 0; i < count; i++) {
          final box = List<double>.from((boxes + i * 9).asTypedList(9));
          for (var k = 0; k < 8; k += 2) {
            box[k] = (box[k] * source.width / w).clamp(0.0, source.width - 1.0);
            box[k + 1] = (box[k + 1] * source.height / h).clamp(
              0.0,
              source.height - 1.0,
            );
          }
          regions.add(box);
        }
      } finally {
        calloc.free(boxes);
      }
    } finally {
      detection.close();
    }
    final lines = <OcrLine>[];
    for (final box in regions) {
      final width = math.max(
            2,
            _distance(box[0], box[1], box[2], box[3]).round(),
          ),
          height = math.max(
            2,
            _distance(box[0], box[1], box[6], box[7]).round(),
          );
      final crop = image.copyRectify(
        source,
        topLeft: image.Point(box[0], box[1]),
        topRight: image.Point(box[2], box[3]),
        bottomRight: image.Point(box[4], box[5]),
        bottomLeft: image.Point(box[6], box[7]),
        interpolation: image.Interpolation.linear,
        toImage: image.Image(width: width, height: height),
      );
      var result = _read(crop);
      if (result.$2 < .72) {
        final rotated = _read(image.copyRotate(crop, angle: 180));
        if (rotated.$2 > result.$2) result = rotated;
      }
      if (result.$1.isNotEmpty && result.$2 >= .5) {
        final xs = [box[0], box[2], box[4], box[6]],
            ys = [box[1], box[3], box[5], box[7]];
        lines.add(
          OcrLine(
            result.$1,
            result.$2,
            xs.reduce(math.min),
            ys.reduce(math.min),
            ys.reduce(math.max) - ys.reduce(math.min),
          ),
        );
      }
    }
    lines.sort((a, b) => a.y.compareTo(b.y));
    final rows = <List<OcrLine>>[];
    for (final line in lines) {
      if (rows.isEmpty ||
          (line.y - rows.last.first.y).abs() >
              math.min(line.height, rows.last.first.height) * .45) {
        rows.add([line]);
      } else {
        rows.last.add(line);
      }
    }
    for (final row in rows) {
      row.sort((a, b) => a.x.compareTo(b.x));
    }
    final ordered = rows.expand((r) => r).toList();
    return {
      'text': rows.map((r) => r.map((l) => l.text).join('  ')).join('\n'),
      'confidence': ordered.isEmpty
          ? 0.0
          : ordered.map((r) => r.confidence).reduce((a, b) => a + b) /
                ordered.length,
      'lines': ordered.map((r) => r.toJson()).toList(),
    };
  }

  (String, double) _read(image.Image crop) {
    final resizedWidth = math.min(
      1536,
      math.max(8, (48 * crop.width / crop.height).ceil()),
    );
    final width = math.max(320, resizedWidth);
    final resized = image.copyResize(
      crop,
      width: resizedWidth,
      height: 48,
      interpolation: image.Interpolation.linear,
    );
    final normalized = _normalize(resized, padWidth: width);
    final output = recognizer.run(normalized, [1, 3, 48, width]);
    try {
      if (output.shape.length != 3 || output.shape[0] != 1) {
        throw StateError('PP-OCRv6 recognition output shape is invalid');
      }
      final steps = output.shape[1], classes = output.shape[2];
      if (classes != characters.length) {
        throw StateError(
          'PP-OCRv6 model and dictionary do not match: $classes / ${characters.length}',
        );
      }
      final indices = calloc<Int32>(steps), scores = calloc<Float>(steps);
      try {
        ppocrArgmax(output.data, steps, classes, indices, scores);
        final text = StringBuffer();
        var previous = -1, count = 0;
        var score = 0.0;
        for (var i = 0; i < steps; i++) {
          final index = indices[i];
          if (index != 0 && index != previous) {
            text.write(characters[index]);
            score += scores[i];
            count++;
          }
          previous = index;
        }
        return (text.toString(), count == 0 ? 0.0 : score / count);
      } finally {
        calloc.free(indices);
        calloc.free(scores);
      }
    } finally {
      output.close();
    }
  }
}

double _distance(double x, double y, double xx, double yy) =>
    math.sqrt((x - xx) * (x - xx) + (y - yy) * (y - yy));

Float32List _normalize(image.Image image, {int? padWidth}) {
  final width = padWidth ?? image.width, plane = width * image.height;
  final out = Float32List(plane * 3);
  // PP-OCR's published OpenCV pipeline expects BGR, not RGB.
  for (var y = 0; y < image.height; y++)
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y), i = y * width + x;
      out[i] = pixel.b / 127.5 - 1;
      out[plane + i] = pixel.g / 127.5 - 1;
      out[plane * 2 + i] = pixel.r / 127.5 - 1;
    }
  return out;
}
