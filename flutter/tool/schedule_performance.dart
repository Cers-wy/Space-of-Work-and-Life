// Isolated Release probe limited to Gantt and calendar month UI.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:space_flutter/main.dart' show SpaceApp;
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/schedule.dart';
import 'performance_main.dart' as probe;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['SPACE_FLUTTER_DATA_DIRECTORY'];
  if (path == null || path.isEmpty) {
    throw StateError('Isolated empty directory required');
  }
  final dir = Directory(path);
  if (dir.existsSync() && dir.listSync().isNotEmpty) {
    throw StateError('Directory must be empty');
  }
  dir.createSync(recursive: true);
  probe.directory = dir;
  final store = SpaceStore(SpaceRepository(dir));
  await store.initialize();
  final date = beijingDay();
  final data = demoState(count: 600);
  await store.commit(
    data.copy(
      tasks: [
        for (final (i, t) in data.tasks.indexed)
          t.patch({
            'startDate': dayString(
              DateTime.utc(date.year, date.month, 1 + i % 20),
            ),
            'due': dayString(DateTime.utc(date.year, date.month, 10 + i % 20)),
          }),
      ],
      settings: {
        'appearance': 'dark',
        'viewMode': 'gantt',
        'calendarMode': 'month',
        'navCollapsed': 'true',
        'overviewCollapsed': 'true',
      },
    ),
    'Synthetic schedule probe',
  );
  store.notice = null;
  runApp(
    RepaintBoundary(
      key: probe.root,
      child: SpaceApp(store: store),
    ),
  );
  void collect(List<FrameTiming> batch) => probe.timings.addAll(batch);
  SchedulerBinding.instance.addTimingsCallback(collect);
  final results = <Map<String, Object?>>[];
  try {
    final gate = Platform.environment['SPACE_PROBE_START_GATE'];
    if (gate != null) {
      while (!File(gate).existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    await probe.waitForProbeForeground();
    await Future<void>.delayed(const Duration(seconds: 3));
    final response = <double>[];
    Future<void> measure(String name, Future<void> Function() action) async {
      response.clear();
      final row = await probe.measure(name, action);
      final sorted = [...response]..sort();
      row['actionFirstFrameP95Ms'] = sorted.isEmpty
          ? null
          : sorted[((sorted.length - 1) * .95).ceil()];
      row['actions'] = sorted.length;
      results.add(row);
    }

    Future<void> capture(String name) async {
      final boundary =
          probe.root.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$path/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    }

    await capture('gantt');

    await measure(
      'gantt-idle',
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await measure('gantt-scroll', () async {
      final element = probe.root.currentContext! as Element;
      final scrolls = <ScrollableState>[];
      void visit(Element e) {
        if (e is StatefulElement && e.state is ScrollableState) {
          scrolls.add(e.state as ScrollableState);
        }
        e.visitChildren(visit);
      }

      element.visitChildren(visit);
      for (var i = 0; i < 10; i++) {
        for (final scroll in scrolls) {
          if (scroll.mounted &&
              scroll.position.hasContentDimensions &&
              scroll.position.maxScrollExtent > 0) {
            scroll.position.animateTo(
              i.isEven ? scroll.position.maxScrollExtent : 0,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
            );
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    });
    await store.preference('viewMode', 'calendar');
    await Future<void>.delayed(const Duration(seconds: 1));
    await measure(
      'calendar-month-idle',
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await measure('calendar-month-switch', () async {
      dynamic state;
      void visit(Element e) {
        if (e.widget is CalendarView && e is StatefulElement) state = e.state;
        e.visitChildren(visit);
      }

      (probe.root.currentContext! as Element).visitChildren(visit);
      for (var i = 0; i < 10; i++) {
        final timer = Stopwatch()..start();
        state.move(i.isEven ? 1 : -1);
        await SchedulerBinding.instance.endOfFrame;
        response.add(timer.elapsedMicroseconds / 1000);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    });
    await capture('calendar-month');
    if (const bool.fromEnvironment('SPACE_PROBE_NEW_FEATURES')) {
      await store.preference('viewMode', 'gantt');
      await Future<void>.delayed(const Duration(seconds: 1));
      await measure('gantt-month-scale-switch', () async {
        dynamic state;
        void visit(Element e) {
          if (e.widget is GanttView && e is StatefulElement) state = e.state;
          e.visitChildren(visit);
        }

        (probe.root.currentContext! as Element).visitChildren(visit);
        for (var i = 0; i < 12; i++) {
          final timer = Stopwatch()..start();
          state.moveMonth(i.isEven ? 1 : -1);
          await store.preference('ganttMode', ['day', 'week', 'month'][i % 3]);
          await SchedulerBinding.instance.endOfFrame;
          response.add(timer.elapsedMicroseconds / 1000);
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      });
    }
    File('$path/report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'version': const String.fromEnvironment('SPACE_PROBE_VERSION'),
        'platform': Platform.operatingSystem,
        'mode': 'Release',
        'tasks': 600,
        'window': '1380x860 default',
        'theme': 'dark',
        'formalDataAccessed': false,
        'results': results,
      }),
    );
  } catch (e, st) {
    File('$path/error.txt').writeAsStringSync('$e\n$st');
    exitCode = 1;
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(collect);
    store.dispose();
    exit(exitCode);
  }
}
