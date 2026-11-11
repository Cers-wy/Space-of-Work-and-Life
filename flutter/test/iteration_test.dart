import 'dart:io';
import 'dart:math' show min, max;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/main.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/dialogs.dart';
import 'package:space_flutter/ui/workspace.dart';
import 'package:space_flutter/ui/theme.dart';

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

  test('列宽连续比例、上下限、旧设置与重启恢复', () async {
    expect(s.hideScrollbars, false);
    expect(s.boardWidthRatio('todo'), 1);
    for (final value in boardWidthRatios) {
      await s.preference('boardWidth.todo', '$value');
      await s.reload();
      expect(s.boardWidthRatio('todo'), value);
    }
    expect(snapBoardRatio(-2), .5);
    expect(snapBoardRatio(9), 1);
    expect(snapBoardRatio(.68), .68);
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
  for (final width in [1020.0, 1600.0]) {
    testWidgets('$width 导航图标保持同一实例，逐帧连续且快速反向无跳位', (t) async {
      await t.runAsync(() => s.preference('navCollapsed', 'false'));
      await launch(t, width);
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: false);
      await t.pump(const Duration(milliseconds: 600));
      final icons = [
        find.byKey(const ValueKey('navigation-mark')),
        find.byKey(const ValueKey('navigation-task-icon')),
        find.byKey(const ValueKey('navigation-settings')),
      ];
      final elements = icons.map(t.element).toList();
      final target = find.descendant(
        of: icons.last,
        matching: find.byType(GestureDetector),
      );
      final focus = Focus.of(t.element(target));
      focus.requestFocus();
      await t.pump();
      final initial = icons.map(t.getCenter).toList();
      for (final collapsed in [true, false, true, false]) {
        final before = icons.map(t.getCenter).toList();
        await t.runAsync(() => s.preference('navCollapsed', '$collapsed'));
        await t.pump();
        final filters = t.widgetList<BackdropFilter>(
          find.descendant(
            of: find.byType(Workspace),
            matching: find.byType(BackdropFilter),
          ),
        );
        expect(CardFlow.debugSnapshotImages, greaterThan(0));
        expect(filters, isNotEmpty);
        expect(filters.every((f) => !f.enabled), isTrue);
        for (var i = 0; i < icons.length; i++) {
          expect(icons[i], findsOneWidget);
          expect(t.element(icons[i]), same(elements[i]));
          expect(focus.hasFocus, isTrue);
          expect((t.getCenter(icons[i]) - before[i]).distance, lessThan(.1));
        }
        final glowTime = t.widget<CardFlow>(find.byType(CardFlow).first).time;
        var previous = before;
        // Reverse every movement while still in flight.
        for (var frame = 0; frame < 5; frame++) {
          await t.pump(const Duration(milliseconds: 16));
          final now = icons.map(t.getCenter).toList();
          for (var i = 0; i < icons.length; i++) {
            expect(icons[i], findsOneWidget);
            expect(t.element(icons[i]), same(elements[i]));
            expect((now[i] - previous[i]).distance, lessThan(12));
          }
          previous = now;
          expect(
            t.widget<CardFlow>(find.byType(CardFlow).first).time,
            glowTime,
          );
        }
      }
      await t.pump(const Duration(milliseconds: 600));
      await t.pump();
      expect(focus.hasFocus, isTrue);
      expect(CardFlow.debugSnapshotImages, 0);
      expect(
        t
            .widgetList<BackdropFilter>(
              find.descendant(
                of: find.byType(Workspace),
                matching: find.byType(BackdropFilter),
              ),
            )
            .every((f) => f.enabled),
        isTrue,
      );
      final column = find.byKey(const ValueKey('board-column-todo'));
      final settledWidth = t.getSize(column).width;
      final pausedGlow = t.widget<CardFlow>(find.byType(CardFlow).first).time;
      await t.pump(const Duration(milliseconds: 80));
      expect(t.getSize(column).width, closeTo(settledWidth, .1));
      expect(CardFlow.debugSnapshotImages, 0);
      expect(
        t.widget<CardFlow>(find.byType(CardFlow).first).time,
        greaterThan(pausedGlow),
      );
      for (var i = 0; i < icons.length; i++) {
        expect(t.element(icons[i]), same(elements[i]));
        expect((t.getCenter(icons[i]) - initial[i]).distance, lessThan(.1));
      }
      expect(t.takeException(), isNull);
    });
    testWidgets('$width 导航减少动态立即完成，图标操作和键盘焦点保留', (t) async {
      await t.runAsync(() => s.preference('navCollapsed', 'false'));
      await launch(t, width);
      final settings = find.byKey(const ValueKey('navigation-settings'));
      final target = find.descendant(
        of: settings,
        matching: find.byType(GestureDetector),
      );
      final focus = Focus.of(t.element(target));
      focus.requestFocus();
      await t.pump();
      expect(focus.hasFocus, isTrue);
      final expanded = t.getCenter(
        find.byKey(const ValueKey('navigation-task-icon')),
      );
      await t.runAsync(() => s.preference('navCollapsed', 'true'));
      await t.pump();
      expect(focus.hasFocus, isTrue);
      expect(
        t.getCenter(find.byKey(const ValueKey('navigation-task-icon'))).dy,
        closeTo(expanded.dy - 40, .1),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      final titlebar = find.byKey(const ValueKey('settings-titlebar'));
      expect(titlebar, findsOneWidget);
      Navigator.of(t.element(titlebar)).pop();
      await t.pumpAndSettle();
      s.query.text = '不存在的测试任务';
      s.refreshQuery();
      await t.pump();
      await t.tap(find.byKey(const ValueKey('navigation-task-icon')));
      await t.pumpAndSettle();
      expect(s.query.text, isEmpty);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('导航选中图标悬停保持单层并保留按下反馈', (t) async {
    await launch(t, 1020);
    final button = find.byKey(const ValueKey('navigation-task'));
    final icon = find.byKey(const ValueKey('navigation-task-icon'));
    final surface = find
        .descendant(of: button, matching: find.byType(AnimatedContainer))
        .first;
    final opacity = find
        .descendant(of: button, matching: find.byType(Opacity))
        .first;
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    for (final appearance in ['light', 'dark', 'system']) {
      await t.runAsync(() => s.preference('appearance', appearance));
      for (final collapsed in [false, true]) {
        await t.runAsync(() => s.preference('navCollapsed', '$collapsed'));
        await t.pumpAndSettle();
        final location = t.getCenter(icon);
        await mouse.moveTo(location);
        await t.pumpAndSettle();
        final decoration =
            t.widget<AnimatedContainer>(surface).decoration! as BoxDecoration;
        expect(decoration.color, Colors.transparent);
        expect(decoration.boxShadow, isNull);
        await mouse.down(location);
        await t.pump(const Duration(milliseconds: 120));
        expect(t.widget<Opacity>(opacity).opacity, lessThan(1));
        await mouse.up();
        await t.pumpAndSettle();
      }
    }
    await mouse.removePointer();
  });
  testWidgets('全局隐藏在现有弹窗中立即生效，关闭恢复滚动条', (t) async {
    await launch(t, 1380);
    final future = showSettings(t.element(find.byType(Workspace)), s);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('settings-category-1')));
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
  test('看板列设置按状态保存、重启恢复，全选清除偏好', () async {
    expect(s.boardColumns, isEmpty);
    expect(s.boardStatuses, ['todo', 'doing', 'done']);
    await s.setBoardColumns({'todo', 'done'});
    expect(s.boardStatuses, ['todo', 'done']);
    await s.reload();
    expect(s.boardStatuses, ['todo', 'done']);
    final reopened = SpaceStore(SpaceRepository(dir));
    await reopened.initialize();
    expect(reopened.boardStatuses, ['todo', 'done']);
    await reopened.setBoardColumns({'todo', 'doing', 'done'});
    expect(reopened.boardColumns, isEmpty);
    expect(reopened.boardStatuses, ['todo', 'doing', 'done']);
    await reopened.addStatus('待复核');
    const custom = 'custom:待复核';
    expect(reopened.boardStatuses, contains(custom));
    await reopened.setBoardColumns({custom});
    await reopened.toggleStatus(custom);
    expect(reopened.boardStatuses, ['todo', 'doing', 'done']);
    await reopened.toggleStatus(custom);
    expect(reopened.boardStatuses, [custom]);
    await reopened.deleteStatus(custom, 'todo');
    expect(reopened.boardColumns, isEmpty, reason: '已删除状态从设置中清理');
    reopened.dispose();
  });
  testWidgets('筛选浮层多选看板列，看板立即增减列且筛选条件不变', (t) async {
    await t.runAsync(
      () => s.preferences({'viewMode': 'board', 'overviewCollapsed': 'true'}),
    );
    await launch(t, 1380);
    expect(find.byKey(const ValueKey('board-column-doing')), findsOneWidget);
    await t.tap(
      find.byWidgetPredicate((w) => w is IconButtonS && w.label == '筛选与排序'),
    );
    await t.pumpAndSettle();
    expect(find.text('看板列'), findsOneWidget);
    final columnField = find.byWidgetPredicate(
      (w) => w is SpaceMultiSelect && w.label == '看板列',
    );
    expect(t.widget<SpaceMultiSelect>(columnField).values, {
      'todo',
      'doing',
      'done',
    });
    await t.ensureVisible(columnField);
    await t.pumpAndSettle();
    await t.tap(columnField);
    await t.pumpAndSettle();
    final doingCheckbox = find.byWidgetPredicate(
      (w) => w is SpaceCheckbox && w.label == '进行中',
    );
    expect(doingCheckbox, findsOneWidget);
    expect(t.widget<SpaceCheckbox>(doingCheckbox).value, isTrue);
    final ink = find.descendant(
      of: doingCheckbox,
      matching: find.byType(InkWell),
    );
    Focus.of(
      t.element(find.byWidget(t.widget<InkWell>(ink).child!)),
    ).requestFocus();
    await t.pump();
    await t.runAsync(() async {
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (s.busy && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await t.pumpAndSettle();
    expect(t.widget<SpaceCheckbox>(doingCheckbox).value, isFalse);
    expect(s.boardColumns, {'todo', 'done'});
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-column-doing')), findsNothing);
    expect(find.byKey(const ValueKey('board-column-todo')), findsOneWidget);
    expect(s.query.hasFilters, isFalse);

    await t.runAsync(() => s.preference('viewMode', 'list'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('筛选与排序'));
    await t.pumpAndSettle();
    expect(columnField, findsNothing);
    expect(s.query.hasFilters, isFalse);
    expect(t.takeException(), isNull);
  });
  testWidgets('甘特收起展开为单按钮并随状态切换图标', (t) async {
    await t.runAsync(() => s.preference('viewMode', 'gantt'));
    await launch(t, 1380);
    IconButtonS button() => t.widget<IconButtonS>(
      find.byWidgetPredicate(
        (w) =>
            w is IconButtonS &&
            (w.label == '展开全部项目' ||
                w.label == '收起全部项目' ||
                w.label == '暂无可展开或收起的项目'),
      ),
    );
    expect(button().icon, 'collapse-tree');
    expect(button().label, '收起全部项目');
    expect(t.getSize(find.byTooltip('收起全部项目')), const Size(32, 32));
    expect(button().onPressed, isNotNull);
    await t.tap(find.byTooltip('收起全部项目'));
    await t.pumpAndSettle();
    expect(button().icon, 'expand-tree');
    expect(button().label, '展开全部项目');
    await t.tap(find.byTooltip('展开全部项目'));
    await t.pumpAndSettle();
    expect(button().icon, 'collapse-tree');
    s.query.text = 'no-synthetic-match';
    s.refreshQuery();
    await t.pumpAndSettle();
    expect(button().label, '暂无可展开或收起的项目');
    expect(button().onPressed, isNull);
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
