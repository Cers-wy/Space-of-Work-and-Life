// A separate Release entry point. Uses synthetic data in an explicitly empty
// directory; this entry point is never packaged as the user application.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi' hide Size;
import 'package:ffi/ffi.dart';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:space_flutter/main.dart' show SpaceApp;
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/core/richtext.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/dialogs.dart';
import 'package:space_flutter/ui/theme.dart' show CardFlow;
import 'package:space_flutter/ui/workspace.dart';

final root = GlobalKey();
final timings = <FrameTiming>[];
late Directory directory;

final _user32 = DynamicLibrary.open('user32.dll');
final _getForegroundWindow = _user32
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
      'GetForegroundWindow',
    );
final _getWindowProcess = _user32
    .lookupFunction<
      Uint32 Function(Pointer<Void>, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint32>)
    >('GetWindowThreadProcessId');
bool nativeForeground() {
  if (!Platform.isWindows) {
    return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }
  final value = calloc<Uint32>();
  try {
    _getWindowProcess(_getForegroundWindow(), value);
    return value.value == pid;
  } finally {
    calloc.free(value);
  }
}

// Optional manual start gate lets the UI test driver focus the window before
// any measured action. This is probe-only code and never ships in the app.
Future<void> waitForProbeForeground() async {
  final gate = Platform.environment['SPACE_PROBE_START_GATE'];
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while ((gate != null && !File(gate).existsSync()) || !nativeForeground()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Probe requires its start gate and foreground focus');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

class ForegroundProbe extends WidgetsBindingObserver {
  bool uninterrupted =
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) uninterrupted = false;
  }
}

/// True while sampling is paused because the probe window is unfocused.
final probePaused = ValueNotifier<bool>(false);

