// Dedicated Profile/Release entry point, never packaged as the application.
// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:space_flutter/main.dart' show SpaceApp;
import 'package:space_flutter/core/drive.dart';
import 'package:space_flutter/core/invoice_pdf.dart';
import 'package:space_flutter/core/invoices.dart';
import 'package:space_flutter/core/ppocr.dart';
import 'package:space_flutter/core/releases.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/host.dart';
import 'package:space_flutter/ui/dialogs.dart' show showSettings;
import 'package:space_flutter/ui/file_drive.dart';
import 'package:space_flutter/ui/invoice_batch_update.dart';
import 'package:space_flutter/ui/invoice_workspace.dart';
import 'package:space_flutter/ui/workspace.dart';

import 'invoice_performance.dart' as perf;
import 'performance_main.dart' as base;

class ProbeRemote {
  final index = <String, dynamic>{};
  final blobs = <String, Uint8List>{};
  int revision = 0;
}

class ProbeApi extends DriveApi {
  final ProbeRemote remote;
  ProbeApi(super.config, super.token, this.remote);
  @override
  Future<String> head() async => 'r${remote.revision}';
  @override
  Future<Map<String, dynamic>> indexAt(String ref) async =>
      Map.of(remote.index);
  @override
  Future<String> blob(String content, {void Function(double)? progress}) async {
    final bytes = base64Decode(content),
        id = sha256.convert(base64Decode(content)).toString();
    remote.blobs[id] = bytes;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    progress?.call(1);
    return id;
  }

  @override
  Future<void> commit(
    List<Map<String, Object?>> changes, {
    List<Map<String, Object?>> records = const [],
    String? remove,
  }) async {
    for (final r in records) {
      remote.index[r['id'] as String] = r;
    }
    remote.revision++;
  }
}

dynamic get workspace => perf.element<dynamic>(
  (e) => e is StatefulElement && e.widget is Workspace ? e.state : null,
);
dynamic get drivePage => perf.element<dynamic>(
  (e) => e is StatefulElement && e.widget is DrivePage ? e.state : null,
);
Future<void> settle([int ms = 80]) async {
  WidgetsBinding.instance.scheduleFrame();
  await SchedulerBinding.instance.endOfFrame;
  await Future<void>.delayed(Duration(milliseconds: ms));
}

