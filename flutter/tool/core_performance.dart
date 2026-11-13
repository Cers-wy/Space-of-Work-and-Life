// Release-only core probe with Flutter's native-asset bundling; never ship it.
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'benchmark.dart' as benchmark;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['SPACE_FLUTTER_DATA_DIRECTORY'];
  if (output == null || output.isEmpty) {
    throw StateError('Explicit isolated output directory required');
  }
  for (final count in [1000, 10000]) {
    await benchmark.main([
      '$count',
      output,
      'Flutter Release AOT core probe; no UI frame timing',
    ]);
  }
  exit(0);
}
