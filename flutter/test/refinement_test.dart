import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/drive.dart';
import 'package:space_flutter/core/drive_query.dart';
import 'package:space_flutter/core/invoices.dart';
import 'package:space_flutter/core/invoice_recognition.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/host.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/file_drive.dart';
import 'package:space_flutter/ui/invoice_details.dart';
import 'package:space_flutter/ui/invoice_workspace.dart';
import 'package:space_flutter/ui/theme.dart';
import 'package:space_flutter/ui/settings_controls.dart';

class PreviewDrive extends DriveService {
  PreviewDrive(super.directory) {
    initialized = true;
    config = const DriveConfig(
      owner: 'example',
      repository: 'fixture',
      device: '测试',
    );
    token = 'test-only';
  }
  @override
  Future<List<DriveFile>> list() async => [
    DriveFile(
      '差旅.pdf',
      'a',
      100,
      created: DateTime(2026, 11, 12),
      device: '测试',
    ),
    DriveFile('资料/方案.docx', 'b', 100, created: DateTime(2026, 11, 11)),
  ];
}

class SwitchingApi extends DriveApi {
  final Completer<String> gate;
  final Completer<void> started;
  SwitchingApi(super.config, super.token, this.gate, this.started);
  @override
  Future<void> validate() async {}
  @override
  Future<String> head() async {
    if (config.repository == 'old') {
      if (!started.isCompleted) started.complete();
      return gate.future;
    }
    return 'same-head';
  }

