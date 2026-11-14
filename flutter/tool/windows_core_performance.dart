// Background native-work probe. No UI/foreground smoothness claims.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:space_flutter/core/invoice_pdf.dart';
import 'package:space_flutter/core/invoice_pdf_engine.dart';
import 'package:space_flutter/core/ppocr.dart';
import 'invoice_refinement_performance.dart' show fixture;
import 'performance_main.dart' show processSample;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['SPACE_FLUTTER_DATA_DIRECTORY'];
  if (path == null || !path.contains('windows-baseline')) {
    throw StateError('Explicit isolated project output required');
  }
  final out = Directory(path);
  if (out.existsSync() && out.listSync().isNotEmpty) {
    throw StateError('Output must be empty');
  }
  out.createSync(recursive: true);
  final rows = <Map<String, Object?>>[];
  Future<void> measure(String name, Future<Object?> Function() action) async {
    final before = await processSample();
    final watch = Stopwatch()..start();
    final result = await action();
    watch.stop();
    final after = await processSample();
    rows.add({
      'scenario': name,
      'durationMs': watch.elapsedMicroseconds / 1000,
      'cpuCorePercent': (after['cpuSeconds']! - before['cpuSeconds']!) /
          (watch.elapsedMicroseconds / 1e6) * 100,
      'rssBeforeMiB': before['rssMiB'],
      'rssAfterMiB': after['rssMiB'],
      'processPeakRssMiB': ProcessInfo.maxRss / 1048576,
      'result': result,
    });
  }
  try {
    final input = Directory('${out.path}/input')..createSync();
    final files = await fixture(input);
    for (var run = 0; run < 3; run++) {
      late List<InvoiceSourcePage> pages;
      await measure('pdf-inspect-trim-100-$run', () async {
        pages = [];
        for (var i = 0; i < 100; i++) {
          pages.addAll(await InvoicePdf.inspect(files.$1, trim: true));
        }
        return {'pages': pages.length};
      });
      final sheets = const InvoiceLayout().arrange(pages, []);
      await measure('pdf-compose-100-$run', () async {
        final target = '${out.path}/merged-$run.pdf';
        await NativeInvoicePdf.write(target, sheets);
        final preview = await InvoicePdf.preview(target, 1);
        if (preview.pages != sheets.length) throw StateError('Page count mismatch');
        return {'pages': preview.pages, 'bytes': File(target).lengthSync()};
      });
      for (final enhanced in [false, true]) {
        await measure('ocr-${enhanced ? 'medium' : 'small'}-$run', () async {
          final result = await LocalPpocr.recognize(files.$2, enhanced: enhanced);
          if (result.text.trim().isEmpty) throw StateError('OCR returned no text');
          return {'characters': result.text.length, 'lines': result.lines.length};
        });
      }
    }
    await measure('ocr-worker-close-and-idle-5s', () async {
      await LocalPpocr.dispose();
      await Future<void>.delayed(const Duration(seconds: 5));
      return {'workerClosed': true};
    });
  } catch (error, stack) {
    File('${out.path}/error.txt').writeAsStringSync('$error\n$stack');
    exitCode = 1;
  } finally {
    await LocalPpocr.dispose();
    File('${out.path}/result.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'mode': 'Windows Release background native processing',
        'formalDataAccessed': false,
        'frontendPerformanceMeasured': false,
        'results': rows,
      }),
    );
  }
  exit(exitCode);
}
