import 'dart:convert';
import 'dart:io';

import 'package:space_ocr/space_ocr.dart';

/// Functional check, not a performance benchmark. Never writes to the ledger.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/ppocr_smoke.dart IMAGE [small|medium]',
    );
    exitCode = 64;
    return;
  }
  final tier = args.length > 1 ? args[1] : 'small';
  final worker = PpocrWorker();
  try {
    final result = await worker.recognize(
      File(args[0]).absolute.path,
      File('assets/models/ppocrv6/PP-OCRv6_det_$tier.onnx').absolute.path,
      File('assets/models/ppocrv6/PP-OCRv6_rec_$tier.onnx').absolute.path,
    );
    stdout.writeln(
      jsonEncode({
        'model': 'PP-OCRv6_$tier',
        'text': result.text,
        'confidence': result.confidence,
        'lines': result.lines,
      }),
    );
  } finally {
    await worker.close();
  }
}
