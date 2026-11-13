import 'dart:convert';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/core/sync.dart';
import 'package:space_flutter/core/sync_service.dart';
import 'package:space_flutter/host.dart';
import 'package:space_flutter/main.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/settings_controls.dart';
import 'package:space_flutter/core/releases.dart';
import 'package:space_flutter/ui/dialogs.dart';
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
      // SQLite snapshots materialize the built-in category map.
      demoState().copy(
        settings: {
          ...store.state.settings,
          'taskCategories': jsonEncode(demoState().taskCategories),
        },
      ),
      '合成任务',
    );
    final fingerprint = SyncCodec.fingerprint(store.state);
    await sync.transfer(download: false);
    expect(api.uploads, 1);
    await store.commit(store.state.copy(tasks: []), '清空合成数据');
    await sync.transfer(download: true);
    expect(sync.pending, isNotNull, reason: sync.message);
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

  Future<void> launch(
    WidgetTester t, {
    double width = 1020,
    bool animations = false,
  }) async {
    t.view.physicalSize = Size(width, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: !animations);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await t.pumpWidget(SpaceApp(store: store));
    await t.pumpAndSettle();
  }

  ReleaseChecker fakeUpdates() => ReleaseChecker(
    infoLoader: () async => {'version': '2.1.0', 'build': '13'},
    releaseLoader: () async => [
      {
        'tag_name': 'v2.2.0',
        'draft': false,
        'prerelease': false,
        'html_url': '$projectUrl/releases/tag/v2.2.0',
        'assets': [
          {'name': 'Space-2.2.0-macOS-arm64.dmg'},
        ],
      },
    ],
    platform: 'macos',
  );
  Future<void> openSettings(WidgetTester t) async {
    final updates = fakeUpdates();
    addTearDown(updates.dispose);
    showSettings(t.element(find.byType(Workspace)), store, updates: updates);
    await t.pumpAndSettle();
  }

  Future<void> select(WidgetTester t, int index) async {
    await t.tap(find.byKey(ValueKey('settings-category-$index')));
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.tap(find.byTooltip('关闭设置'));
    await t.pumpAndSettle();
  }

  testWidgets('跟随系统临时切换、重复通知、系统变化、固定主题和重启', (t) async {
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await t.runAsync(store.updateSystemAppearance);
    await launch(t, animations: true);
    await t.runAsync(store.toggleTheme);
    await t.pumpAndSettle();
    expect(store.appearance, 'system');
    expect(store.dark, isTrue);
    expect(store.temporaryDark, isTrue);
    await t.runAsync(store.updateSystemAppearance);
    expect(store.temporaryDark, isTrue);
    final reopened = SpaceStore(SpaceRepository(dir));
    await t.runAsync(reopened.initialize);
    expect(reopened.appearance, 'system');
    expect(reopened.temporaryDark, isNull);
    reopened.dispose();
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await t.runAsync(store.updateSystemAppearance);
    await t.pumpAndSettle();
    expect(store.temporaryDark, isNull);
    expect(store.dark, isTrue);
    await t.runAsync(() => store.preference('appearance', 'light'));
    await t.pumpAndSettle();
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await t.runAsync(store.updateSystemAppearance);
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await t.runAsync(store.updateSystemAppearance);
    await t.pumpAndSettle();
    expect(store.dark, isFalse);
    expect(store.appearance, 'light');
    await t.runAsync(store.toggleTheme);
    await t.pumpAndSettle();
    expect(store.appearance, 'dark');
    expect(t.takeException(), isNull);
  });
  testWidgets('备份文件面板取消不修改数据，关于版本与系统外部链接', (t) async {
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      DesktopHost.channel,
      (call) async {
        calls.add(call);
        if (call.method == 'openFiles') return <String>[];
        if (call.method == 'openExternal') return true;
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
    await openSettings(t);
    await select(t, 2);
    final original = await t.runAsync(
      () => File(store.repository.path).readAsBytes(),
    );
    await t.tap(find.widgetWithText(SettingsAction, '导出'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(SettingsAction, '选择文件'));
    await t.pumpAndSettle();
    expect(calls.singleWhere((c) => c.method == 'saveFile').arguments, {
      'name': 'Space备份.spacepack',
      'sqliteOnly': false,
      'title': '导出备份包',
    });
    expect(calls.singleWhere((c) => c.method == 'openFiles').arguments, {
      'multiple': false,
      'sqliteOnly': false,
      'title': '导入 Space 备份',
      'extensions': ['spacepack', 'sqlite', 'sqlite3', 'db'],
    });
    expect(
      await t.runAsync(() => File(store.repository.path).readAsBytes()),
      original,
    );
    await select(t, 7);
    expect(find.text('新版 2.2.0 可下载'), findsOneWidget);
    expect(find.text('Cers'), findsOneWidget);
    await t.tap(find.text('GitHub 项目'));
    await t.pumpAndSettle();
    expect(
      (calls.lastWhere((c) => c.method == 'openExternal').arguments
          as Map)['url'],
      projectUrl,
    );
    await close(t);
    expect(store.modal, isFalse);
  });
  testWidgets('连接编辑自动保存，切换栏目不丢失，上传仍需确认', (t) async {
    await launch(t);
    await openSettings(t);
    await select(t, 3);
    Finder input(String hint) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    );
    await t.enterText(input('https://github.com/账号/仓库'), url);
    await t.enterText(input('填写此仓库的访问令牌'), token);
    await t.enterText(input('自行设置至少12个字符，其他设备使用相同密钥'), legacyKey);
    await t.pump(const Duration(milliseconds: 700));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    expect(store.state.settings['github.token'], token);
    await select(t, 1);
    await select(t, 3);
    expect(find.text(url), findsOneWidget);
    await t.tap(find.text('同步到云端'));
    await t.pumpAndSettle();
    expect(find.text('同步数据到云端'), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    await close(t);
    await openSettings(t);
    await select(t, 3);
    expect(find.text(url), findsOneWidget);
    await close(t);
  });
  testWidgets('关闭按钮支持辅助功能激活，不依赖鼠标坐标', (t) async {
    await launch(t);
    await openSettings(t);
    final handle = t.ensureSemantics();
    final target = find.descendant(
      of: find.byKey(const ValueKey('settings-close')),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == '关闭设置',
      ),
    );
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await t.pumpAndSettle();
    expect(store.modal, isFalse);
    handle.dispose();
  });
  for (final width in [700.0, 1020.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('$width ${dark ? '深' : '浅'}色八页导航、标题栏和滚动适配', (t) async {
        await t.runAsync(
          () => store.preference('appearance', dark ? 'dark' : 'light'),
        );
        await launch(t, width: width);
        await openSettings(t);
        expect(
          t.getSize(find.byKey(const ValueKey('settings-titlebar'))).height,
          t.getSize(find.byKey(const ValueKey('workspace-titlebar'))).height,
        );
        for (final i in [1, 2, 3, 4, 5, 6, 7, 0]) {
          await select(t, i);
          expect(t.takeException(), isNull);
        }
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(store.modal, isFalse);
      });
    }
  }

  testWidgets('发票识别栏目：优先 OCR 默认关闭、说明文字与持久化', (t) async {
    expect(store.preferOcr, isFalse, reason: '开关默认关闭');
    await launch(t);
    await openSettings(t);
    await select(t, 5);
    expect(find.text('优先使用 OCR'), findsOneWidget);
    expect(find.textContaining('默认关闭'), findsOneWidget);
    final toggle = find.byKey(const ValueKey('settings-prefer-ocr'));
    expect(t.widget<Switch>(toggle).value, isFalse);
    await t.tap(toggle);
    await t.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!store.preferOcr && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await t.pumpAndSettle();
    expect(store.preferOcr, isTrue);
    expect(t.widget<Switch>(toggle).value, isTrue);
    await select(t, 0);
    expect(find.text('优先 OCR'), findsOneWidget);
    final reopened = SpaceStore(SpaceRepository(dir));
    addTearDown(reopened.dispose);
    await t.runAsync(reopened.initialize);
    expect(reopened.preferOcr, isTrue, reason: '偏好写入本机设置，重启保留');
    expect(t.takeException(), isNull);
  });
}
