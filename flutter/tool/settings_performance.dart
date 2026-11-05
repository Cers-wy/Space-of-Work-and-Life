// Separate Release entry point, never the packaged app. This same source also
// runs against the 2.0.8 baseline without importing the new settings widget.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/main.dart' show SpaceApp;
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/dialogs.dart';

import 'performance_main.dart' as probe;

T? elementValue<T>(T? Function(Element) read) {
  T? value;
  void visit(Element element) {
    value ??= read(element);
    if (value == null) element.visitChildren(visit);
  }

  (probe.root.currentContext! as Element).visitChildren(visit);
  return value;
}

SpaceButton? category(int index) => elementValue(
  (e) =>
      e.widget is SpaceButton &&
          e.widget.key == ValueKey('settings-category-$index')
      ? e.widget as SpaceButton
      : null,
);

SpaceButton textButton(String label) {
  SpaceButton? result;
  void visit(Element element) {
    if (element.widget is SpaceButton) {
      var matches = false;
      void text(Element child) {
        if (child.widget is Text && (child.widget as Text).data == label) {
          matches = true;
        }
        child.visitChildren(text);
      }

      element.visitChildren(text);
      if (matches) result ??= element.widget as SpaceButton;
    }
    if (result == null) element.visitChildren(visit);
  }

  (probe.root.currentContext! as Element).visitChildren(visit);
  return result ?? (throw StateError('Missing button: $label'));
}

ScrollPosition settingsScroll() {
  ScrollPosition? position;
  void visit(Element e) {
    if (e is StatefulElement && e.state is ScrollableState) {
      final candidate = (e.state as ScrollableState).position;
      if (candidate.axis == Axis.vertical) position = candidate;
    }
    e.visitChildren(visit);
  }

  (probe.root.currentContext! as Element).visitChildren(visit);
  return position ?? (throw StateError('Missing settings scroll position'));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['SPACE_FLUTTER_DATA_DIRECTORY'];
  if (path == null || path.isEmpty) {
    throw StateError('Explicit isolated directory required');
  }
  final directory = Directory(path);
  if (directory.existsSync() && directory.listSync().isNotEmpty) {
    throw StateError('Requires a new, empty isolated directory');
  }
  await directory.create(recursive: true);
  probe.directory = directory;
  final store = SpaceStore(SpaceRepository(directory));
  await store.initialize();
  await store.commit(
    demoState(count: 120).copy(
      settings: {
        'appearance': 'light',
        'dark': 'false',
        'navCollapsed': 'false',
        'overviewCollapsed': 'true',
        'viewMode': 'board',
      },
    ),
    'Isolated synthetic settings benchmark',
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
  final frameLatencies = <String, List<double>>{};
  Future<void> nextFrame(String name, VoidCallback action) async {
    final watch = Stopwatch()..start();
    action();
    await SchedulerBinding.instance.endOfFrame;
    (frameLatencies[name] ??= []).add(watch.elapsedMicroseconds / 1000);
  }

  Future<void> measure(String name, Future<void> Function() action) async {
    final row = await probe.measure(name, action);
    if (frameLatencies[name] case final List<double> latencies) {
      row['programmaticActionToNextFrameMs'] = latencies;
    }
    results.add(row);
  }

  try {
    await probe.waitForProbeForeground();
    await Future<void>.delayed(const Duration(seconds: 3));
    await measure('settings-open-close', () async {
      for (var i = 0; i < 6; i++) {
        await nextFrame('settings-open-close', () {
          unawaited(showSettings(probe.workspaceContext(), store));
        });
        await Future<void>.delayed(const Duration(milliseconds: 400));
        textButton('完成').onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    });
    unawaited(showSettings(probe.workspaceContext(), store));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final hasCategories = category(0) != null;
    await measure(
      'settings-idle',
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    if (hasCategories) {
      await measure('settings-category-switch', () async {
        for (final index in [1, 3, 2, 4, 0, 3, 1, 2, 4, 0]) {
          await nextFrame(
            'settings-category-switch',
            () => category(index)!.onPressed!(),
          );
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      });
    }
    final position = settingsScroll();
    final scrollExtent = position.maxScrollExtent;
    await measure('settings-scroll', () async {
      for (var i = 0; i < 8; i++) {
        await position.animateTo(
          i.isEven ? position.maxScrollExtent : 0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.decelerate,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    results.last['scrollExtentPx'] = scrollExtent;
    if (hasCategories) category(1)!.onPressed!();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await measure('settings-theme-switch', () async {
      for (var i = 0; i < 6; i++) {
        await nextFrame(
          'settings-theme-switch',
          () => textButton(i.isEven ? '深色' : '浅色').onPressed!(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
    });
    textButton('完成').onPressed!();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await measure(
      'settings-closed-idle',
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    final size = probe.root.currentContext!.size;
    await File('$path/report.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': const String.fromEnvironment('SPACE_PROBE_VERSION'),
        'platform': Platform.operatingSystem,
        'buildMode': 'Release',
        'taskCount': 120,
        'windowLogicalSize': {'width': size?.width, 'height': size?.height},
        'initialAppearance': 'light',
        'categoriesAvailable': hasCategories,
        'formalDataAccessed': false,
        'networkTransfersPerformed': false,
        'latencyNote':
            'Programmatic callback to next Flutter frame; excludes native input and display presentation latency.',
        'baselineNote':
            'Category switching is a new scenario; common scenarios use the identical probe source against 2.0.8 and the final version.',
        'frameBudgetNote':
            'Build/raster budget overruns are not direct presentation dropped-frame counts.',
        'results': results,
      }),
    );
  } catch (e, stack) {
    await File('$path/error.txt').writeAsString('$e\n$stack');
    exitCode = 1;
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(collect);
    store.dispose();
    exit(exitCode);
  }
}
