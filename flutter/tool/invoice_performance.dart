// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures
// Standalone Release/Profile probe, never the production entry point.
// The SAME probe runs against the pre-change and current source snapshots.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:space_flutter/main.dart' show SpaceApp;
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/core/invoice_pdf.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/invoice_details.dart';
import 'package:space_flutter/ui/invoice_merge.dart';
import 'package:space_flutter/ui/invoice_workspace.dart';

import 'performance_main.dart' as probe;

final frames = <FrameTiming>[];
late Directory out;
late SpaceStore store;
final result = <Map<String, Object?>>[];
final start = Stopwatch()..start();
final objc = DynamicLibrary.open('/usr/lib/libobjc.A.dylib');
final getClass = objc
    .lookupFunction<
      Pointer<Void> Function(Pointer<Utf8>),
      Pointer<Void> Function(Pointer<Utf8>)
    >('objc_getClass');
final getSel = objc
    .lookupFunction<
      Pointer<Void> Function(Pointer<Utf8>),
      Pointer<Void> Function(Pointer<Utf8>)
    >('sel_registerName');
final send = objc
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
    >('objc_msgSend');
final sendInt = objc
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)
    >('objc_msgSend');
Pointer<Void> sel(String name) {
  final p = name.toNativeUtf8();
  try {
    return getSel(p);
  } finally {
    malloc.free(p);
  }
}

bool Function()? foregroundOverride;
bool foreground() {
  final override = foregroundOverride;
  if (override != null) return override();
  if (!Platform.isMacOS) return probe.nativeForeground();
  final p = 'NSWorkspace'.toNativeUtf8();
  try {
    final workspace = send(getClass(p), sel('sharedWorkspace'));
    final app = send(workspace, sel('frontmostApplication'));
    return sendInt(app, sel('processIdentifier')) == pid;
  } finally {
    malloc.free(p);
  }
}

T? element<T>(T? Function(Element) read) {
  T? found;
  void visit(Element e) {
    found ??= read(e);
    if (found == null) e.visitChildren(visit);
  }

  (probe.root.currentContext! as Element).visitChildren(visit);
  return found;
}

dynamic get mergeState => element<dynamic>(
  (e) =>
      e is StatefulElement && e.widget is InvoiceMergeEditor ? e.state : null,
);
Future<void> waitUntil(bool Function() check, {int seconds = 60}) async {
  final w = Stopwatch()..start();
  while (!check()) {
    if (w.elapsed.inSeconds > seconds)
      throw StateError('Timed out waiting for UI');
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
  await SchedulerBinding.instance.endOfFrame;
}

Future<void> ready() async {
  await waitUntil(
    () =>
        mergeState != null &&
        mergeState.reading == false &&
        mergeState.preview != null,
  );
  if (mergeState.previewError != null || mergeState.layoutError != null)
    throw StateError('Preview failed');
}

Future<void> measure(
  String name,
  Future<void> Function() action, {
  Map<String, Object?> extra = const {},
}) async {
  final before = await probe.processSample();
  final t0 = Timeline.now;
  var peak = ProcessInfo.currentRss;
  var active = foreground();
  var samples = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
    samples++;
    peak = ProcessInfo.currentRss > peak ? ProcessInfo.currentRss : peak;
    active = active && foreground();
  });
  try {
    await action();
  } finally {
    timer.cancel();
  }
  final t1 = Timeline.now;
  final after = await probe.processSample();
  active = active && foreground();
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final batch = frames.where((f) {
    final t = f.timestampInMicroseconds(ui.FramePhase.buildStart);
    return t >= t0 && t < t1;
  }).toList();
  double q(Iterable<double> values, double p) {
    final a = values.toList()..sort();
    return a.isEmpty ? 0 : a[((a.length - 1) * p).ceil()];
  }

  final hz = ui.PlatformDispatcher.instance.views.first.display.refreshRate;
  final row = <String, Object?>{
    'scenario': name,
    'durationMs': (t1 - t0) / 1000,
    'cpuMeanPercent':
        (after['cpuSeconds']! - before['cpuSeconds']!) /
        ((t1 - t0) / 1e6) *
        100,
    'rssBeforeMiB': before['rssMiB'],
    'rssAfterMiB': after['rssMiB'],
    'rssPeakSampledMiB': peak / 1048576,
    'resourceSampleCount': samples,
    'foregroundThroughout': active,
    'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
    'frameCount': batch.length,
    'refreshRateHz': hz,
    'buildP95Ms': q(
      batch.map((f) => f.buildDuration.inMicroseconds / 1000),
      .95,
    ),
    'rasterP95Ms': q(
      batch.map((f) => f.rasterDuration.inMicroseconds / 1000),
      .95,
    ),
    'buildMaxMs': q(batch.map((f) => f.buildDuration.inMicroseconds / 1000), 1),
    'rasterMaxMs': q(
      batch.map((f) => f.rasterDuration.inMicroseconds / 1000),
      1,
    ),
    'stageOverBudgetFrames': batch
        .where(
          (f) =>
              f.buildDuration.inMicroseconds > 1e6 / hz ||
              f.rasterDuration.inMicroseconds > 1e6 / hz,
        )
        .length,
    'imageCacheBytes': PaintingBinding.instance.imageCache.currentSizeBytes,
    'imageCacheCount': PaintingBinding.instance.imageCache.currentSize,
    'liveImages': PaintingBinding.instance.imageCache.liveImageCount,
    ...extra,
  };
  result.add(row);
  File('${out.path}/$name.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(row));
  File('${out.path}/progress.json').writeAsStringSync(
    jsonEncode({'completed': name, 'scenarios': result.length, 'pid': pid}),
  );
  print(
    'PROBE $name ${row['durationMs']} ms RSS ${row['rssAfterMiB']} MiB active=$active',
  );
}

