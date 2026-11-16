import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/schedule.dart';
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
    await store.setStatusSmoke('自定义', false);
    await store.deleteStatus('自定义', 'todo');
    expect(store.state.settings.containsKey('cardSmoke.自定义'), isFalse);
    expect(store.smokeForStatus('todo'), isFalse);
  });

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
