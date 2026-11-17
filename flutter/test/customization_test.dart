import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/schedule.dart';
import 'package:space_flutter/ui/dialogs.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/theme.dart';

void main() {
  late Directory dir;
  late SpaceStore store;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('space-customization-');
    store = SpaceStore(SpaceRepository(dir));
    await store.initialize();
    await store.commit(demoState(count: 12), 'synthetic');
  });
  tearDown(() async {
    store.dispose();
    await dir.delete(recursive: true);
  });

  test('smoke preferences are independent, persistent and removed with deleted status', () async {
    expect(store.smokeForStatus('doing'), isTrue);
    await store.setStatusSmoke('todo', false);
    await store.reload();
    expect(store.smokeForStatus('todo'), isFalse);
    expect(store.smokeForStatus('doing'), isTrue);
    await store.addStatus('自定义');
    await store.setStatusSmoke('custom:自定义', false);
    expect(store.smokeForStatus('custom:自定义'), isFalse);
    await store.deleteStatus('custom:自定义', 'todo');
    expect(store.state.settings.containsKey('cardSmoke.custom:自定义'), isFalse);
    expect(store.smokeForStatus('todo'), isFalse);
  });

  testWidgets(
    'status management smoke controls have bounded widths and accept keyboard toggles',
    (tester) async {
      tester.view.physicalSize = const Size(1020, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => store.addStatus('自定义检查'));
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: spaceTheme(dark),
            home: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () => showStatuses(c, store),
                  child: const Text('状态管理'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('状态管理'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final toggle = find.byKey(const ValueKey('status-smoke-todo'));
        expect(tester.getSize(toggle).width, 32);
        expect(tester.widget<SpaceCheckbox>(toggle).showLabel, isFalse);
        expect(find.text('烟雾动画'), findsNothing);
        expect(find.text('新增状态'), findsNothing);
        expect(find.text('删除'), findsNothing);
        expect(find.text('完成'), findsNothing);
        final row = find
            .ancestor(of: toggle, matching: find.byType(SpaceEditorRow))
            .first;
        final name = find.descendant(of: row, matching: find.text('待办'));
        final builtin = find.byKey(const ValueKey('status-builtin-todo'));
        expect(
          tester.getRect(builtin).left,
          greaterThan(tester.getRect(name).right),
        );
        expect(
          tester.getRect(builtin).top,
          lessThan(tester.getRect(name).bottom),
        );
        expect(
          tester.getRect(toggle).right,
          closeTo(tester.getRect(row).right - 12, .1),
        );
        expect(find.byTooltip('新增状态'), findsOneWidget);
        final before = tester.widget<SpaceCheckbox>(toggle).value;
        await tester.runAsync(() async {
          await tester.tap(toggle);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        expect(tester.widget<SpaceCheckbox>(toggle).value, !before!);
        final indicator = find
            .descendant(of: toggle, matching: find.byType(AnimatedContainer))
            .first;
        Focus.of(tester.element(indicator)).requestFocus();
        await tester.pump();
        await tester.runAsync(() async {
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        expect(tester.widget<SpaceCheckbox>(toggle).value, before);
        expect(
          find.byKey(const ValueKey('status-smoke-custom:自定义检查')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'Gantt leading header stays fixed only when selected, across themes',
    (tester) async {
      tester.view.physicalSize = const Size(1020, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        await tester.runAsync(
          () => store.preference('ganttFreezeInfo', 'false'),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: spaceTheme(dark),
            home: Scaffold(
              body: ListenableBuilder(
                listenable: store,
                builder: (_, _) => GanttView(store: store),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final view = tester.widget<SingleChildScrollView>(
          find.byKey(const ValueKey('gantt-timeline')),
        );
        view.controller!.jumpTo(0);
        await tester.pump();
        final header = find.text('项目 / 任务名称');
        final start = tester.getTopLeft(header).dx;
        view.controller!.jumpTo(180);
        await tester.pump();
        expect(tester.getTopLeft(header).dx, closeTo(start - 180, 1));
        await tester.runAsync(
          () => store.preference('ganttFreezeInfo', 'true'),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(header).dx, closeTo(start, 1));
        view.controller!.jumpTo(280);
        await tester.pump();
        expect(tester.getTopLeft(header).dx, closeTo(start, 1));
        expect(tester.takeException(), isNull);
      }
    },
  );
}
