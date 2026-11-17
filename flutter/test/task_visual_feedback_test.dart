import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/main.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/schedule.dart';
import 'package:space_flutter/ui/theme.dart';
import 'package:space_flutter/ui/workspace.dart';

void main() {
  late Directory dir;
  late SpaceStore store;
  final captureKey = GlobalKey();
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('space-ui-feedback-');
    store = SpaceStore(SpaceRepository(dir));
    await store.initialize();
    await store.commit(demoState(count: 12), 'synthetic');
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

  Future<Uint8List> pixels(WidgetTester t, String name) async {
    return (await t.runAsync(() async {
      final boundary =
          captureKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (Platform.environment['SPACE_UI_CAPTURE'] == 'true') {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final folder = Directory(
          'verification/screenshots/ui-feedback-2026-11-17',
        )..createSync(recursive: true);
        await File('${folder.path}/$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
      }
      image.dispose();
      return Uint8List.fromList(raw!.buffer.asUint8List());
    }))!;
  }

  testWidgets(
    'fixed Gantt cells remain painted and clickable beyond their full width',
    (t) async {
      t.view.physicalSize = const Size(1020, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        await t.runAsync(() => store.preference('ganttFreezeInfo', 'true'));
        await t.pumpWidget(
          MaterialApp(
            theme: spaceTheme(dark),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              FlutterQuillLocalizations.delegate,
            ],
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
        final scroll = t
            .widget<SingleChildScrollView>(
              find.byKey(const ValueKey('gantt-timeline')),
            )
            .controller!;
        scroll.jumpTo(0);
        await t.pumpAndSettle();
        final baseline = await pixels(t, 'gantt-$dark-start');
        final firstName = find
            .byWidgetPredicate(
              (w) =>
                  w is Text &&
                  store.visible.any((task) => task.title == w.data),
            )
            .hitTestable()
            .first;
        final name = find.byWidget(t.widget<Text>(firstName));
        // The whole left pane must survive, including actual paint and hit tests.
        for (final offset in [
          180.0,
          440.0,
          scroll.position.maxScrollExtent,
          0.0,
          scroll.position.maxScrollExtent,
        ]) {
          scroll.jumpTo(offset);
          await t.pumpAndSettle();
          final moved = await pixels(t, 'gantt-$dark-${offset.round()}');
          expect(
            name.hitTestable(),
            findsOneWidget,
            reason: 'offset $offset, rect ${t.getRect(name)}',
          );
          for (var y = 65; y < 320; y++) {
            final start = (y * 1020 + 8) * 4;
            expect(
              moved.sublist(start, start + 380 * 4),
              baseline.sublist(start, start + 380 * 4),
              reason: 'fixed pane pixels changed at $offset / row $y',
            );
          }
        }
        await t.tap(name);
        await t.pumpAndSettle();
        expect(find.text('任务详情'), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    },
  );

  testWidgets('smoke changes across the full card in both themes', (t) async {
    await t.runAsync(
      () => ui.FragmentProgram.fromAsset('shaders/task_smoke.frag'),
    );
    for (final dark in [false, true]) {
      Future<Uint8List> frame(double time) async {
        await t.pumpWidget(
          MaterialApp(
            theme: spaceTheme(dark),
            home: Center(
              child: RepaintBoundary(
                key: captureKey,
                child: SizedBox(
                  width: 320,
                  height: 184,
                  child: CardFlow(
                    seed: 37,
                    time: time,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        return pixels(t, 'smoke-$dark-${time.round()}');
      }

      final a = await frame(0);
      final b = await frame(8);
      for (var quadrant = 0; quadrant < 4; quadrant++) {
        var changed = 0;
        for (
          var y = 12 + (quadrant ~/ 2) * 80;
          y < 84 + (quadrant ~/ 2) * 80;
          y++
        ) {
          for (
            var x = 12 + (quadrant % 2) * 150;
            x < 152 + (quadrant % 2) * 150;
            x++
          ) {
            final i = (y * 320 + x) * 4;
            if ((a[i + 3] - b[i + 3]).abs() > 3) changed++;
          }
        }
        expect(changed, greaterThan(2500), reason: '$dark quadrant $quadrant');
      }
      await t.pumpWidget(
        MaterialApp(
          theme: spaceTheme(dark),
          home: Center(
            child: RepaintBoundary(
              key: captureKey,
              child: SizedBox(
                width: 320,
                height: 184,
                child: Stack(
                  children: [
                    const Positioned.fill(child: Ambient()),
                    TaskCard(
                      task: store.visible.first,
                      store: store,
                      onEdit: () {},
                      preview: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await pixels(t, 'task-card-$dark');
      expect(t.takeException(), isNull);
    }
  });

  testWidgets(
    'Gantt controls align at 32px and tool layout edit keeps its action feedback',
    (t) async {
      t.view.physicalSize = const Size(1020, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await t.runAsync(() => store.preference('viewMode', 'gantt'));
      await t.pumpWidget(SpaceApp(store: store));
      await t.pumpAndSettle();
      final freeze = find.byKey(const ValueKey('gantt-freeze-info'));
      final toolbarRects = <Rect>[];
      for (final label in [
        '固定左侧项目信息',
        '收起全部项目',
        '日刻度',
        '周刻度',
        '月刻度',
        '上个月',
        '下个月',
      ]) {
        final target = find.byTooltip(label);
        expect(t.getSize(target), const Size(32, 32), reason: label);
        expect(t.getCenter(target).dy, t.getCenter(freeze).dy, reason: label);
        toolbarRects.add(t.getRect(target));
      }
      expect(t.getSize(find.byType(MonthField)).height, 32);
      toolbarRects.insert(6, t.getRect(find.byType(MonthField)));
      for (var i = 1; i < toolbarRects.length; i++) {
        expect(toolbarRects[i].left - toolbarRects[i - 1].right, 8);
      }
      store.openArea(SpaceArea.tools);
      await t.pumpAndSettle();
      final edit = find.byTooltip('编辑卡片宽高');
      expect(edit, findsOneWidget);
      await t.tap(edit);
      await t.pumpAndSettle();
      expect(find.byTooltip('完成布局编辑'), findsOneWidget);
      expect(
        t
            .widget<IconButtonS>(
              find.byWidgetPredicate(
                (w) => w is IconButtonS && w.label == '完成布局编辑',
              ),
            )
            .selected,
        isTrue,
      );
      await t.tap(find.byTooltip('完成布局编辑'));
      await t.pumpAndSettle();
      expect(edit, findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
