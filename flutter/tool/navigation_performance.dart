// Release-only navigation probe. Explicit empty directory and synthetic data.
// Shared unchanged instrumentation is also compiled against the 2.0.8 baseline.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:space_flutter/main.dart' show SpaceApp;
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';
import 'performance_main.dart' as probe;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['SPACE_FLUTTER_DATA_DIRECTORY'];
  if (path == null || path.isEmpty) {
    throw StateError('Isolated directory required');
  }
  final directory = Directory(path);
  if (directory.existsSync() && directory.listSync().isNotEmpty) {
    throw StateError('Requires an empty isolated directory');
  }
  directory.createSync(recursive: true);
  probe.directory = directory;
  final store = SpaceStore(SpaceRepository(directory));
  await store.initialize();
  final state = demoState(count: 120);
  await store.commit(
    state.copy(
      settings: {
        'appearance': 'dark',
        'dark': 'true',
        'navCollapsed': 'false',
        'overviewCollapsed': 'true',
        'viewMode': 'board',
      },
    ),
    'Synthetic navigation benchmark',
  );
  await store.reload();
  store.notice = null;
  runApp(
    KeyedSubtree(
      key: probe.root,
      child: SpaceApp(store: store),
    ),
  );
  void collect(List<FrameTiming> batch) => probe.timings.addAll(batch);
  SchedulerBinding.instance.addTimingsCallback(collect);
  final results = <Map<String, Object?>>[];
  try {
    await probe.waitForProbeForeground();
    await Future<void>.delayed(const Duration(seconds: 4));
    Future<void> measure(String name, Future<void> Function() action) async {
      final row = await probe.measure(name, action);
      results.add(row);
      File(
        '$path/$name.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(row));
    }

    for (final view in ['board', 'list', 'gantt', 'calendar']) {
      await store.preference('viewMode', view);
      await Future<void>.delayed(const Duration(seconds: 1));
      await measure('$view-navigation', () async {
        for (var i = 0; i < 10; i++) {
          await store.preference('navCollapsed', '${i.isEven}');
          await Future<void>.delayed(const Duration(milliseconds: 650));
        }
      });
    }
    await store.preference('viewMode', 'board');
    await Future<void>.delayed(const Duration(seconds: 1));
    await measure('navigation-reverse', () async {
      for (var i = 0; i < 16; i++) {
        await store.preference('navCollapsed', '${i.isEven}');
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      await Future<void>.delayed(const Duration(milliseconds: 650));
    });
    await measure(
      'post-navigation-idle',
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    File('$path/report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'version': const String.fromEnvironment('SPACE_PROBE_VERSION'),
        'mode':
            '${Platform.operatingSystem} Release / 120 synthetic tasks / dark / default window',
        'formalDataAccessed': false,
        'frameBudgetNote':
            'Build or raster stage above refresh budget; presentation/drop counts are not available',
        'results': results,
      }),
    );
  } catch (e, stack) {
    File('$path/error.txt').writeAsStringSync('$e\n$stack');
    exitCode = 1;
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(collect);
    store.dispose();
    exit(exitCode);
  }
}
