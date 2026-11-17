import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/core/tool_board.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/schedule.dart';
import 'package:space_flutter/ui/theme.dart';
import 'package:space_flutter/ui/tool_board.dart';

void main() {
  late Directory dir;
  late SpaceStore store;
  final captureKey = GlobalKey();
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('space-followup-ui-');
    store = SpaceStore(SpaceRepository(dir));
    await store.initialize();
    await store.commit(demoState(count: 60), 'synthetic');
    final font = File(
      Platform.environment['SPACE_TEST_FONT'] ??
          '../work/flutter-qa/test-fonts/Chinese-glyphs.ttf',
    );
    if (font.existsSync()) {
      await (FontLoader(
        'PingFang SC',
      )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  tearDown(() async {
    store.dispose();
    await dir.delete(recursive: true);
  });

  Future<List<int>> fixedPixels(
    WidgetTester t, {
    String? name,
  }) async => (await t.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    final fixed = <int>[];
    for (var y = 65; y < 310; y++) {
      fixed.addAll(data.sublist((y * 1020 + 8) * 4, (y * 1020 + 388) * 4));
    }
    if (name != null && Platform.environment['SPACE_UI_CAPTURE'] == 'true') {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory('verification/screenshots/followup-2026-11-17')
        ..createSync(recursive: true);
      await File('${folder.path}/$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
    }
    image.dispose();
    return fixed;
  }))!;

  Future<void> captureUi(WidgetTester t, String name) async {
    if (Platform.environment['SPACE_UI_CAPTURE'] != 'true') return;
    await t.runAsync(() async {
      final boundary =
          captureKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory('verification/screenshots/followup-2026-11-17')
        ..createSync(recursive: true);
      await File('${folder.path}/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'fixed pane stays outside the date viewport throughout trackpad gestures and vertical scrolls stay linked',
    (t) async {
      t.view.physicalSize = const Size(2040, 1400);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        await t.runAsync(
          () => store.preferences({
            'ganttFreezeInfo': 'true',
            'ganttMode': 'day',
          }),
        );
        await t.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: spaceTheme(dark),
            home: Scaffold(
              body: RepaintBoundary(
                key: captureKey,
                child: Stack(
                  children: [
                    const Positioned.fill(child: Ambient()),
                    ListenableBuilder(
                      listenable: store,
                      builder: (_, _) => GanttView(store: store),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final timeline = find.byKey(const ValueKey('gantt-timeline'));
        final h = t.widget<SingleChildScrollView>(timeline).controller!;
        final leftRows = find.byKey(const ValueKey('gantt-rows-info'));
        final rightRows = find.byKey(const ValueKey('gantt-rows-timeline'));
        final left = t.widget<ListView>(leftRows).controller!;
        final right = t.widget<ListView>(rightRows).controller!;
        left.jumpTo(0);
        h.jumpTo(120);
        await t.pumpAndSettle();
        expect(t.getRect(leftRows).right, t.getRect(timeline).left);
        final baseline = await fixedPixels(t);
        final trackpad = TestPointer(81, PointerDeviceKind.trackpad);
        const position = Offset(760, 84);
        for (final direction in [-1.0, 1.0]) {
          final before = h.offset;
          await t.sendEventToBinding(trackpad.panZoomStart(position));
          for (var i = 1; i <= 8; i++) {
            await t.sendEventToBinding(
              trackpad.panZoomUpdate(
                position,
                pan: Offset(direction * i * 24, 0),
                timeStamp: Duration(milliseconds: i * 16),
              ),
            );
            await t.pump(const Duration(milliseconds: 16));
            expect(
              await fixedPixels(t),
              baseline,
              reason: '$dark direction $direction frame $i',
            );
          }
          expect(
            h.offset,
            direction < 0 ? greaterThan(before) : lessThan(before),
          );
          await t.sendEventToBinding(
            trackpad.panZoomEnd(timeStamp: const Duration(milliseconds: 144)),
          );
          h.jumpTo(340);
          await t.pump();
        }
        final infoPan = TestPointer(82, PointerDeviceKind.trackpad);
        const infoPoint = Offset(100, 84);
        final beforeInfoPan = h.offset;
        await t.sendEventToBinding(infoPan.panZoomStart(infoPoint));
        for (var i = 1; i <= 4; i++) {
          await t.sendEventToBinding(
            infoPan.panZoomUpdate(
              infoPoint,
              pan: Offset(-i * 24.0, 0),
              timeStamp: Duration(milliseconds: i * 16),
            ),
          );
          await t.pump(const Duration(milliseconds: 16));
          expect(await fixedPixels(t), baseline);
        }
        expect(h.offset, greaterThan(beforeInfoPan));
        await t.sendEventToBinding(infoPan.panZoomEnd());
        for (final offset in [-24.0, h.position.maxScrollExtent + 24]) {
          h.jumpTo(offset);
          await t.pump(const Duration(milliseconds: 16));
          expect(
            await fixedPixels(t),
            baseline,
            reason: '$dark overscroll $offset',
          );
        }
        h.jumpTo(340);
        await t.pumpAndSettle();
        await fixedPixels(t, name: 'gantt-$dark');
        await t.sendEventToBinding(
          const PointerScrollEvent(
            position: Offset(100, 350),
            scrollDelta: Offset(0, 160),
          ),
        );
        await t.pumpAndSettle();
        expect(left.offset, greaterThan(0));
        expect(right.offset, closeTo(left.offset, .01));
        await t.sendEventToBinding(
          const PointerScrollEvent(
            position: Offset(700, 350),
            scrollDelta: Offset(0, 120),
          ),
        );
        await t.pumpAndSettle();
        expect(left.offset, closeTo(right.offset, .01));
        final vertical = right.offset;
        for (final frozen in [false, true]) {
          await t.runAsync(
            () => store.preference('ganttFreezeInfo', '$frozen'),
          );
          await t.pumpAndSettle();
          final rows = find.byKey(
            ValueKey('gantt-rows-${frozen ? 'timeline' : 'all'}'),
          );
          expect(
            t.widget<ListView>(rows).controller!.offset,
            closeTo(vertical, .01),
          );
        }
        expect(t.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'calendar scale and date controls use matching 32px surfaces in both themes',
    (t) async {
      t.view.physicalSize = const Size(720, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        await t.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: spaceTheme(dark),
            home: Scaffold(
              body: ListenableBuilder(
                listenable: store,
                builder: (_, _) => CalendarView(store: store),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final date = find.byTooltip('查看日期');
        for (final label in ['日刻度', '周刻度', '月刻度']) {
          final button = find.byTooltip(label);
          expect(t.getSize(button), const Size(32, 32));
          expect(t.getCenter(button).dy, t.getCenter(date).dy);
          await t.runAsync(() async {
            await t.tap(button);
            while (store.busy) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          await t.pumpAndSettle();
          expect(t.getSize(button), const Size(32, 32));
        }
        expect(t.getSize(date).height, 32);
        expect(
          t.getRect(find.byTooltip('周刻度')).left -
              t.getRect(find.byTooltip('日刻度')).right,
          8,
        );
        await t.tap(date);
        await t.pumpAndSettle();
        expect(find.byType(DatePopover), findsOneWidget);
        expect(find.text('清除'), findsNothing);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'tool add and edit forms keep compact icon actions, inline local selection and editable values',
    (t) async {
      t.view.physicalSize = const Size(500, 760);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        ToolLink? saved;
        final initial = ToolLink.create(
          name: '本地工具',
          kind: 'local',
          target: '/isolated/tool.html',
        );
        await t.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: spaceTheme(dark),
              home: Scaffold(
                body: Builder(
                  builder: (c) => Column(
                    children: [
                      TextButton(
                        onPressed: () async {
                          saved = await editToolLink(c);
                        },
                        child: const Text('新增工具'),
                      ),
                      TextButton(
                        onPressed: () async {
                          saved = await editToolLink(c, initial: initial);
                        },
                        child: const Text('编辑工具'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        for (final action in ['新增工具', '编辑工具']) {
          await t.runAsync(() => t.tap(find.text(action)));
          await t.pumpAndSettle();
          for (final label in ['取消', '保存小工具', '上传 SVG 图标']) {
            expect(t.getSize(find.byTooltip(label)), const Size(32, 32));
          }
          expect(find.text('保存'), findsNothing);
          expect(find.text('上传 SVG'), findsNothing);
          if (action == '编辑工具') {
            final target = find.byWidgetPredicate(
              (w) => w is TextField && w.controller?.text == initial.target,
            );
            final pick = find.byTooltip('选择本地入口');
            expect(
              (t.getCenter(target).dy - t.getCenter(pick).dy).abs(),
              lessThan(1),
            );
            await t.enterText(find.byType(TextField).first, '已编辑工具');
          } else {
            await t.enterText(find.byType(TextField).first, '网页工具');
            await t.enterText(
              find.byType(TextField).last,
              'https://example.com',
            );
          }
          await t.pump();
          await captureUi(t, 'tool-$dark-$action');
          await t.runAsync(() => t.tap(find.byTooltip('保存小工具')));
          await t.pumpAndSettle();
          expect(saved!.name, action == '编辑工具' ? '已编辑工具' : '网页工具');
          expect(t.takeException(), isNull);
        }
      }
    },
  );
  testWidgets(
    'module editing retains nested tool changes and compact footer actions',
    (t) async {
      t.view.physicalSize = const Size(500, 760);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final link = ToolLink.create(
        name: '本地入口',
        kind: 'local',
        target: '/isolated/tool.html',
      );
      final initial = ToolModule.create(
        '我的模块',
        '说明',
      ).copy(tools: [link], defaultTool: link.id);
      for (final dark in [false, true]) {
        ToolModule? saved;
        await t.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: spaceTheme(dark),
              home: Scaffold(
                body: Builder(
                  builder: (c) => TextButton(
                    onPressed: () async {
                      saved = await editToolModule(c, initial: initial);
                    },
                    child: const Text('编辑模块'),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.runAsync(() => t.tap(find.text('编辑模块')));
        await t.pumpAndSettle();
        expect(t.getSize(find.byTooltip('保存模块')), const Size(32, 32));
        await t.ensureVisible(find.byTooltip('编辑本地入口'));
        await t.runAsync(() => t.tap(find.byTooltip('编辑本地入口')));
        await t.pumpAndSettle();
        final name = find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == '本地入口',
        );
        await t.enterText(name, '已更新入口');
        await t.runAsync(() => t.tap(find.byTooltip('保存小工具')));
        await t.pumpAndSettle();
        expect(find.byTooltip('编辑已更新入口'), findsOneWidget);
        await captureUi(t, 'module-$dark');
        await t.runAsync(() => t.tap(find.byTooltip('保存模块')));
        await t.pumpAndSettle();
        expect(saved!.tools.single.name, '已更新入口');
        expect(saved!.defaultTool, link.id);
        expect(t.takeException(), isNull);
      }
    },
  );
}