/// Pauses until the probe window regains foreground focus so every scenario
/// is sampled in the foreground. Probe-only code, never ships in the app.
Future<void> awaitProbeForeground() async {
  final deadline = DateTime.now().add(const Duration(minutes: 10));
  while (!nativeForeground()) {
    probePaused.value = true;
    if (DateTime.now().isAfter(deadline)) {
      probePaused.value = false;
      throw StateError(
        'Measurement paused over 10 minutes waiting for foreground focus',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  probePaused.value = false;
}

/// Amber banner shown over the probe UI whenever sampling is paused because
/// the window lost focus; clicking the window resumes the run automatically.
class ProbePauseBanner extends StatelessWidget {
  const ProbePauseBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(
        child: ValueListenableBuilder(
          valueListenable: probePaused,
          builder: (_, bool paused, _) =>
              paused
              ? Material(
                  color: const Color(0xe6b7791a),
                  elevation: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 18,
                      horizontal: 24,
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '⏸ 测量已暂停 —— 请点击本窗口使其置于最前，采样将自动继续',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

T? findWidget<T extends Widget>() {
  T? found;
  void visit(Element e) {
    if (e.widget is T) {
      found ??= e.widget as T;
    }
    if (found == null) e.visitChildren(visit);
  }

  (root.currentContext! as Element).visitChildren(visit);
  return found;
}

BuildContext workspaceContext() {
  BuildContext? found;
  void visit(Element e) {
    if (e.widget is Workspace) found ??= e;
    if (found == null) e.visitChildren(visit);
  }

  (root.currentContext! as Element).visitChildren(visit);
  return found!;
}

Future<Map<String, num>> processSample() async {
  if (Platform.isWindows) {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-Command',
      '(Get-Process -Id $pid | Select-Object CPU,WorkingSet64 | ConvertTo-Json -Compress)',
    ]);
    if (result.exitCode != 0) throw StateError('Process sample failed');
    final values = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    return {
      'cpuSeconds': (values['CPU'] as num).toDouble(),
      'psRssMiB': (values['WorkingSet64'] as num) / 1048576,
      'rssMiB': ProcessInfo.currentRss / 1048576,
    };
  }
  final result = await Process.run('/bin/ps', [
    '-p',
    '$pid',
    '-o',
    'time=,rss=',
  ]);
  if (result.exitCode != 0) throw StateError('Process sample failed');
  final parts = (result.stdout as String).trim().split(RegExp(r'\s+'));
  var seconds = 0.0;
  for (final part in parts[0].split(':')) {
    seconds = seconds * 60 + double.parse(part);
  }
  return {
    'cpuSeconds': seconds,
    'psRssMiB': int.parse(parts[1]) / 1024,
    'rssMiB': ProcessInfo.currentRss / 1048576,
  };
}

double _percentile(Iterable<double> values, double p) {
  final sorted = values.toList()..sort();
  return sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * p).ceil()];
}

/// Measures a scenario, redoing it when focus was lost mid-sample so the
/// recorded sample always reflects an uninterrupted foreground run (max 2
/// retries; the pause banner guides the user back to the window).
Future<Map<String, Object?>> measure(
  String name,
  Future<void> Function() action,
) async {
  var result = await _measureOnce(name, action);
  var attempts = 1;
  while (!(result['foregroundThroughout'] as bool? ?? false) && attempts < 3) {
    await awaitProbeForeground();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    result = await _measureOnce(name, action);
    attempts++;
  }
  return result;
}

Future<Map<String, Object?>> _measureOnce(
  String name,
  Future<void> Function() action,
) async {
  await awaitProbeForeground();
  timings.clear();
  // Probe-only diagnostics: prove which smoke clock is compiled in, the
  // window size, and how many smoke cards are actually mounted, so the A/B
  // protocol can self-check instead of trusting build flags.
  final view = ui.PlatformDispatcher.instance.views.first;
  var cardFlowTotal = 0, cardFlowSmoke = 0;
  void countFlows(Element e) {
    if (e.widget is CardFlow) {
      cardFlowTotal++;
      if ((e.widget as CardFlow).enabled) cardFlowSmoke++;
    }
    e.visitChildren(countFlows);
  }

  (root.currentContext! as Element).visitChildren(countFlows);
  final smokeClock = kLegacySmokeClock ? 'legacy-per-card-20hz' : 'shared-13.3hz';
  final windowLogicalSize =
      '${(view.physicalSize.width / view.devicePixelRatio).toStringAsFixed(0)}'
      'x'
      '${(view.physicalSize.height / view.devicePixelRatio).toStringAsFixed(0)}';
  final foreground = ForegroundProbe();
  WidgetsBinding.instance.addObserver(foreground);
  final before = await processSample(), timer = Stopwatch()..start();
  final frameStart = Timeline.now;
  await action();
  final frameEnd = Timeline.now;
  final after = await processSample();
  WidgetsBinding.instance.removeObserver(foreground);
  final measuredFrames = timings.where((t) {
    final start = t.timestampInMicroseconds(ui.FramePhase.buildStart);
    return start >= frameStart && start < frameEnd;
  }).toList();
  double p95(Iterable<double> values) {
    final list = values.toList()..sort();
    return list.isEmpty ? 0 : list[((list.length - 1) * .95).ceil()];
  }

  final result = <String, Object?>{
    'scenario': name,
    'seconds': timer.elapsedMilliseconds / 1000,
    'cpuMeanPercent':
        (after['cpuSeconds']! - before['cpuSeconds']!) /
        timer.elapsedMicroseconds *
        100000000,
    ...after,
    'imageCacheBytes': PaintingBinding.instance.imageCache.currentSizeBytes,
    'imageCacheCount': PaintingBinding.instance.imageCache.currentSize,
    'liveImages': PaintingBinding.instance.imageCache.liveImageCount,
    'frameCount': measuredFrames.length,
    'buildP95Ms': p95(
      measuredFrames.map((t) => t.buildDuration.inMicroseconds / 1000),
    ),
    'rasterP95Ms': p95(
      measuredFrames.map((t) => t.rasterDuration.inMicroseconds / 1000),
    ),
    'buildP99Ms': _percentile(
      measuredFrames.map((t) => t.buildDuration.inMicroseconds / 1000),
      .99,
    ),
    'rasterP99Ms': _percentile(
      measuredFrames.map((t) => t.rasterDuration.inMicroseconds / 1000),
      .99,
    ),
    'buildMaxMs': _percentile(
      measuredFrames.map((t) => t.buildDuration.inMicroseconds / 1000),
      1,
    ),
    'rasterMaxMs': _percentile(
      measuredFrames.map((t) => t.rasterDuration.inMicroseconds / 1000),
      1,
    ),
    'refreshRateHz':
        ui.PlatformDispatcher.instance.views.first.display.refreshRate,
    'frameBudgetMs':
        1000 / ui.PlatformDispatcher.instance.views.first.display.refreshRate,
    'budgetSampleCount': measuredFrames.length,
    'overBudgetFrames': measuredFrames.where((t) {
      final budget =
          1000000 /
          ui.PlatformDispatcher.instance.views.first.display.refreshRate;
      return t.buildDuration.inMicroseconds > budget ||
          t.rasterDuration.inMicroseconds > budget;
    }).length,
    'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
    'foregroundThroughout': foreground.uninterrupted,
    'smokeClock': smokeClock,
    'windowLogicalSize': windowLogicalSize,
    'cardFlowTotal': cardFlowTotal,
    'cardFlowSmokeEnabled': cardFlowSmoke,
  };
  await File(
    '${directory.path}/$name.json',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  return result;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['SPACE_FLUTTER_DATA_DIRECTORY'];
  if (path == null || path.isEmpty) {
    throw StateError('Explicit isolated directory required');
  }
  directory = Directory(path);
  if (directory.existsSync() && directory.listSync().isNotEmpty) {
    throw StateError('Benchmark requires an empty directory');
  }
  await directory.create(recursive: true);
  // Deterministic large screenshot-like PNGs, created before measurements.
  final images = <RichRun>[];
  for (final size in [const Size(4096, 2304), const Size(3840, 2160)]) {
    final recorder = ui.PictureRecorder();
    final drawing = Canvas(recorder);
    drawing.drawColor(const Color(0xffeef2ff), BlendMode.src);
    for (var i = 0; i < 240; i++) {
      drawing.drawRect(
        Rect.fromLTWH(
          (i * 71 % 3500).toDouble(),
          (i * 37 % 2000).toDouble(),
          500,
          16,
        ),
        Paint()..color = Color(0xff334455 + i * 193),
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    images.add(RichRun(image: data!.buffer.asUint8List()));
    image.dispose();
    picture.dispose();
  }
  final repo = SpaceRepository(directory), store = SpaceStore(repo);
  await store.initialize();
  final state = demoState(count: 120);
  final imageTask = state.tasks.first.patch({
    'description': '合成大图预览',
    'richDescription': base64Encode(
      FlatRtfd.encode([RichRun(text: '合成大图预览\n'), ...images]),
    ),
  });
  await store.commit(
    state.copy(
      tasks: [imageTask, ...state.tasks.skip(1)],
      settings: {
        'appearance': 'dark',
        'dark': 'true',
        'navCollapsed': 'true',
        'overviewCollapsed': 'true',
        'viewMode': 'board',
      },
    ),
    '隔离性能合成样本',
  );
  await store.reload();
  store.notice = null;
  runApp(
    KeyedSubtree(
      key: root,
      child: Stack(
        children: [
          SpaceApp(store: store),
          const ProbePauseBanner(),
        ],
      ),
    ),
  );
  final frames = <FrameTiming>[];
  void collect(List<FrameTiming> batch) {
    frames.addAll(batch);
    timings.addAll(batch);
  }

  SchedulerBinding.instance.addTimingsCallback(collect);
  try {
    await awaitProbeForeground();
    await Future<void>.delayed(const Duration(seconds: 4));
    final results = <Map<String, Object?>>[];
    results.add(
      await measure(
        'board-idle',
        () => Future<void>.delayed(const Duration(seconds: 10)),
      ),
    );
    results.add(
      await measure('navigation-toggle', () async {
        for (var i = 0; i < 10; i++) {
          await store.preference('navCollapsed', '${i.isOdd}');
          await Future<void>.delayed(const Duration(milliseconds: 650));
        }
      }),
    );
    results.add(
      await measure('board-resize', () async {
        for (var i = 0; i < 12; i++) {
          await store.preference(
            'boardWidth.todo',
            '${[.5, 2 / 3, .75, 1.0][i % 4]}',
          );
          await Future<void>.delayed(const Duration(milliseconds: 650));
        }
      }),
    );
    results.add(
      await measure('board-scroll', () async {
        ScrollableState? scroll;
        void visit(Element e) {
          if (e is StatefulElement && e.state is ScrollableState) {
            final candidate = e.state as ScrollableState;
            if (candidate.position.axis == Axis.vertical &&
                candidate.position.maxScrollExtent > 0) {
              scroll ??= candidate;
            }
          }
          e.visitChildren(visit);
        }

        (root.currentContext! as Element).visitChildren(visit);
        if (scroll == null) throw StateError('Scrollable board required');
        for (var i = 0; i < 6; i++) {
          await scroll!.position.animateTo(
            i.isEven ? scroll!.position.maxScrollExtent : 0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
          );
        }
      }),
    );
    results.add(
      await measure('view-switch', () async {
        for (final view in ['list', 'gantt', 'calendar', 'board']) {
          await store.preference('viewMode', view);
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }),
    );
    for (var i = 0; i < 3; i++) {
      final dialog = editTask(
        workspaceContext(),
        store,
        imageTask,
        existing: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      results.add(
        await measure('image-open-$i', () async {
          final editor = findWidget<q.QuillEditor>();
          if (editor == null) throw StateError('Image editor not mounted');
          for (var j = 0; j < 24; j++) {
            editor.controller.updateSelection(
              TextSelection.collapsed(offset: j % 4),
              q.ChangeSource.local,
            );
            await Future<void>.delayed(const Duration(milliseconds: 40));
          }
        }),
      );
      Navigator.of(workspaceContext()).pop();
      await dialog;
      results.add(
        await measure(
          'image-closed-$i',
          () => Future<void>.delayed(const Duration(seconds: 2)),
        ),
      );
    }
    for (final view in ['list', 'gantt', 'calendar']) {
      await store.preference('viewMode', view);
      await Future<void>.delayed(const Duration(seconds: 1));
      results.add(
        await measure(
          '$view-idle',
          () => Future<void>.delayed(const Duration(seconds: 2)),
        ),
      );
    }
    final report = {
      'mode':
          '${Platform.operatingSystem} Release / 120 synthetic tasks / two 4K images',
      'formalDataAccessed': false,
      'smokeClock': kLegacySmokeClock ? 'legacy-per-card-20hz' : 'shared-13.3hz',
      'frameCount': frames.length,
      'results': results,
    };
    await File(
      '${directory.path}/report.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  } catch (e, stack) {
    await File('${directory.path}/error.txt').writeAsString('$e\n$stack');
    exitCode = 1;
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(collect);
    store.dispose();
    exit(exitCode);
  }
}
