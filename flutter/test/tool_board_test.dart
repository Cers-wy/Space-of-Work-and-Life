import 'dart:io';
import 'dart:async';

import 'package:space_flutter/core/models.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/drive.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/core/tool_board.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/main.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/theme.dart';
import 'package:space_flutter/ui/tool_board.dart';

void main() {
  const svg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M2 12h20"/></svg>';
  test('tool configuration and embedded SVG survive SQLite reload; shrinking removes stale chunks', () async {
    final dir = Directory.systemTemp.createTempSync('space-tool-board-');
    final store = SpaceStore(SpaceRepository(dir));
    await store.initialize();
    try {
      final link = ToolLink.create(
        name: '本地工具',
        kind: 'local',
        target: '/isolated/tool.html',
        svg: validateToolSvg(svg),
      );
      final modules = [
        ToolModule.create('我的工具', '测试').copy(
          hidden: true,
          span: 8,
          height: 280,
          defaultTool: link.id,
          tools: [link],
        ),
      ];
      expect(
        await store.preferences(encodeToolBoard(modules, store.state.settings)),
        isTrue,
      );
      await store.reload();
      final restored = decodeToolBoard(store.state.settings).single;
      expect(restored.hidden, isTrue);
      expect(restored.span, 8);
      expect(restored.height, 280);
      expect(restored.defaultTool, link.id);
      expect(restored.tools.single.svg, svg);
      expect(restored.tools.single.target, '/isolated/tool.html');
      final long = encodeToolBoard([
        restored.copy(description: '测试' * 4000),
      ], store.state.settings);
      expect(int.parse(long['$toolBoardKey.parts']!), greaterThan(1));
      final short = encodeToolBoard([], {...store.state.settings, ...long});
      expect(short['$toolBoardKey.1'], '');
    } finally {
      store.dispose();
      dir.deleteSync(recursive: true);
    }
  });
  test(
    'icons reject invalid and external SVG; web entries reject invalid URLs',
    () {
      for (final input in [
        '<html/>',
        '<svg><script/></svg>',
        '<svg><image href="https://example.com/a"/></svg>',
        '<svg><path fill="url(https://example.com/a)"/></svg>',
      ]) {
        expect(() => validateToolSvg(input), throwsA(isA<FormatException>()));
      }
      expect(
        () => ToolLink.create(
          name: '错误',
          kind: 'web',
          target: 'file:///etc/hosts',
        ).validate(),
        throwsFormatException,
      );
      final modules = defaultToolModules();
      final spans = modules.map((m) => m.span).toList();
      final narrow = toolBoardLayout(modules, 400);
      expect(narrow.every((r) => r.width == 400 && r.x == 0), isTrue);
      expect(modules.map((m) => m.span), spans);
    },
  );
  testWidgets(
    'tool cards fit light/dark narrow and wide windows; adding a module persists',
    (t) async {
      final dir = Directory.systemTemp.createTempSync('space-tool-ui-');
      final store = SpaceStore(SpaceRepository(dir));
      await t.runAsync(() => store.initialize());
      addTearDown(() {
        store.dispose();
        dir.deleteSync(recursive: true);
      });
      final service = DriveService(dir);
      final key = GlobalKey<ToolBoardState>();
      for (final width in [500.0, 1100.0]) {
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        for (final dark in [false, true]) {
          await t.pumpWidget(
            MaterialApp(
              theme: spaceTheme(dark),
              home: Scaffold(
                body: ToolBoard(
                  key: key,
                  store: store,
                  drive: service,
                  editing: true,
                  illustration: const SizedBox(),
                  openMerge: () {},
                  uploads: () {},
                  files: () {},
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }
      }
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      late Future<void> future;
      await t.runAsync(() async {
        future = key.currentState!.addModule();
      });
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '自动化工具');
      await t.runAsync(() => t.tap(find.byTooltip('保存模块')));
      await t.pumpAndSettle();
      await t.runAsync(() => future.timeout(const Duration(seconds: 5)));
      await t.pumpAndSettle();
      expect(decodeToolBoard(store.state.settings).last.name, '自动化工具');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'hidden module can be restored through the tools titlebar and survives reload',
    (t) async {
      final dir = Directory.systemTemp.createTempSync('space-tool-restore-');
      final store = SpaceStore(SpaceRepository(dir));
      await t.runAsync(() => store.initialize());
      store.openArea(SpaceArea.tools);
      t.view.physicalSize = const Size(1100, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(() async {
        store.dispose();
        await dir.delete(recursive: true);
      });
      await t.pumpWidget(SpaceApp(store: store));
      await t.pumpAndSettle();
      await t.runAsync(() => t.tap(find.byTooltip('管理发票处理')));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(find.text('隐藏模块'));
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (!decodeToolBoard(store.state.settings).first.hidden &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await t.pumpAndSettle();
      final board = t.state<ToolBoardState>(find.byType(ToolBoard));
      expect(
        decodeToolBoard(store.state.settings).first.hidden,
        isTrue,
        reason:
            'saving=${board.saving}, busy=${store.busy}, error=${board.error}, modules=${board.modules.map((m) => '${m.id}:${m.hidden}').toList()}, settings=${store.state.settings.keys.toList()}',
      );
      expect(find.byTooltip('管理发票处理'), findsNothing);
      await t.tap(find.byTooltip('恢复隐藏模块'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('隐藏的模块'), findsOneWidget);
      final restore = find.byWidgetPredicate(
        (w) => w is IconButtonS && w.label == '取消隐藏：发票处理',
      );
      expect(restore, findsOneWidget);
      final action = restore;
      await t.runAsync(() async {
        await t.tap(action);
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (decodeToolBoard(store.state.settings).first.hidden &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(decodeToolBoard(store.state.settings).first.hidden, isFalse);
      expect(find.text('没有隐藏的模块'), findsOneWidget);
      await t.runAsync(() => store.reload());
      expect(decodeToolBoard(store.state.settings).first.hidden, isFalse);
    },
  );
  testWidgets(
    'hidden manager refreshes restore availability when a pending save finishes',
    (t) async {
      final dir = Directory.systemTemp.createTempSync('space-restore-pending-');
      final repository = _PausedToolRepository(dir);
      final store = SpaceStore(repository);
      await t.runAsync(() => store.initialize());
      final modules = [defaultToolModules().first.copy(hidden: true)];
      await t.runAsync(
        () => store.preferences(encodeToolBoard(modules, store.state.settings)),
      );
      final key = GlobalKey<ToolBoardState>();
      t.view.physicalSize = const Size(700, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(() async {
        store.dispose();
        await dir.delete(recursive: true);
      });
      await t.pumpWidget(
        MaterialApp(
          theme: spaceTheme(false),
          home: Scaffold(
            body: ToolBoard(
              key: key,
              store: store,
              drive: DriveService(dir),
              editing: false,
              illustration: const SizedBox(),
              openMerge: () {},
              uploads: () {},
              files: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('恢复隐藏模块'), findsOneWidget);
      repository.pending = Completer<void>();
      late Future<bool> saving;
      await t.runAsync(() async {
        saving = key.currentState!.save(modules);
      });
      await t.runAsync(() => t.tap(find.text('恢复隐藏模块')));
      await t.pumpAndSettle();
      final restore = find.byWidgetPredicate(
        (w) => w is IconButtonS && w.label == '取消隐藏：发票处理',
      );
      VoidCallback? restoreCallback() {
        if (restore.evaluate().isNotEmpty) {
          return t.widget<IconButtonS>(restore).onPressed;
        }
        return t
            .widget<SpaceButton>(
              find
                  .ancestor(
                    of: find.text('恢复'),
                    matching: find.byType(SpaceButton),
                  )
                  .first,
            )
            .onPressed;
      }

      expect(restoreCallback(), isNull);
      await t.runAsync(() async {
        repository.pending!.complete();
        await saving;
        repository.pending = null;
      });
      await t.pumpAndSettle();
      expect(restoreCallback(), isNotNull);
      await t.runAsync(() async {
        await t.tap(restore);
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (key.currentState!.saving && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await t.pumpAndSettle();
      expect(find.text('没有隐藏的模块'), findsOneWidget);
      expect(decodeToolBoard(store.state.settings).single.hidden, isFalse);
      await t.tap(find.byTooltip('完成'));
      await t.pumpAndSettle();
      expect(find.byTooltip('管理发票处理'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}

class _PausedToolRepository extends SpaceRepository {
  Completer<void>? pending;
  _PausedToolRepository(super.directory);
  @override
  Future<SpaceState> save(
    SpaceState state, {
    bool preferencesOnly = false,
  }) async {
    if (preferencesOnly && pending != null) await pending!.future;
    return super.save(state, preferencesOnly: preferencesOnly);
  }
}
