import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/core/sync.dart';
import 'package:space_flutter/core/sync_service.dart';
import 'package:space_flutter/host.dart';
import 'package:space_flutter/main.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/dialogs.dart';
import 'package:space_flutter/ui/theme.dart';
import 'package:space_flutter/ui/workspace.dart';

class MemoryGitHub extends GitHubAPI {
  Uint8List? cloud;
  bool race = false;
  int uploads = 0;
  MemoryGitHub() : super(const GitHubConfig(), 'test-token');
  @override
  Future<void> validate() async {}
  @override
  Future<({String sha, int size, Uint8List? data})?> metadata() async =>
      cloud == null
      ? null
      : (sha: SyncCodec.gitBlob(cloud!), size: cloud!.length, data: cloud);
  @override
  Future<Uint8List> download(
    ({String sha, int size, Uint8List? data}) meta,
  ) async => cloud!;
  @override
  Future<String> upload(Uint8List bytes, String? expected) async {
    if (race ||
        expected != (cloud == null ? null : SyncCodec.gitBlob(cloud!))) {
      throw APIError('云端备份已变化，已停止覆盖');
    }
    uploads++;
    cloud = bytes;
    return SyncCodec.gitBlob(bytes);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late SpaceStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('space-settings-');
    store = SpaceStore(SpaceRepository(dir));
    await store.initialize();
  });
  tearDown(() async {
    store.dispose();
    await dir.delete(recursive: true);
  });
  const url = 'https://github.com/example/private-backup';
  const token = 'test-only-token';
  final legacyKey = SyncCodec.newRecoveryKey();

  test('SQLite重开保留凭据；本地备份含连接、云端排除；切换仓库不复用凭据', () async {
    final sync = SyncService(store);
    await sync.initialize();
    expect(
      await sync.save(GitHubConfig.fromUrl(url), token, legacyKey),
      isTrue,
    );
    await store.reload();
    final reopened = SyncService(store);
    await reopened.initialize();
    expect(reopened.config.url, url);
    expect(reopened.token, token);
    expect(reopened.recoveryKey, legacyKey);
    expect(File('${dir.path}/github-sync.json').existsSync(), isFalse);
    final exported = '${dir.path}/backup.sqlite';
    await store.repository.exportSQLite(exported);
    expect((await store.readBackup(exported)).settings['github.token'], token);
    final cloud = await SyncCodec.githubOpen(
      await SyncCodec.githubSeal(store.state, legacyKey),
      legacyKey,
    );
    expect(cloud.settings, isEmpty);
    expect(await reopened.save(reopened.config, '', ''), isTrue);
    expect(reopened.token, token);
    expect(
      await reopened.save(
        GitHubConfig.fromUrl('https://github.com/other/repo'),
        '',
        '',
      ),
      isFalse,
    );
    expect(reopened.config.url, url);
    sync.dispose();
    reopened.dispose();
  });

  test('已有连接和钥匙串凭据迁移至SQLite，不修改旧文件', () async {
    const oldConfig = GitHubConfig(branch: 'backup', path: 'old/backup.space');
    final file = File('${dir.path}/github-sync.json');
    await file.writeAsString(
      jsonEncode({'configuration': oldConfig.toJson(), 'automatic': true}),
    );
    final original = await file.readAsBytes();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      DesktopHost.channel,
      (call) async {
        if (call.method == 'readSecret') {
          return (call.arguments as Map)['id'].endsWith(':token')
              ? token
              : legacyKey;
        }
        return null;
      },
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DesktopHost.channel,
        null,
      ),
    );
    final sync = SyncService(store);
    await sync.initialize();
    expect(sync.ready, isTrue);
    expect(
      store.repository.readFile(store.repository.path).settings['github.key'],
      legacyKey,
    );
    expect(sync.config.branch, 'backup');
    expect(sync.config.path, 'old/backup.space');
    expect(await file.readAsBytes(), original);
    sync.dispose();
  });

  test('自设恢复口令随机盐加密、正确恢复、错误密钥及篡改拒绝', () async {
    const key = '这是用户自己设置的恢复密钥2026';
    final snapshot = demoState().copy(settings: {'github.token': token});
    final first = await SyncCodec.githubSeal(snapshot, key);
    final second = await SyncCodec.githubSeal(snapshot, key);
    expect(first, isNot(second));
    expect(
      utf8.decode(first.take(SyncCodec.passphraseHeader.length).toList()),
      'SPACE-GITHUB-2\n',
    );
    final opened = await SyncCodec.githubOpen(first, key);
    expect(SyncCodec.fingerprint(opened), SyncCodec.fingerprint(snapshot));
    expect(opened.settings, isEmpty);
    await expectLater(
      SyncCodec.githubOpen(first, '这是一条错误的恢复密钥2026'),
      throwsFormatException,
    );
    final changed = Uint8List.fromList(first)..[20] ^= 1;
    await expectLater(
      SyncCodec.githubOpen(changed, key),
      throwsFormatException,
    );
    expect(
      () => SyncCodec.validateGitHubKey('too-short'),
      throwsFormatException,
    );
  });

  test('双向传输、恢复前快照、配置保留；错误密钥及云端竞争阻止覆盖', () async {
    final api = MemoryGitHub();
    final sync = SyncService(store, apiFactory: (_, _) => api);
    await sync.initialize();
    await sync.save(GitHubConfig.fromUrl(url), token, legacyKey);
    await store.commit(
      demoState().copy(settings: store.state.settings),
      '合成任务',
    );
    final fingerprint = SyncCodec.fingerprint(store.state);
    await sync.transfer(download: false);
    expect(api.uploads, 1);
    await store.commit(store.state.copy(tasks: []), '清空合成数据');
    await sync.transfer(download: true);
    expect(sync.pending!.backup.tasks.length, 9);
    await sync.restoreGitHub();
    expect(SyncCodec.fingerprint(store.state), fingerprint);
    expect(store.repository.readFile(store.repository.previous).tasks, isEmpty);
    expect(store.state.settings['github.token'], token);
    api.race = true;
    final oldCloud = api.cloud;
    await sync.transfer(download: false);
    expect(api.cloud, oldCloud);
    expect(sync.message, contains('云端备份已变化'));
    api.race = false;
    await sync.save(sync.config, '', SyncCodec.newRecoveryKey());
    await sync.transfer(download: false);
    expect(api.uploads, 1);
    expect(sync.message, contains('密钥不正确'));
    sync.dispose();
  });

  test('恢复确认期间业务修改阻止替换，取消不改数据', () async {
    final api = MemoryGitHub()
      ..cloud = await SyncCodec.githubSeal(demoState(), legacyKey);
    final sync = SyncService(store, apiFactory: (_, _) => api);
    await sync.save(GitHubConfig.fromUrl(url), token, legacyKey);
    await sync.transfer(download: true);
    await store.commit(
      store.state.copy(
        tasks: [
          SpaceTask.create().patch({'title': '恢复期间新任务'}),
        ],
      ),
      '新增',
    );
    await sync.restoreGitHub();
    expect(store.state.tasks.single.title, '恢复期间新任务');
    expect(sync.message, contains('本地数据已变化'));
    await sync.transfer(download: true);
    sync.cancelPending();
    expect(sync.pending, isNull);
    expect(store.state.tasks.single.title, '恢复期间新任务');
    sync.dispose();
  });

  test('SQLite导入拒绝JSON且原库保留；恢复保留本机连接', () async {
    await store.preferences({'github.token': token, 'github.key': legacyKey});
    final file = File('${dir.path}/backup.json')
      ..writeAsStringSync(jsonEncode(demoState().toJson()));
    await expectLater(store.readBackup(file.path), throwsA(anything));
    expect(store.state.tasks, isEmpty);
    await store.applyBackup(
      demoState().copy(
        settings: {'github.token': 'remote-token', 'appearance': 'dark'},
      ),
    );
    expect(store.state.settings['github.token'], token);
    expect(store.appearance, 'dark');
  });

  test('仓库URL校验及.git后缀；拒绝凭据、分支链接和外部域名', () {
    expect(GitHubConfig.fromUrl('$url.git/').url, url);
    for (final bad in [
      'http://github.com/a/b',
      'https://other.test/a/b',
      'https://x:y@github.com/a/b',
      '$url/tree/main',
      '$url?token=abc',
      'https://github.com/a/..',
    ]) {
      expect(() => GitHubConfig.fromUrl(bad), throwsFormatException);
    }
  });

  final screenshotKey = GlobalKey();
  Future<void> launch(WidgetTester t, {bool animations = false}) async {
    t.view.physicalSize = const Size(1020, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: !animations);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await t.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: SpaceApp(store: store),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> capture(WidgetTester t, String name) async {
    await t.runAsync(() async {
      await Directory('verification/screenshots').create(recursive: true);
      final boundary =
          screenshotKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 1);
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'verification/screenshots/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      picture.dispose();
    });
  }

  testWidgets('系统跟随、手动覆盖、重开保留及连续过渡中间帧', (t) async {
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await launch(t, animations: true);
    final context = t.element(find.byType(Workspace));
    expect(store.appearance, 'system');
    expect(Palette.of(context).darkness, 0);
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await t.pump();
    await t.pump(const Duration(milliseconds: 90));
    final middle = Palette.of(context);
    expect(middle.darkness, greaterThan(0));
    expect(middle.darkness, lessThan(1));
    expect(middle.canvas, isNot(const Palette(false).canvas));
    expect(middle.canvas, isNot(const Palette(true).canvas));
    await t.pumpAndSettle();
    expect(Palette.of(context).darkness, 1);
    await t.runAsync(() => store.preference('appearance', 'light'));
    await t.pumpAndSettle();
    expect(Palette.of(context).darkness, 0);
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await t.pumpAndSettle();
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await t.pumpAndSettle();
    expect(Palette.of(context).darkness, 0);
    await t.runAsync(store.reload);
    expect(store.appearance, 'light');
    await t.runAsync(() => store.preference('appearance', 'system'));
    await t.pumpAndSettle();
    expect(Palette.of(context).darkness, 1);
  });

  testWidgets('数据库导入导出使用专用文件面板，取消不改数据库；附件另存保持通用', (t) async {
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      DesktopHost.channel,
      (call) async {
        calls.add(call);
        if (call.method == 'openFiles') return <String>[];
        return null;
      },
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DesktopHost.channel,
        null,
      ),
    );
    await launch(t);
    showSettings(t.element(find.byType(Workspace)), store);
    await t.pumpAndSettle();
    final original = await t.runAsync(
      () => File(store.repository.path).readAsBytes(),
    );
    await t.tap(find.widgetWithText(SpaceButton, '导出SQLite'));
    await t.pumpAndSettle();
    expect(calls.singleWhere((c) => c.method == 'saveFile').arguments, {
      'name': 'Space备份.sqlite',
      'sqliteOnly': true,
    });
    await t.tap(find.widgetWithText(SpaceButton, '导入SQLite'));
    await t.pumpAndSettle();
    expect(calls.singleWhere((c) => c.method == 'openFiles').arguments, {
      'multiple': false,
      'sqliteOnly': true,
    });
    expect(
      await t.runAsync(() => File(store.repository.path).readAsBytes()),
      original,
    );
    expect(find.text('导入备份'), findsNothing);
    await t.runAsync(() => DesktopHost.saveFile('附件.txt'));
    expect(calls.lastWhere((c) => c.method == 'saveFile').arguments, {
      'name': '附件.txt',
      'sqliteOnly': false,
    });
    await t.tap(find.text('完成'));
    await t.pumpAndSettle();
  });

  testWidgets('连接字段自动落库，关闭重开保留；云端按钮先确认', (t) async {
    await launch(t);
    showSettings(t.element(find.byType(Workspace)), store);
    await t.pumpAndSettle();
    // SpaceInput exposes its label through Semantics rather than InputDecoration.
    Finder controllerInput(String hint) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    );
    await t.enterText(controllerInput('https://github.com/账号/仓库'), url);
    await t.enterText(controllerInput('填写此仓库的访问令牌'), token);
    await t.enterText(controllerInput('自行设置至少12个字符，其他设备使用相同密钥'), legacyKey);
    await t.pump(const Duration(milliseconds: 700));
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(store.state.settings['github.token'], token);
    expect(store.state.settings['github.key'], legacyKey);
    await t.scrollUntilVisible(
      find.text('同步数据到云端'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('同步数据到云端'));
    await t.pumpAndSettle();
    expect(find.text('同步到云端'), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    await t.tap(find.text('完成'));
    await t.pumpAndSettle();
    showSettings(t.element(find.byType(Workspace)), store);
    await t.pumpAndSettle();
    expect(find.text(url), findsOneWidget);
    expect(controllerInput('已保存到SQLite，留空保留'), findsNWidgets(2));
    await t.tap(find.text('完成'));
    await t.pumpAndSettle();
  });

  for (final width in [700.0, 1020.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('$width ${dark ? '深' : '浅'}色设置分栏、滚动、按钮和分类自适应', (t) async {
        final font = File('/System/Library/Fonts/STHeiti Medium.ttc');
        await t.runAsync(() async {
          if (font.existsSync()) {
            await (FontLoader(
              'PingFang SC',
            )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
          }
          await store.preference('appearance', dark ? 'dark' : 'light');
        });
        await launch(t);
        t.view.physicalSize = Size(width, width >= 1400 ? 1000 : 860);
        await t.pumpAndSettle();
        showSettings(t.element(find.byType(Workspace)), store);
        await t.pumpAndSettle();
        expect(find.text('跟随系统'), findsOneWidget);
        final appearance = t.getRect(find.text('界面主题'));
        final cloud = t.getRect(find.text('GitHub 私有仓库同步'));
        if (width >= 1000) {
          expect(cloud.left, greaterThan(appearance.right));
          expect(
            (cloud.top - t.getRect(find.text('外观与交互').last).top).abs(),
            lessThan(1),
          );
        } else {
          expect(cloud.top, greaterThan(appearance.bottom));
        }
        final export = t.getRect(find.widgetWithText(SpaceButton, '导出SQLite'));
        final import = t.getRect(find.widgetWithText(SpaceButton, '导入SQLite'));
        final restore = t.getRect(find.widgetWithText(SpaceButton, '恢复上次备份'));
        final reveal = t.getRect(find.widgetWithText(SpaceButton, '打开数据库文件夹'));
        expect(export.top, import.top);
        expect(restore.top, reveal.top);
        expect(restore.top, greaterThan(export.bottom));
        expect(export.right, lessThan(import.left));
        expect(export.width, lessThan(280));
        expect(find.text('同步数据到云端'), findsOneWidget);
        expect(find.text('恢复云端数据'), findsOneWidget);
        for (final removed in [
          '本地数据库',
          '其他位置的手动快照同步',
          '导出JSON',
          '保存GitHub配置',
          '创建访问令牌…',
          '下载云端预览',
        ]) {
          expect(find.text(removed), findsNothing);
        }
        if (width >= 1400) {
          await capture(t, 'settings-2.0.9-${dark ? 'dark' : 'light'}');
        }
        await t.tap(find.byKey(const ValueKey('settings-category-4')));
        await t.pumpAndSettle();
        expect(find.text('界面主题'), findsNothing);
        expect(find.text('仓库地址'), findsNothing);
        expect(find.text('载入演示任务'), findsOneWidget);
        final demo = t.getRect(find.widgetWithText(SpaceButton, '载入演示任务'));
        final clear = t.getRect(find.widgetWithText(SpaceButton, '清空所有任务'));
        expect(clear.top, greaterThan(demo.bottom));
        await t.tap(find.byKey(const ValueKey('settings-category-0')));
        await t.pumpAndSettle();
        expect(find.text('界面主题'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.tap(find.text('完成'));
        await t.pumpAndSettle();
      });
    }
  }

  testWidgets('分类切换和窗口调整保留未提交配置、键盘可切换并Esc关闭', (t) async {
    await launch(t, animations: true);
    showSettings(t.element(find.byType(Workspace)), store);
    await t.pumpAndSettle();
    Finder tokenInput() => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '填写此仓库的访问令牌',
    );
    await t.enterText(tokenInput(), 'test-only-draft');
    final originalController = t.widget<TextField>(tokenInput()).controller;
    await t.tap(find.byKey(const ValueKey('settings-category-1')));
    await t.pump(const Duration(milliseconds: 60));
    await t.tap(find.byKey(const ValueKey('settings-category-3')));
    await t.pump(const Duration(milliseconds: 60));
    t.view.physicalSize = const Size(700, 860);
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(tokenInput()).controller,
      same(originalController),
    );
    expect(originalController!.text, 'test-only-draft');
    expect(t.widget<TextField>(tokenInput()).obscureText, isTrue);
    await t.tap(find.byTooltip('显示Token令牌'));
    await t.pumpAndSettle();
    expect(t.widget<TextField>(tokenInput()).obscureText, isFalse);
    final nav = find.byKey(const ValueKey('settings-category-2'));
    Focus.of(
      t.element(
        find.descendant(of: nav, matching: find.byType(GestureDetector)).first,
      ),
    ).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('本地备份与恢复'), findsOneWidget);
    expect(find.text('仓库地址'), findsNothing);
    expect(t.takeException(), isNull);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('数据与设置'), findsNothing);
    expect(store.modal, isFalse);
    expect(store.state.settings['github.token'], isNull);
  });

  testWidgets('数据管理确认取消不改任务，主题与滚动条立即生效并持久化', (t) async {
    await t.runAsync(() => store.commit(demoState(), '合成数据'));
    await launch(t);
    showSettings(t.element(find.byType(Workspace)), store);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('settings-category-4')));
    await t.pumpAndSettle();
    final count = store.state.tasks.length;
    await t.tap(find.widgetWithText(SpaceButton, '清空所有任务'));
    await t.pumpAndSettle();
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(store.state.tasks.length, count);
    await t.tap(find.byKey(const ValueKey('settings-category-1')));
    await t.pumpAndSettle();
    await t.tap(find.text('深色'));
    await t.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pumpAndSettle();
    expect(store.appearance, 'dark');
    final previous = store.hideScrollbars;
    await t.tap(find.byType(Switch));
    await t.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pumpAndSettle();
    expect(store.hideScrollbars, !previous);
    await t.runAsync(store.reload);
    await t.pumpAndSettle();
    expect(store.appearance, 'dark');
    expect(store.hideScrollbars, !previous);
    await t.tap(find.text('完成'));
    await t.pumpAndSettle();
  });
}
