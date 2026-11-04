import 'dart:io';
import 'dart:math' show min, max;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/main.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/dialogs.dart';
import 'package:space_flutter/ui/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late SpaceStore s;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('space-iteration-');
    s = SpaceStore(SpaceRepository(dir));
    await s.initialize();
    await s.commit(demoState(), 'synthetic');
    await s.reload();
    s.notice = null;
  });
  tearDown(() async {
    s.dispose();
    await dir.delete(recursive: true);
  });
  Future<void> launch(WidgetTester t, double width) async {
    t.view.physicalSize = Size(width, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await t.pumpWidget(SpaceApp(store: s));
    await t.pumpAndSettle();
  }

  test('列宽四档、上下限、旧设置与重启恢复', () async {
    expect(s.hideScrollbars, false);
    expect(s.boardWidthRatio('todo'), 1);
    for (final value in boardWidthRatios) {
      await s.preference('boardWidth.todo', '$value');
      await s.reload();
      expect(s.boardWidthRatio('todo'), value);
    }
    expect(snapBoardRatio(-2), .5);
    expect(snapBoardRatio(9), 1);
    expect(snapBoardRatio(.68), 2 / 3);
    await s.preferences({'hideScrollbars': 'true', 'boardWidth.todo': 'NaN'});
    final reopened = SpaceStore(SpaceRepository(dir));
    await reopened.initialize();
    expect(reopened.hideScrollbars, true);
    expect(reopened.boardWidthRatio('todo'), 1);
    reopened.dispose();
  });
  for (final dark in [false, true]) {
    for (final width in [1020.0, 1180.0, 1380.0, 1600.0]) {
      testWidgets('$dark/$width 顶栏双方向过渡按钮无裁切，概览独立收展', (t) async {
        await t.runAsync(() => s.preference('dark', '$dark'));
        await launch(t, width);
        for (final overview in [false, true]) {
          await t.runAsync(
            () => s.preference('overviewCollapsed', '$overview'),
          );
          await t.pumpAndSettle();
          for (final nav in [false, true]) {
            await t.runAsync(() => s.preference('navCollapsed', '$nav'));
            await t.pump();
            for (final ms in [0, 16, 64, 128, 256, 512]) {
              await t.pump(Duration(milliseconds: ms));
              for (final label in [
                '使用帮助',
                overview ? '展开概览' : '收起概览',
                nav ? '展开导航' : '收起导航',
              ]) {
                final f = find.byWidgetPredicate(
                  (w) => w is IconButtonS && w.label == label,
                );
                final rect = t.getRect(f);
                expect(rect.left, greaterThanOrEqualTo(0));
                expect(rect.right, lessThanOrEqualTo(width));
                final target = f.evaluate().single.renderObject!;
                var child = target;
                var ancestor = child.parent;
                while (ancestor != null) {
                  final clip = ancestor.describeApproximatePaintClip(child);
                  if (clip != null) {
                    final global = MatrixUtils.transformRect(
                      ancestor.getTransformTo(null),
                      clip,
                    ).inflate(.1);
                    expect(
                      global.contains(rect.topLeft) &&
                          global.contains(rect.bottomRight),
                      true,
                      reason: '$label/$ms/$ancestor',
                    );
                  }
                  child = ancestor;
                  ancestor = ancestor.parent;
                }
              }
              expect(t.takeException(), isNull);
            }
          }
        }
      });
      testWidgets('$dark/$width 四档独立列宽与等高卡片无溢出', (t) async {
        await t.runAsync(() => s.preference('dark', '$dark'));
        await launch(t, width);
        final column = find.byKey(const ValueKey('board-column-todo'));
        final other = find.byKey(const ValueKey('board-column-doing'));
        final base = t.getSize(column).width,
            otherBase = t.getSize(other).width;
        for (final ratio in boardWidthRatios) {
          await t.runAsync(() => s.preference('boardWidth.todo', '$ratio'));
          await t.pumpAndSettle();
          expect(t.getSize(column).width, closeTo(base * ratio, .01));
          expect(t.getSize(other).width, otherBase);
          final cards = find.descendant(
            of: column,
            matching: find.byType(TaskCard),
          );
          final heights = cards
              .evaluate()
              .map((e) => t.getSize(find.byWidget(e.widget)).height)
              .toSet();
          expect(heights.length, lessThanOrEqualTo(1));
          expect(t.takeException(), isNull);
        }
        final handle = find.byKey(const ValueKey('board-resize-todo'));
        final g = await t.startGesture(t.getCenter(handle));
        await g.moveBy(const Offset(-20, 0));
        await t.pump();
        await g.moveBy(const Offset(-1000, 0));
        await t.pump();
        await t.runAsync(() async {
          await g.up();
          while (s.busy) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await t.pumpAndSettle();
        expect(s.boardWidthRatio('todo'), .5);
        expect(t.takeException(), isNull);
      });
    }
  }
  for (final width in [1020.0, 1600.0]) {
    testWidgets('$width 看板缩窄左对齐，导航和列宽经过中间帧且可反向', (t) async {
      await t.runAsync(() => s.preference('navCollapsed', 'false'));
      await launch(t, width);
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: false);
      await t.pump(const Duration(milliseconds: 600));
      final first = find.byKey(const ValueKey('board-column-todo'));
      final second = find.byKey(const ValueKey('board-column-doing'));
      final initial = t.getRect(first);
      await t.runAsync(() => s.preference('boardWidth.todo', '.5'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 80));
      expect(t.getSize(first).width, lessThan(initial.width));
      expect(t.getSize(first).width, greaterThan(initial.width * .5));
      await t.pump(const Duration(milliseconds: 600));
      expect(t.getRect(first).left, closeTo(initial.left, .1));
      expect(
        t.getRect(second).left,
        closeTo(initial.left + initial.width * .5 + 12, .1),
      );
      for (final collapsed in [true, false]) {
        final start = t.getRect(first).left;
        await t.runAsync(() => s.preference('navCollapsed', '$collapsed'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 80));
        final middle = t.getRect(first).left;
        await t.pump(const Duration(milliseconds: 600));
        final end = t.getRect(first).left;
        expect(middle, inExclusiveRange(min(start, end), max(start, end)));
        expect(t.takeException(), isNull);
      }
      await t.runAsync(() => s.preference('navCollapsed', 'true'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 64));
      await t.runAsync(() => s.preference('navCollapsed', 'false'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(t.getRect(first).left, closeTo(initial.left, .1));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('全局隐藏在现有弹窗中立即生效，关闭恢复滚动条', (t) async {
    await launch(t, 1380);
    final future = showSettings(t.element(find.byType(Workspace)), s);
    await t.pumpAndSettle();
    expect(find.text('隐藏滚动条'), findsOneWidget);
    expect(find.byType(Scrollbar), findsWidgets);
    await t.runAsync(() => s.preference('hideScrollbars', 'true'));
    await t.pumpAndSettle();
    expect(find.byType(Scrollbar), findsNothing);
    final scroll = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(SingleChildScrollView),
    );
    if (scroll.evaluate().isNotEmpty) {
      await t.drag(scroll.first, const Offset(0, -150));
      await t.pumpAndSettle();
    }
    expect(find.byType(Scrollbar), findsNothing);
    await t.runAsync(() => s.preference('hideScrollbars', 'false'));
    await t.pumpAndSettle();
    expect(find.byType(Scrollbar), findsWidgets);
    Navigator.of(t.element(find.text('隐藏滚动条'))).pop();
    await t.pumpAndSettle();
    await future;
    expect(t.takeException(), isNull);
  });
  testWidgets('最窄停用列标题与新建入口无溢出；双击恢复默认宽度', (t) async {
    await t.runAsync(
      () => s.commit(s.state.copy(disabledStatuses: ['doing']), 'synthetic'),
    );
    await t.runAsync(
      () => s.preferences({'boardWidth.doing': '.5', 'boardWidth.todo': '.5'}),
    );
    await launch(t, 1020);
    expect(t.takeException(), isNull);
    final handle = find.byKey(const ValueKey('board-resize-todo'));
    await t.tap(handle);
    await t.pump(const Duration(milliseconds: 80));
    await t.runAsync(() async {
      await t.tap(handle);
      while (s.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await t.pumpAndSettle();
    expect(s.boardWidthRatio('todo'), 1);
  });
  testWidgets('甘特双折角尺寸与全开、全关、无项目禁用状态', (t) async {
    await t.runAsync(() => s.preference('viewMode', 'gantt'));
    await launch(t, 1380);
    final expand = find.byWidgetPredicate(
      (w) => w is IconButtonS && w.label == '展开全部项目',
    );
    final collapse = find.byWidgetPredicate(
      (w) => w is IconButtonS && w.label == '收起全部项目',
    );
    expect(t.widget<IconButtonS>(expand).icon, 'expand-all');
    expect(t.widget<IconButtonS>(expand).iconSize, 20);
    expect(t.getSize(expand), const Size(40, 40));
    expect(t.widget<IconButtonS>(expand).onPressed, isNull);
    await t.tap(collapse);
    await t.pumpAndSettle();
    expect(t.widget<IconButtonS>(collapse).onPressed, isNull);
    expect(t.widget<IconButtonS>(expand).onPressed, isNotNull);
    await t.tap(expand);
    await t.pumpAndSettle();
    expect(t.widget<IconButtonS>(expand).onPressed, isNull);
    s.query.text = 'no-synthetic-match';
    s.refreshQuery();
    await t.pumpAndSettle();
    expect(t.widget<IconButtonS>(expand).onPressed, isNull);
    expect(t.widget<IconButtonS>(collapse).onPressed, isNull);
  });
  testWidgets('隐藏开关覆盖四视图和任务编辑的嵌套滚动区域', (t) async {
    await launch(t, 1020);
    for (final view in ['board', 'list', 'gantt', 'calendar']) {
      await t.runAsync(
        () => s.preferences({'viewMode': view, 'hideScrollbars': 'true'}),
      );
      await t.pumpAndSettle();
      expect(find.byType(Scrollbar), findsNothing, reason: view);
      await t.runAsync(() => s.preference('hideScrollbars', 'false'));
      await t.pumpAndSettle();
      expect(find.byType(Scrollbar), findsWidgets, reason: view);
    }
    await t.runAsync(() => s.preference('hideScrollbars', 'true'));
    final future = editTask(
      t.element(find.byType(Workspace)),
      s,
      s.state.tasks.first,
      existing: true,
    );
    await t.pumpAndSettle();
    expect(find.byType(Scrollbar), findsNothing);
    Navigator.of(t.element(find.text('取消').last)).pop();
    await t.pumpAndSettle();
    await future;
    expect(t.takeException(), isNull);
  });
}