Future<void> waitFor(bool Function() check) async {
  final time = Stopwatch()..start();
  while (!check()) {
    if (time.elapsed.inSeconds > 120) throw StateError('Probe timeout');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  await settle();
}

Future<(String, String)> fixture(Directory input) async {
  final fontPath = Platform.environment['SPACE_PROBE_FONT'];
  if (fontPath == null) throw StateError('Fixture font required');
  final font = pw.Font.ttf(
    ByteData.sublistView(File(fontPath).readAsBytesSync()),
  );
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(600, 420),
      margin: const pw.EdgeInsets.all(24),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('电子发票（普通发票）', style: pw.TextStyle(font: font, fontSize: 20)),
          pw.SizedBox(height: 16),
          for (final line in [
            '发票号码：26327000000000000123',
            '开票日期：2026年11月13日',
            '购买方名称：测试科技有限公司',
            '销售方名称：示例汽车服务有限公司',
            '项目名称：运输服务  数量：1  单价：100.00',
            '未税金额：100.00  税额：6.00',
            '价税合计（小写）：¥106.00',
          ])
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 14),
              child: pw.Text(
                line,
                style: pw.TextStyle(font: font, fontSize: 13),
              ),
            ),
        ],
      ),
    ),
  );
  final pdf = File('${input.path}/synthetic.pdf');
  await pdf.writeAsBytes(await document.save());
  final png = File('${input.path}/synthetic.png');
  await png.writeAsBytes((await InvoicePdf.preview(pdf.path, 1)).bytes);
  return (pdf.path, png.path);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isMacOS) throw UnsupportedError('This probe targets macOS');
  final path = Platform.environment['SPACE_FLUTTER_DATA_DIRECTORY'];
  if (path == null || !path.contains('space233'))
    throw StateError('Explicit isolated path required');
  final out = Directory(path);
  if (out.existsSync() && out.listSync().isNotEmpty)
    throw StateError('Output must be empty');
  out.createSync(recursive: true);
  perf.out = out;
  base.directory = out;
  final store = SpaceStore(SpaceRepository(out));
  await store.initialize();
  perf.store = store;
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
    'Synthetic fixture',
  );
  await store.reload();
  store.notice = null;
  final input = Directory('${out.path}/input')..createSync();
  final source = await fixture(input);
  final setup = InvoiceRepository(store.repository), paths = <String>[];
  for (var i = 0; i < 1000; i++) {
    final original = i < 8 ? source.$2 : source.$1;
    final file = File('${input.path}/ticket-$i.${i < 8 ? 'png' : 'pdf'}');
    await File(original).copy(file.path);
    paths.add(file.path);
  }
  await setup.importFiles(paths);
  final db = store.repository.openInvoiceDatabase();
  try {
    db.execute('UPDATE invoices SET month=?,purpose=?,recognition=?', [
      '2026-10',
      '原备注',
      '{"status":"fixture"}',
    ]);
  } finally {
    db.close();
  }
  runApp(
    KeyedSubtree(
      key: base.root,
      child: SpaceApp(store: store),
    ),
  );
  SchedulerBinding.instance.addTimingsCallback(perf.frames.addAll);
  var nativeFocused = false, readingFocus = false;
  var lastFocus = DateTime.fromMillisecondsSinceEpoch(0);
  final focusSamples = <Map<String, Object?>>[];
  Future<void> readFocus() async {
    if (readingFocus) return;
    readingFocus = true;
    try {
      final info = await DesktopHost.channel.invokeMapMethod<String, dynamic>(
        'diagnostics',
      );
      lastFocus = DateTime.now();
      nativeFocused =
          info?['appActive'] == true && info?['frontmostPid'] == pid;
      focusSamples.add({
        'timeUs': lastFocus.microsecondsSinceEpoch,
        'active': nativeFocused,
        'key': info?['windowKey'],
      });
    } finally {
      readingFocus = false;
    }
  }

  await readFocus();
  final focusTimer = Timer.periodic(
    const Duration(milliseconds: 100),
    (_) => unawaited(readFocus()),
  );
  perf.foregroundOverride = () =>
      nativeFocused &&
      DateTime.now().difference(lastFocus).inMilliseconds < 2000;
  await settle();
  File('${out.path}/ready.json').writeAsStringSync(
    jsonEncode({'pid': pid, 'buildMode': kProfileMode ? 'Profile' : 'Release'}),
  );
  try {
    final deadline = Stopwatch()..start();
    while (!perf.foreground() || !File('${out.path}/start').existsSync()) {
      if (deadline.elapsed.inMinutes >= 10)
        throw StateError('Foreground required');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await settle(3000);
    await perf.measure(
      'workspace-idle-10s',
      () => Future<void>.delayed(const Duration(seconds: 10)),
      extra: {'tasks': 9},
    );
    store.openArea(SpaceArea.invoices);
    final session = workspace.invoices as InvoiceSession;
    await waitFor(
      () => session.ledger?.entries.length == 1000 && !session.busy,
    );
    final entries = session.ledger!.entries,
        ids = entries.map((e) => e.id).toList();
    final context = base.workspaceContext();
    await perf.measure('invoice-list-scroll-1000', () async {
      final scroll = perf.element<ScrollController>(
        (e) =>
            e.widget is ListView &&
                (e.widget as ListView).scrollDirection == Axis.vertical
            ? (e.widget as ListView).controller
            : null,
      )!;
      for (var i = 0; i < 10; i++) {
        await scroll.animateTo(
          i.isEven ? scroll.position.maxScrollExtent : 0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.linear,
        );
      }
    }, extra: {'invoices': 1000});
    final updates = <double>[];
    await perf.measure('batch-update-1000-x10', () async {
      for (var i = 0; i < 10; i++) {
        final t = Stopwatch()..start();
        if (!await session.updateReimbursement(
          ids,
          InvoiceReimbursementPatch(
            month: i.isEven ? '2026-11' : '2026-12',
            project: session.projects.keys.first,
            purpose: '批量备注$i',
          ),
        ))
          throw StateError('Batch update');
        updates.add(t.elapsedMicroseconds / 1000);
        await settle();
      }
    }, extra: {'invoicesPerUpdate': 1000, 'updates': 10});
    if (session.ledger!.entries.any(
      (e) => e.info.month != '2026-12' || e.info.purpose != '批量备注9',
    ))
      throw StateError('Batch persistence');
    await perf.measure('batch-dialog-open-close-8', () async {
      for (var i = 0; i < 8; i++) {
        final dialog = showInvoiceBatchUpdate(context, store, session, ids);
        await settle(250);
        Navigator.of(context).pop();
        await dialog;
        await settle(220);
      }
    }, extra: {'selected': 1000});
    final pdfEntry = entries.firstWhere((e) => e.original.isPdf),
        imageEntries = entries.where((e) => !e.original.isPdf).toList();
    await perf.measure('pdf-text-recognize-save', () async {
      await session.recognizeEntry(pdfEntry.id);
      await session.refresh();
      session.update(() {});
    });
    await perf.measure('ocr-cold-recognize-save', () async {
      await session.recognizeEntry(imageEntries.first.id);
      await session.refresh();
      session.update(() {});
    });
    await perf.measure('ocr-medium-first-use', () async {
      final r = await LocalPpocr.recognize(source.$2, enhanced: true);
      if (!r.text.contains('106.00')) throw StateError('Medium OCR');
    });
    final actions = <double>[];
    await perf.measure('ocr-background-8-with-frontend', () async {
      final batch = session.recognizeSelected(
        imageEntries.map((e) => e.id).toList(),
      );
      for (var i = 0; i < 30; i++) {
        if (session.busy) throw StateError('Global busy occupied');
        final t = Stopwatch()..start();
        session.update(() {
          session.query = i.isEven ? 'ticket-1' : '';
          session.selected.add(entries.last.id);
        });
        store.openArea(i % 3 == 0 ? SpaceArea.tools : SpaceArea.invoices);
        WidgetsBinding.instance.scheduleFrame();
        await SchedulerBinding.instance.endOfFrame;
        actions.add(t.elapsedMicroseconds / 1000);
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      await batch;
      if (session.batchError != null || session.batchProcessed != 8)
        throw StateError('OCR batch failed');
    }, extra: {'images': 8, 'frontendActions': 30});
    // 用户已批量设置的报销月份必须保留；票号应一致；小模型 OCR 对合成图的价税合计
    // 可能取不到，允许为空并单独统计，但绝不能写入错误金额。
    var amountRecognized = 0;
    for (final e in (await session.repo.load()).entries.where(
      (e) => imageEntries.any((i) => i.id == e.id),
    )) {
      if (e.info.number != '26327000000000000123')
        throw StateError('Recognition number differs: ${e.info.number}');
      if (e.info.month != '2026-12')
        throw StateError('Recognition overwrote month: ${e.info.month}');
      if (e.info.cents == 10600) amountRecognized++;
      if (e.info.cents != null && e.info.cents != 10600)
        throw StateError('Recognition wrote wrong amount: ${e.info.cents}');
    }
    await perf.measure(
      'post-ocr-idle-release-30s',
      () => Future<void>.delayed(const Duration(seconds: 30)),
    );
    final remote = ProbeRemote();
    for (var i = 0; i < 1000; i++) {
      final id = 'fixture-$i';
      remote.index[id] = {
        'id': id,
        'path': '资料$i.${['pdf', 'docx', 'xlsx', 'jpg'][i % 4]}',
        'blob': id,
        'size': 1024,
        'created': '2026-11-13T00:00:00Z',
        'device': 'Synthetic',
        'sha256': '',
        'stored': 'files/$id',
      };
    }
    final drive =
        DriveService(
            Directory('${out.path}/probe-drive'),
            apiFactory: (c, t) => ProbeApi(c, t, remote),
          )
          ..initialized = true
          ..config = const DriveConfig(
            owner: 'fixture',
            repository: 'fixture',
            device: 'Synthetic',
          )
          ..token = 'synthetic-no-network';
    final route = Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: DrivePage(
            store: store,
            service: drive,
            titleBuilder: (actions) => SizedBox(
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ),
          ),
        ),
      ),
    );
    await waitFor(
      () =>
          drivePage != null &&
          !drivePage.loading &&
          drivePage.files.length == 1000,
    );
    await perf.measure(
      'drive-filter-tabs-scroll-1000',
      () async {
        final page = drivePage;
        for (var i = 0; i < 15; i++) {
          page.fileFilter.query = i.isEven ? '资料1' : '';
          page.fileFilter.changed();
          await settle(60);
          final scroll = page.cloudScroll as ScrollController;
          if (scroll.hasClients)
            await scroll.animateTo(
              i.isEven ? scroll.position.maxScrollExtent : 0,
              duration: const Duration(milliseconds: 100),
              curve: Curves.linear,
            );
          page.setState(() {
            page.cloud = false;
          });
          await settle(60);
          page.setState(() {
            page.cloud = true;
          });
          await settle(60);
        }
      },
      extra: {
        'files': 1000,
        'transport': 'in-memory simulated Git API; not real network throughput',
      },
    );
    drivePage.setState(() {
      drivePage.cloud = false;
    });
    await settle(200);
    await perf.measure(
      'drive-upload-queue-40',
      () async {
        final paths = <String>[];
        for (var i = 0; i < 40; i++) {
          final f = File('${input.path}/upload-$i.txt');
          await f.writeAsString('synthetic\n' * 8192);
          paths.add(f.path);
        }
        await drive.add(paths);
        await waitFor(() => !drive.active);
        if (drive.tasks.any((t) => t.status != UploadStatus.complete))
          throw StateError('Upload queue');
      },
      extra: {
        'files': 40,
        'bytesEach': 81920,
        'transport': 'simulated API 20ms/blob; real scan, digest, encoding and queue persistence',
      },
    );
    Navigator.of(context).pop();
    await route;
    await settle(250);
    drive.dispose();
    final checker = ReleaseChecker(
      infoLoader: () async => {'version': '2.3.3', 'build': '20'},
      releaseLoader: () async => [
        {
          'draft': false,
          'prerelease': false,
          'tag_name': 'v2.3.3',
          'html_url': '$projectUrl/releases/tag/v2.3.3',
          'assets': [],
        },
      ],
    );
    await perf.measure('drive-settings-direct-5', () async {
      for (var i = 0; i < 5; i++) {
        final modal = showSettings(
          context,
          store,
          initialCategory: 'drive',
          updates: checker,
        );
        await settle(260);
        Navigator.of(context).pop();
        await modal;
        await settle(220);
      }
    });
    checker.dispose();
    await LocalPpocr.dispose();
    updates.sort();
    actions.sort();
    final size = MediaQuery.sizeOf(context);
    final result = {
      'version': '2.3.3+20',
      'applicationBaseline': '9cb7f938 plus the recorded batch-update diff',
      'buildMode': kProfileMode ? 'Profile' : 'Release',
      'platform': Platform.operatingSystem,
      'dartVersion': Platform.version,
      'pid': pid,
      'windowLogicalSize': {'width': size.width, 'height': size.height},
      'formalDatabaseAccessed': false,
      'ocrAmountCoverage': {'images': 8, 'recognized': amountRecognized},
      'batchUpdateMs': {
        'p95': updates[(updates.length * .95).ceil() - 1],
        'max': updates.last,
      },
      'frontendActionToFrameMs': {
        'p95': actions[(actions.length * .95).ceil() - 1],
        'max': actions.last,
      },
      'foregroundValid': perf.result.every(
        (r) => r['foregroundThroughout'] == true,
      ),
      'results': perf.result,
    };
    File('${out.path}/result.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    focusTimer.cancel();
    File('${out.path}/focus-samples.json')
        .writeAsStringSync(jsonEncode(focusSamples));
    print('INVOICE_REFINEMENT_PROBE_DONE');
  } catch (e, st) {
    focusTimer.cancel();
    File('${out.path}/error.txt').writeAsStringSync('$e\n$st');
    print('INVOICE_REFINEMENT_PROBE_ERROR $e');
  }
}
