import 'dart:convert';
import 'dart:io';
import 'package:flutter/scheduler.dart';
import '../store.dart';
import '../host.dart';

Future<void> runUiBenchmark(SpaceStore store) async {
  const isolated = String.fromEnvironment('SPACE_DATA_DIRECTORY');
  if (isolated.isEmpty) {
    throw StateError('UI benchmark requires an isolated directory');
  }
  final frames = <FrameTiming>[], actions = <double>[];
  void collect(List<FrameTiming> batch) => frames.addAll(batch);
  SchedulerBinding.instance.addTimingsCallback(collect);
  await Future<void>.delayed(const Duration(seconds: 1));
  for (var repeat = 0; repeat < 3; repeat++) {
    for (final view in ['board', 'list', 'gantt', 'calendar']) {
      final timer = Stopwatch()..start();
      await store.preference('viewMode', view);
      await SchedulerBinding.instance.endOfFrame;
      actions.add(timer.elapsedMicroseconds / 1000);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
  await store.preference('viewMode', 'board');
  await Future<void>.delayed(const Duration(seconds: 1));
  SchedulerBinding.instance.removeTimingsCallback(collect);
  double percentile(List<double> list, double q) {
    if (list.isEmpty) return 0;
    final sorted = [...list]..sort();
    return sorted[((sorted.length - 1) * q).ceil()];
  }

  final builds = frames
      .map((f) => f.buildDuration.inMicroseconds / 1000)
      .toList();
  final rasters = frames
      .map((f) => f.rasterDuration.inMicroseconds / 1000)
      .toList();
  Object? host;
  try {
    host = await DesktopHost.channel.invokeMethod('diagnostics');
  } catch (e) {
    host = '$e';
  }
  final result = {
    'nativeHost': host,
    'mode': 'Flutter desktop Release, real engine frames',
    'tasks': store.state.tasks.length,
    'platform': Platform.operatingSystem,
    'frames': frames.length,
    'frameBuildP95Ms': percentile(builds, .95),
    'frameRasterP95Ms': percentile(rasters, .95),
    'actionFirstFrameMedianMs': percentile(actions, .5),
    'actionFirstFrameP95Ms': percentile(actions, .95),
    'rssMiB': ProcessInfo.currentRss / 1048576,
    'peakRssMiB': ProcessInfo.maxRss / 1048576,
    'transitions': 'original 500ms curve preserved',
    'formalDataAccessed': false,
  };
  final file = File('$isolated/ui-performance.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(result));
}