Future<void> main() async {
  start.reset();
  start.start();
  WidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['SPACE_FLUTTER_DATA_DIRECTORY'];
  final sourceRoot = Platform.environment['SPACE_INVOICE_PROBE_INPUT'];
  if (path == null || sourceRoot == null)
    throw StateError('Explicit isolated output and test input required');
  out = Directory(path);
  if (out.existsSync() && out.listSync().isNotEmpty)
    throw StateError('Output must be empty');
  out.createSync(recursive: true);
  probe.directory = out;
  final repository = SpaceRepository(out);
  store = SpaceStore(repository);
  await store.initialize();
  await store.commit(
    demoState(count: 9).copy(
      settings: {
        'appearance': 'light',
        'dark': 'false',
        'navCollapsed': 'false',
        'overviewCollapsed': 'true',
        'viewMode': 'list',
      },
    ),
    'Isolated invoice performance',
  );
  await store.reload();
  store.notice = null;
  runApp(
    KeyedSubtree(
      key: probe.root,
      child: SpaceApp(store: store),
    ),
  );
  SchedulerBinding.instance.addTimingsCallback(frames.addAll);
  await SchedulerBinding.instance.endOfFrame;
  final firstFrameMs = start.elapsedMicroseconds / 1000;
  File('${out.path}/ready.json').writeAsStringSync(
    jsonEncode({
      'pid': pid,
      'dartMainToFirstFrameMs': firstFrameMs,
      'wallTimeUs': DateTime.now().microsecondsSinceEpoch,
    }),
  );
  try {
    final deadline = Stopwatch()..start();
    while (!foreground()) {
      if (deadline.elapsed.inSeconds > 90)
        throw StateError('Real foreground focus required');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    await measure(
      'workspace-idle',
      () => Future<void>.delayed(const Duration(seconds: 10)),
    );
    final session = InvoiceSession(repository);
    final input = Directory('${out.path}/input')..createSync();
    final paths = <String>[];
    for (var i = 0; i < 100; i++) {
      final source = File('$sourceRoot/发票${i % 2 + 1}.pdf');
      final target =
          '${input.path}/invoice-${i.toString().padLeft(3, '0')}.pdf';
      source.copySync(target);
      paths.add(target);
    }
    await session.import(paths);
    await session.refresh();
    if (session.error != null || session.ledger!.entries.length != 100)
      throw StateError('Isolated import failed');
    final entries = session.ledger!.entries;
    final context = probe.workspaceContext();
    Future<void> detail() async {
      final modal = showInvoiceDetails(
        context,
        store,
        session,
        entries.first.id,
      );
      await waitUntil(
        () =>
            element<Image>(
              (e) =>
                  e.widget is Image && (e.widget as Image).image is MemoryImage
                  ? e.widget as Image
                  : null,
            ) !=
            null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      Navigator.of(context).pop();
      await modal;
      await waitUntil(
        () =>
            element<Widget>(
              (e) => e.widget.key == const ValueKey('invoice-details-sheet')
                  ? e.widget
                  : null,
            ) ==
            null,
      );
    }

    await measure('details-first-open-close', detail);
    await measure('details-repeat-10', () async {
      for (var i = 0; i < 10; i++) await detail();
    });
    final detailModal = showInvoiceDetails(
      context,
      store,
      session,
      entries.first.id,
    );
    await waitUntil(
      () =>
          element<Widget>(
            (e) => e.widget.key == const ValueKey('invoice-details-sheet')
                ? e.widget
                : null,
          ) !=
          null,
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    final scroll = element<ScrollPosition>(
      (e) =>
          e is StatefulElement &&
              e.state is ScrollableState &&
              (e.state as ScrollableState).position.axis == Axis.vertical &&
              (e.state as ScrollableState).position.maxScrollExtent > 0
          ? (e.state as ScrollableState).position
          : null,
    );
    await measure('details-scroll', () async {
      if (scroll == null) throw StateError('Missing detail scroll');
      for (var i = 0; i < 8; i++)
        await scroll.animateTo(
          i.isEven ? scroll.maxScrollExtent : 0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
    });
    Navigator.of(context).pop();
    await detailModal;
    Future<void>? modal;
    await measure('merge-first-preview-2', () async {
      modal = openInvoiceMerge(
        context,
        store,
        session.repo,
        entries: entries.take(2).toList(),
      );
      await ready();
    });
    await measure(
      'merge-idle',
      () => Future<void>.delayed(const Duration(seconds: 10)),
    );
    final latencies = <double>[];
    await measure('merge-layout-switch-12', () async {
      for (var i = 0; i < 12; i++) {
        final button = element<SpaceButton>(
          (e) =>
              e.widget is SpaceButton &&
                  e.widget.key == ValueKey('merge-layout-${i % 4 + 1}')
              ? e.widget as SpaceButton
              : null,
        )!;
        final w = Stopwatch()..start();
        button.onPressed!();
        await ready();
        latencies.add(w.elapsedMicroseconds / 1000);
      }
    });
    result.last['previewReadyMs'] = latencies;
    File('${out.path}/merge-layout-switch-12.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(result.last),
    );
    Navigator.of(context).pop();
    await modal;
    await waitUntil(
      () =>
          element<Widget>(
            (e) => e.widget.key == const ValueKey('invoice-details-sheet')
                ? e.widget
                : null,
          ) ==
          null,
    );
    final cold = <InvoiceSourcePage>[];
    await measure('inspect-100', () async {
      for (final file in paths)
        cold.addAll(await InvoicePdf.inspect(file, trim: true));
    }, extra: {'invoiceCount': 100});
    final layout = const InvoiceLayout(
      top: 10,
      left: 10,
      right: 10,
      bottom: 10,
      perPage: 2,
      gap: 10,
    );
    final sheets = layout.arrange(cold, []);
    await measure('export-100', () async {
      await InvoicePdf.save(session.repo, '${out.path}-batch.pdf', sheets);
    }, extra: {'invoiceCount': 100, 'outputPageCount': sheets.length});
    result.last['outputBytes'] = File('${out.path}-batch.pdf').lengthSync();
    await measure(
      'post-close-idle',
      () => Future<void>.delayed(const Duration(seconds: 15)),
    );
    session.dispose();
    File('${out.path}/report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'version': const String.fromEnvironment('SPACE_PROBE_VERSION'),
        'platform': Platform.operatingSystem,
        'buildMode': const bool.fromEnvironment('dart.vm.product')
            ? 'Release'
            : 'Profile',
        'dartVersion': Platform.version,
        'dartMainToFirstFrameMs': firstFrameMs,
        'data': '100 isolated copies of the two user-supplied test PDFs; 9 synthetic tasks',
        'formalDatabaseAccessed': false,
        'windowLogicalSize': {
          'width': probe.root.currentContext!.size!.width,
          'height': probe.root.currentContext!.size!.height,
        },
        'notes': [
          'CPU percentage is one-core equivalent from OS process CPU-time delta.',
          'RSS peak sampled at 100ms, not an exact allocation peak.',
          'Frame stage budget exceedances are not physical presentation/drop counts.',
          'Foreground verified against NSWorkspace frontmost PID at 100ms.',
        ],
        'results': result,
      }),
    );
  } catch (e, stack) {
    File('${out.path}/error.txt').writeAsStringSync('$e\n$stack');
    exitCode = 1;
  } finally {
    store.dispose();
    exit(exitCode);
  }
}
