import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:space_flutter/core/ppocr_models.dart';

Future<void> main(List<String> args) async {
  final directory = Directory('assets/models/ppocrv6');
  await directory.create(recursive: true);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final proxy =
      Platform.environment['HTTPS_PROXY'] ??
      Platform.environment['https_proxy'];
  if (proxy != null) {
    final uri = Uri.parse(proxy);
    client.findProxy = (_) => 'PROXY ${uri.host}:${uri.port}';
  }
  try {
    for (final entry in ppocrModelHashes.entries) {
      final file = File('${directory.path}/${entry.key}');
      if (await file.exists() &&
          (await sha256.bind(file.openRead()).first).toString() ==
              entry.value) {
        stdout.writeln('${entry.key}: verified');
        continue;
      }
      final task = entry.key.contains('_det_') ? 'det' : 'rec';
      final uri = Uri.parse(
        'https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/$ppocrModelRelease/onnx/PP-OCRv6/$task/${entry.key}',
      );
      final temp = File('${file.path}.download');
      try {
        final response = await (await client.getUrl(uri))
            .close()
            .timeout(const Duration(seconds: 45));
        if (response.statusCode != 200) {
          throw StateError('Model download failed: ${response.statusCode}');
        }
        final sink = temp.openWrite();
        try {
          await sink.addStream(response.timeout(const Duration(seconds: 45)));
        } finally {
          await sink.close();
        }
        if ((await sha256.bind(temp.openRead()).first).toString() !=
            entry.value) {
          throw StateError('Model SHA256 mismatch: ${entry.key}');
        }
        await temp.rename(file.path);
        stdout.writeln('${entry.key}: downloaded and verified');
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    }
  } finally {
    client.close(force: true);
  }
}
