import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:space_ocr/space_ocr.dart';

import '../host.dart';
import 'ppocr_models.dart';

/// Bundled assets only: recognizing an invoice never downloads a model or
/// sends the invoice to a remote service.
abstract final class LocalPpocr {
  static final _worker = PpocrWorker();
  static final _prepared = <String, Future<Map<String, String>>>{};
  static Future<Map<String, String>> _models(String tier) =>
      _prepared.putIfAbsent(tier, () => _prepare(tier));
  static Future<Map<String, String>> _prepare(String tier) async {
    final root = Directory(
      '${DesktopHost.dataDirectory()}/ocr-models/$ppocrModelRelease',
    );
    await root.create(recursive: true);
    final paths = <String, String>{};
    for (final entry in ppocrModelHashes.entries) {
      if (!entry.key.endsWith('_$tier.onnx')) {
        continue;
      }
      final file = File('${root.path}/${entry.key}');
      var valid = false;
      if (await file.exists()) {
        final path = file.path;
        valid = await Isolate.run(
          () =>
              sha256.convert(File(path).readAsBytesSync()).toString() ==
              entry.value,
        );
      }
      if (!valid) {
        final data = await rootBundle.load(
          'assets/models/ppocrv6/${entry.key}',
        );
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (await Isolate.run(() => sha256.convert(bytes).toString()) !=
            entry.value) {
          throw StateError('发票识别模型校验失败，请重新安装完整更新包。');
        }
        final temp = File('${file.path}.tmp');
        try {
          await temp.writeAsBytes(bytes, flush: true);
          await temp.rename(file.path);
        } finally {
          if (await temp.exists()) await temp.delete();
        }
      }
      paths[entry.key] = file.path;
    }
    return paths;
  }

  static Future<PpocrResult> recognize(
    String path, {
    bool enhanced = false,
  }) async {
    final tier = enhanced ? 'medium' : 'small';
    final models = await _models(tier);
    return _worker.recognize(
      path,
      models['PP-OCRv6_det_$tier.onnx']!,
      models['PP-OCRv6_rec_$tier.onnx']!,
    );
  }

  static Future<void> dispose() => _worker.close();
}

/// Confidence is not a calibrated probability. Ambiguous money/number lines
/// are excluded rather than turned into apparently correct ledger values.
String reliableInvoiceOcrText(PpocrResult result) {
  final lines = result.lines.where((line) {
    final text = line['text'] as String;
    final numeric = RegExp(r'[¥￥]|\d+\.\d{2}|^\d{8,20}$').hasMatch(text);
    return (line['confidence'] as num) >= (numeric ? .98 : .90);
  }).toList();
  final synthetic = <String>[];
  for (final label in lines.where((l) => l['text'] == '发票')) {
    final x = (label['x'] as num).toDouble(),
        y = (label['y'] as num).toDouble();
    final height = (label['height'] as num).toDouble();
    final below = lines.any(
      (l) =>
          l['text'] == '号码' &&
          ((l['x'] as num) - x).abs() < height &&
          (l['y'] as num) >= y &&
          (l['y'] as num) - y < height * 1.5,
    );
    if (!below) continue;
    final numbers = lines
        .where(
          (l) =>
              RegExp(r'^\d{8,20}$').hasMatch(l['text'] as String) &&
              (l['x'] as num) > x + height &&
              ((l['y'] as num) - y).abs() < height * 1.2,
        )
        .toList();
    if (numbers.length == 1) synthetic.add('发票号码：${numbers.single['text']}');
  }
  return [...synthetic, ...lines.map((l) => l['text'] as String)].join('\n');
}