  @override
  Future<Map<String, dynamic>> indexAt(String ref) async => {
    'f': {
      'path': '${config.repository}.txt',
      'blob': 'fake',
      'size': 1,
      'created': '2026-11-12T00:00:00Z',
      'device': 'fixture',
      'sha256': 'fake',
      'stored': 'fake',
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late SpaceStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('space-refinement-');
    store = SpaceStore(SpaceRepository(dir));
    await store.initialize();
  });
  tearDown(() async {
    store.dispose();
    await dir.delete(recursive: true);
  });
  Future<InvoiceSession> sample({int count = 1}) async {
    final s = InvoiceSession(store.repository);
    for (var i = 0; i < count; i++) {
      final file = File('${dir.path}/sample$i.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );
      await s.repo.importFiles([file.path]);
    }
    await s.refresh();
    addTearDown(s.dispose);
    return s;
  }

  test('十类文件多选取并集、单日精确匹配且不越目录', () {
    final f = DriveFileFilter();
    addTearDown(f.dispose);
    final files = [
      DriveFile('a.DOCX', '', 1, created: DateTime(2026, 11, 12)),
      DriveFile('b.xlsm', '', 1, created: DateTime(2026, 11, 11)),
      DriveFile('c.pdf', '', 1, created: DateTime(2026, 11, 12)),
      DriveFile('子目录/a.doc', '', 1, created: DateTime(2026, 11, 12)),
    ];
    expect(driveDirectoryFiles(files, '', f).length, 4);
    f.types.addAll(['word', 'pdf']);
    expect(driveDirectoryFiles(files, '', f).map((e) => e.name), [
      'a.DOCX',
      'c.pdf',
    ]);
    f.date = '2026-11-11';
    expect(driveDirectoryFiles(files, '', f), isEmpty);
    f.date = '2026-11-12';
    f.query = 'a';
    expect(driveDirectoryFiles(files, '', f).single.name, 'a.DOCX');
    expect(driveDirectoryFiles(files, '子目录/', f).single.name, 'a.doc');
    final appFilter = DriveFileFilter()..types.add('app');
    addTearDown(appFilter.dispose);
    expect(
      driveDirectoryFiles(
        [const DriveFile('工具.app/Contents/info.plist', '', 1)],
        '',
        appFilter,
      ).single.path,
      '工具.app/',
    );
    for (final item in {
      '方案.pptm': 'ppt',
      '资料.tar.gz': 'archive',
      '视频.MP4': 'video',
      '照片.heic': 'image',
      '笔记.md': 'text',
      '安装.dmg': 'app',
      '无后缀': 'other',
      'unknown.xyz': 'other',
    }.entries) {
      expect(driveFileType(item.key), item.value);
    }
  });
  test('仓库链接与短地址一致，拒绝凭据和其他域名', () {
    expect(
      DriveConfig.fromAddress(
        'https://github.com/example/fixture.git',
        branch: 'space-drive',
        device: '测试',
      ).repository,
      'fixture',
    );
    expect(
      DriveConfig.fromAddress(
        'example/fixture',
        branch: 'space-drive',
        device: '测试',
      ).owner,
      'example',
    );
    expect(
      () => DriveConfig.fromAddress(
        'https://other.com/example/fixture',
        branch: 'space-drive',
        device: '测试',
      ),
      throwsStateError,
    );
    expect(
      () => DriveConfig.fromAddress(
        'https://token@github.com/example/fixture',
        branch: 'space-drive',
        device: '测试',
      ),
      throwsStateError,
    );
  });
  test('主动识别覆盖票面并落库，不推导或修改个人报销字段', () async {
    final s = await sample(), id = s.ledger!.entries.single.id;
    await s.repo.save(
      id,
      const InvoiceInfo(
        seller: '原销售方',
        purpose: '个人备注',
        spent: '',
        month: '',
        reimbursed: true,
      ),
    );
    s.recognizeFile = (f, {required preferOcr}) async =>
        const InvoiceRecognition({
          'seller': '新销售方',
          'number': '00001234',
          'issued': '2026-11-12',
          'cents': 26800,
          'purpose': '禁止写入',
        }, '');
    await s.recognizeEntry(id);
    final info = (await s.repo.load()).entries.single.info;
    expect(info.seller, '新销售方');
    expect(info.number, '00001234');
    expect(info.cents, 26800);
    expect(info.purpose, '个人备注');
    expect(info.spent, isEmpty);
    expect(info.month, isEmpty);
    expect(info.reimbursed, isTrue);
  });
  test('批量识别串行执行，单张失败不回滚；批量删除仅处理指定票据与附件', () async {
    final s = await sample(count: 3),
        ids = s.ledger!.entries.map((e) => e.id).toList();
    var active = 0, maxActive = 0, index = 0;
    s.recognizeFile = (f, {required preferOcr}) async {
      active++;
      if (active > maxActive) maxActive = active;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      active--;
      if (index++ == 1) throw StateError('模拟单张失败');
      return const InvoiceRecognition({'number': '00009999'}, '');
    };
    await s.recognizeSelected(ids.take(2).toList());
    expect(maxActive, 1);
    expect(s.recognitionFailures.length, 1);
    expect(s.batchNotice, contains('1 张已保存'));
    expect(s.batchError, contains('1 张未完成'));
    expect(
      s.ledger!.entries.where((e) => e.info.number == '00009999').length,
      1,
    );
    final retry = s.recognitionFailures.keys.single;
    await s.recognizeEntry(retry);
    expect(s.recognitionFailures, isEmpty);
    final original = s.ledger!.entries
        .firstWhere((e) => e.id == ids.first)
        .original
        .path;
    await s.deleteSelected([ids.first]);
    expect(s.ledger!.entries.length, 2);
    expect(File(original).existsSync(), isFalse);
    expect(s.ledger!.entries.any((e) => e.id == ids.last), isTrue);
  });
  test('后台识别不占用前台busy，保留期间保存的手工字段和用户新选择', () async {
    final s = await sample(count: 2),
        id = s.ledger!.entries.first.id,
        other = s.ledger!.entries.last.id;
    await s.repo.save(id, const InvoiceInfo(seller: '原销售方'));
    await s.refresh();
    final started = Completer<void>(), gate = Completer<void>();
    s.recognizeFile = (f, {required preferOcr}) async {
      started.complete();
      await gate.future;
      return const InvoiceRecognition({
        'seller': 'OCR销售方',
        'number': '00008888',
      }, '');
    };
    s.selected.add(id);
    final batch = s.recognizeSelected([id]);
    await started.future;
    expect(s.batchRecognizing, isTrue);
    expect(s.busy, isFalse);
    final before = s.ledger!.entries.firstWhere((e) => e.id == id).info;
    await s.run(() async {
      await s.repo.save(
        id,
        const InvoiceInfo(seller: '用户刚保存的销售方', purpose: '前台备注'),
        baseline: before,
      );
      return '前台保存完成';
    });
    s.update(() {
      s.query = '用户新查询';
      s.selected
        ..clear()
        ..add(other);
    });
    expect(s.notice, '前台保存完成');
    expect(s.batchRecognizing, isTrue);
    gate.complete();
    await batch;
    final info = (await s.repo.load()).entries
        .firstWhere((e) => e.id == id)
        .info;
    expect(info.seller, '用户刚保存的销售方');
    expect(info.number, '00008888');
    expect(info.purpose, '前台备注');
    expect(s.query, '用户新查询');
    expect(s.selected, {other});
    expect(s.batchNotice, contains('1 张已保存'));
    expect(s.busy, isFalse);
  });
  test('后台识别期间删除无需等待，当前项和排队项被跳过且不会恢复', () async {
    final s = await sample(count: 3),
        ids = s.ledger!.entries.map((e) => e.id).toList();
    final gate = Completer<void>(), started = Completer<void>();
    var calls = 0;
    s.recognizeFile = (f, {required preferOcr}) async {
      calls++;
      started.complete();
      await gate.future;
      return const InvoiceRecognition({'number': '00007777'}, '');
    };
    final batch = s.recognizeSelected(ids.take(2).toList());
    await started.future;
    await s
        .deleteSelected(ids.take(2).toList())
        .timeout(const Duration(seconds: 3));
    expect(gate.isCompleted, isFalse);
    expect(s.batchRecognizing, isTrue);
    expect(s.ledger!.entries.single.id, ids.last);
    gate.complete();
    await batch;
    expect(calls, 1);
    expect((await s.repo.load()).entries.single.id, ids.last);
    expect(s.batchNotice, contains('2 张已跳过'));
    expect(s.batchError, isNull);
    expect(s.recognitionFailures, isEmpty);
  });
  testWidgets('标题栏纯图标支持悬停和点击提示，点击操作即时执行', (t) async {
    var count = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: spaceTheme(false),
        home: Scaffold(
          body: Center(
            child: IconButtonS.toolbar(
              'scan',
              '后台识别提示',
              onPressed: () => count++,
            ),
          ),
        ),
      ),
    );
    expect(find.text('后台识别提示'), findsNothing);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(t.getCenter(find.byType(IconButtonS)));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('后台识别提示'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await t.pumpAndSettle();
    await t.tap(find.byType(IconButtonS));
    expect(count, 1);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('后台识别提示'), findsOneWidget);
    Tooltip.dismissAllToolTips();
    await mouse.removePointer();
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('后台识别时台账导入导出与筛选可用，用户可继续查询', (t) async {
    final s = (await t.runAsync(() => sample(count: 2)))!;
    store.openArea(SpaceArea.invoices);
    final id = s.ledger!.entries.first.id;
    final gate = Completer<void>(), started = Completer<void>();
    s.recognizeFile = (f, {required preferOcr}) async {
      started.complete();
      await gate.future;
      return const InvoiceRecognition({'number': '00006666'}, '');
    };
    s.selected.add(id);
    await t.pumpWidget(
      MaterialApp(
        theme: spaceTheme(false),
        home: Scaffold(
          body: InvoiceWorkspace(
            store: store,
            session: s,
            showTools: false,
            filterAnchor: GlobalKey(),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final scan = find.byWidgetPredicate(
      (w) => w is IconButtonS && w.label == '识别所选发票',
    );
    await t.tap(scan);
    await t.pump();
    for (var i = 0; i < 100 && !started.isCompleted; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump();
    }
    expect(started.isCompleted, isTrue);
    await t.pump(const Duration(milliseconds: 300));
    expect(s.busy, isFalse);
    expect(find.textContaining('后台识别 0 / 1'), findsOneWidget);
    for (final label in ['导入发票', '按字段导出', '批量删除发票']) {
      final button = find.byWidgetPredicate(
        (w) => w is IconButtonS && w.label == label,
      );
      expect(t.widget<IconButtonS>(button).onPressed, isNotNull);
    }
    final filter = find.byWidgetPredicate(
      (w) => w is IconButtonS && w.label == '筛选发票（⌘F）',
    );
    await t.tap(filter);
    await t.pumpAndSettle();
    expect(find.text('筛选发票'), findsWidgets);
    await t.enterText(find.byType(TextField), '用户继续查询');
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(s.query, '用户继续查询');
    gate.complete();
    for (var i = 0; i < 100 && s.batchRecognizing; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump();
    }
    await t.pumpAndSettle();
    expect(s.batchRecognizing, isFalse);
    expect(s.query, '用户继续查询');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  test('未配置网盘不读钥匙串，并发初始化只执行一次凭据读取', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var reads = 0;
    final requested = Completer<void>(), gate = Completer<String>();
    messenger.setMockMethodCallHandler(DesktopHost.channel, (call) async {
      if (call.method == 'readSecret') {
        reads++;
        if (!requested.isCompleted) requested.complete();
        return gate.future;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(DesktopHost.channel, null),
    );
    final empty = DriveService(dir);
    addTearDown(empty.dispose);
    await empty.initialize();
    expect(reads, 0);
    expect(empty.initialized, isTrue);
    empty.config = const DriveConfig(
      owner: 'fixture',
      repository: 'configured',
      device: '测试',
    );
    await empty.persist();
    final reopened = DriveService(dir);
    addTearDown(reopened.dispose);
    final first = reopened.initialize(), second = reopened.initialize();
    expect(identical(first, second), isTrue);
    await requested.future;
    expect(reopened.initialized, isFalse);
    gate.complete('test-only');
    await Future.wait([first, second]);
    expect(reads, 1);
    expect(reopened.token, 'test-only');
    expect(reopened.initialized, isTrue);
  });

  test('切换仓库时旧列表请求不能回写缓存或下载目标', () async {
    final gate = Completer<String>(), started = Completer<void>();
    final service =
        DriveService(
            dir,
            apiFactory: (c, t) => SwitchingApi(c, t, gate, started),
          )
          ..initialized = true
          ..config = const DriveConfig(
            owner: 'fixture',
            repository: 'old',
            device: '测试',
          )
          ..token = 'test-only';
    addTearDown(service.dispose);
    final binding =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    binding.setMockMethodCallHandler(DesktopHost.channel, (call) async => null);
    addTearDown(
      () => binding.setMockMethodCallHandler(DesktopHost.channel, null),
    );
    final old = service.list();
    final rejected = expectLater(old, throwsStateError);
    await started.future;
    await service.connect(
      const DriveConfig(owner: 'fixture', repository: 'new', device: '测试'),
      'test-only',
    );
    gate.complete('same-head');
    await rejected;
    expect((await service.list()).single.name, 'new.txt');
  });

  testWidgets('单日历与多选下拉弹层等于条件字段宽度，键盘可多选', (t) async {
    final values = <String>{};
    await t.pumpWidget(
      MaterialApp(
        theme: spaceTheme(false),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DateField(
                    value: '2026-11-12',
                    label: '创建日期',
                    matchFieldWidth: true,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 16),
                  SpaceMultiSelect(
                    values: values,
                    options: driveFileTypes,
                    label: '文件类型',
                    matchFieldWidth: true,
                    onChanged: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final field = find.byType(DateField);
    await t.tap(field);
    await t.pumpAndSettle();
    expect(
      t.getSize(find.byType(DatePopover)).width,
      closeTo(t.getSize(field).width, .1),
    );
    expect(find.text('明天'), findsOneWidget);
    await t.tap(find.text('清除'));
    await t.pumpAndSettle();
    final multi = find.byType(SpaceMultiSelect);
    await t.tap(multi);
    await t.pumpAndSettle();
    expect(
      t.getSize(find.byType(PopupSurface)).width,
      closeTo(t.getSize(multi).width, .1),
    );
    await t.tap(find.text('Word'));
    await t.pumpAndSettle();
    await t.tap(find.text('PDF'));
    await t.pumpAndSettle();
    expect(values, {'word', 'pdf'});
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('文件管理双标签与上传状态同排，设置返回保留标签和查询', (t) async {
    t.view.physicalSize = const Size(1100, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final service = PreviewDrive(dir);
    await t.pumpWidget(
      MaterialApp(
        theme: spaceTheme(false),
        home: Scaffold(
          body: DrivePage(
            store: store,
            service: service,
            titleBuilder: (actions) => SpaceTitleBar(
              children: [const Text('文件管理'), const Spacer(), ...actions],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final root = find.text('根目录');
    final tabs = find.text('上传记录');
    expect((t.getCenter(root).dy - t.getCenter(tabs).dy).abs(), lessThan(3));
    await t.tap(tabs);
    await t.pumpAndSettle();
    expect(
      (t.getCenter(find.text('全部')).dy - t.getCenter(find.text('上传记录')).dy)
          .abs(),
      lessThan(3),
    );
    await t.tap(find.text('文件管理').last);
    await t.pumpAndSettle();
    final filter = find.byWidgetPredicate(
      (w) => w is IconButtonS && w.label == '筛选文件',
    );
    await t.tap(filter);
    await t.pumpAndSettle();
    expect(find.text('筛选文件'), findsWidgets);
    await t.enterText(find.byType(TextField), '差旅');
    await t.pumpAndSettle();
    expect(find.text('1 个匹配项'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await t.tap(filter);
    await t.pumpAndSettle();
    expect(find.text('差旅'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    driveFor(store).initialized = true;
    await t.tap(
      find.byWidgetPredicate((w) => w is IconButtonS && w.label == '网盘设置'),
    );
    await t.pumpAndSettle();
    expect(
      t
          .widget<SettingsAction>(
            find.byKey(const ValueKey('settings-category-6')),
          )
          .selected,
      isTrue,
    );
    expect(
      t.getTopLeft(find.byKey(const ValueKey('settings-category-7'))).dy,
      greaterThan(
        t.getTopLeft(find.byKey(const ValueKey('settings-category-6'))).dy,
      ),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await t.tap(filter);
    await t.pumpAndSettle();
    expect(find.text('差旅'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    service.dispose();
    expect(t.takeException(), isNull);
  });
  testWidgets('文件页跟随系统浅深色，窄窗口标签、状态与弹层可达', (t) async {
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    final service = PreviewDrive(dir);
    addTearDown(service.dispose);
    for (final dark in [false, true]) {
      for (final width in [620.0, 1100.0]) {
        t.view.physicalSize = Size(width, 720);
        t.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        await t.pumpWidget(
          MaterialApp(
            theme: spaceTheme(false),
            darkTheme: spaceTheme(true),
            themeMode: ThemeMode.system,
            home: Scaffold(
              body: DrivePage(
                key: UniqueKey(),
                store: store,
                service: service,
                titleBuilder: (a) => SpaceTitleBar(
                  children: [const Text('文件管理'), const Spacer(), ...a],
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(Palette.of(t.element(find.byType(DrivePage))).dark, dark);
        final tab = find.text('上传记录');
        expect(tab.hitTestable(), findsOneWidget);
        await t.tap(tab);
        await t.pumpAndSettle();
        expect(find.text('已完成').hitTestable(), findsOneWidget);
        await t.tap(find.text('文件管理').last);
        await t.pumpAndSettle();
        await t.tap(
          find.byWidgetPredicate((w) => w is IconButtonS && w.label == '筛选文件'),
        );
        await t.pumpAndSettle();
        expect(find.text('文件类型').hitTestable(), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    }
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('详情识别自动保存且无提示条，未保存备注保持独立状态', (t) async {
    final s = await t.runAsync(() => sample());
    final session = s!;
    final id = session.ledger!.entries.single.id;
    session.recognizeFile = (f, {required preferOcr}) async {
      await session.repo.applyRecognition(id, {'issued': '2026-11-12'}, '');
      return const InvoiceRecognition({
        'title': '电子发票（普通发票）',
        'number': '00001234',
        'cents': 26800,
      }, '');
    };
    await t.pumpWidget(
      MaterialApp(
        theme: spaceTheme(false),
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showInvoiceDetails(c, store, session, id),
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('打开详情'));
    await t.pumpAndSettle();
    final note = find.descendant(
      of: find.byKey(const ValueKey('invoice-field-备注')),
      matching: find.byType(TextField),
    );
    await t.enterText(note, '未保存的个人备注');
    final scan = find.byWidgetPredicate(
      (w) => w is IconButtonS && w.icon == 'scan',
    );
    await t.runAsync(() async {
      await t.tap(scan);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await t.pumpAndSettle();
    final saved = await t.runAsync(() => session.repo.load());
    expect(saved!.entries.single.info.number, '00001234');
    expect(saved.entries.single.info.purpose, isEmpty);
    expect(find.text('未保存的个人备注'), findsOneWidget);
    expect(find.textContaining('票面信息已自动保存'), findsNothing);
    await t.tap(
      find.byKey(const ValueKey('invoice-details-dismiss-area')),
      warnIfMissed: false,
    );
    await t.pumpAndSettle();
    expect(find.text('保存修改？'), findsOneWidget);
    await t.tap(find.text('不保存'));
    await t.pumpAndSettle();
    await t.tap(find.text('打开详情'));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(scan);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('invoice-details-dismiss-area')));
    await t.pumpAndSettle();
    expect(find.text('保存修改？'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
