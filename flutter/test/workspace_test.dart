import 'dart:io';
import 'dart:convert';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:space_flutter/host.dart';
import 'package:space_flutter/core/richtext.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/main.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/workspace.dart';
import 'package:space_flutter/ui/theme.dart';
import 'package:space_flutter/ui/gantt_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> loadTestFont() async {
    final file = File('../work/flutter-qa/test-fonts/Chinese-glyphs.ttf');
    if (file.existsSync()) {
      final loader = FontLoader('PingFang SC')
        ..addFont(file.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
  }

  final screenshotKey = GlobalKey();
  late Directory directory;
  late SpaceStore store;
  setUp(() async {
    await loadTestFont();
    directory = await Directory.systemTemp.createTemp('space-ui-');
    store = SpaceStore(SpaceRepository(directory));
    await store.initialize();
    await store.commit(demoState(), '测试合成数据');
    await store.reload();
    store.notice = null;
  });
  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });
  Future<void> launch(WidgetTester t, double width, double height) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1;
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
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
      final boundary =
          screenshotKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('verification/screenshots').create(recursive: true);
      await File(
        'verification/screenshots/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  test('甘特图黑白主题颜色可读，状态独立且不依赖全局主题改色', () {
    for (final dark in [false, true]) {
      final p = Palette(dark);
      final fills = <Color>{};
      for (final status in [
        'todo',
        'doing',
        'done',
        'custom:待审核',
        'custom:等待反馈',
      ]) {
        final ink = GanttInk.forStatus(p, status);
        expect(ink.fill.a, 1, reason: '默认与显式排期必须有可见实色');
        final contrast =
            (ink.foreground.computeLuminance() + .05) /
            (ink.fill.computeLuminance() + .05);
        expect(contrast, greaterThanOrEqualTo(4.5), reason: '$dark/$status');
        if (builtins.contains(status)) fills.add(ink.fill);
      }
      expect(fills.length, 3);
    }
  });
  for (final dark in [false, true]) {
    final themeName = dark ? 'dark' : 'light';
    testWidgets('$themeName 顶栏导航可点击收展并持久化，面板无凸凹轮廓', (t) async {
      await t.runAsync(
        () => store.preferences({
          'dark': '$dark',
          'navCollapsed': 'true',
          'overviewCollapsed': 'true',
        }),
      );
      await launch(t, 1380, 860);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final toggle = find.byKey(const ValueKey('navigation-toggle'));
      expect(toggle, findsOneWidget);
      expect(t.widget<IconButtonS>(toggle).icon, 'sidebar-open');
      expect(t.getTopLeft(toggle).dx, greaterThan(72));
      expect(t.getTopLeft(toggle).dy, lessThan(80));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Glass && (w.contour == 'sidebar' || w.contour == 'overview'),
        ),
        findsNothing,
      );
      await capture(t, 'release-$themeName-board');
      await t.runAsync(() async {
        await t.tap(toggle);
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (store.busy && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(store.busy, isFalse);
      });
      await t.pumpAndSettle();
      expect(store.navCollapsed, isFalse);
      expect(t.widget<IconButtonS>(toggle).icon, 'sidebar-close');
      await capture(t, 'release-$themeName-expanded');
      await t.runAsync(() async {
        await t.tap(toggle);
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (store.busy && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(store.busy, isFalse);
      });
      await t.pumpAndSettle();
      expect(store.navCollapsed, isTrue);
      await t.runAsync(store.reload);
      await t.pumpAndSettle();
      expect(store.navCollapsed, isTrue);
      expect(t.takeException(), isNull);
    });
    testWidgets('$themeName 甘特图默认排期和自定义状态使用可读填色', (t) async {
      final statuses = [...builtins, 'custom:待审核', 'custom:等待反馈'];
      final tasks = [
        for (final status in statuses)
          SpaceTask.create(
            status: status,
            due: status == 'todo'
                ? ''
                : dayString(beijingDay().add(const Duration(days: 5))),
          ).patch({'title': '配色验收 · ${statusName(status)}'}),
      ];
      await t.runAsync(
        () => store.commit(
          store.state.copy(tasks: tasks, statuses: statuses),
          '合成状态配色样本',
        ),
      );
      await t.runAsync(
        () => store.preferences({
          'dark': '$dark',
          'viewMode': 'gantt',
          'navCollapsed': 'true',
          'overviewCollapsed': 'true',
        }),
      );
      store.notice = null;
      await launch(t, 1380, 860);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      for (final task in tasks) {
        final bar = t.widget<Container>(
          find.byKey(ValueKey('gantt-bar-${task.id}')),
        );
        final decoration = bar.decoration! as BoxDecoration;
        expect(decoration.color!.a, 1, reason: task.status);
        expect(
          decoration.color,
          GanttInk.forStatus(Palette(dark), task.status).fill,
        );
        final label = t.widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey('gantt-bar-${task.id}')),
            matching: find.text(task.title),
          ),
        );
        expect(label.style!.color, Colors.white);
      }
      expect(find.text('待审核'), findsWidgets);
      await capture(t, 'release-$themeName-gantt');
      expect(t.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    for (final width in [1020.0, 1180.0, 1380.0, 1600.0]) {
      testWidgets('${dark ? '暗' : '亮'}主题 ${width.toInt()} 四视图与收展无布局异常', (
        t,
      ) async {
        await t.runAsync(() => store.preference('dark', '$dark'));
        await launch(t, width, 860);
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        for (final view in ['board', 'list', 'gantt', 'calendar']) {
          await t.runAsync(() => store.preference('viewMode', view));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: '$width/$dark/$view');
          if (width == 1380) {
            await capture(t, '${dark ? 'dark' : 'light'}-$view');
          }
        }
        await t.runAsync(() => store.preference('overviewCollapsed', 'true'));
        await t.pumpAndSettle();
        final compactError = t.takeException();
        expect(compactError, isNull);
        if (width == 1380) {
          await capture(t, '${dark ? 'dark' : 'light'}-compact');
        }
        await t.runAsync(() => store.preference('navCollapsed', 'false'));
        await t.pumpAndSettle();
        final layoutError = t.takeException();
        expect(layoutError, isNull);
      });
    }
  }
  testWidgets('新建保存与重开；脏草稿取消保护；浮层键盘取消', (t) async {
    await launch(t, 1380, 860);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final plus = find.byWidgetPredicate(
      (w) => w is IconButtonS && w.label == '新建任务（⌘N / N）',
    );
    await t.tap(plus);
    await t.pumpAndSettle();
    expect(find.text('新建任务'), findsOneWidget);
    await capture(t, 'light-editor');
    final title = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '下一步要做什么？',
    );
    await t.enterText(title, '自动化新建任务');
    await t.tap(find.text('取消').last);
    await t.pumpAndSettle();
    expect(find.text('放弃未保存的更改？'), findsOneWidget);
    await t.tap(find.text('取消').last);
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.text('创建任务').last);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    await capture(t, 'light-editor-after-save');
    expect(store.state.tasks.length, 10);
    expect(store.state.tasks.any((t) => t.title == '自动化新建任务'), isTrue);
    expect(t.takeException(), isNull);
    final reopen = SpaceRepository(directory);
    expect(
      (await t.runAsync(reopen.load))!.tasks.any((t) => t.title == '自动化新建任务'),
      isTrue,
    );
  });
  testWidgets('分类快筛与查询共用；完成和单步撤销', (t) async {
    await launch(t, 1380, 860);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.tap(
      find.byWidgetPredicate((w) => w is SpaceButton && w.tooltip == '快速筛选工作'),
    );
    await t.pumpAndSettle();
    expect(store.visible.every((t) => t.category == 'work'), isTrue);
    final task = store.visible.first;
    await t.runAsync(() => store.moveTask(task.id, 'done'));
    expect(
      store.state.tasks.firstWhere((t) => t.id == task.id).completedAt,
      isNotNull,
    );
    await t.runAsync(store.undo);
    expect(
      store.state.tasks.firstWhere((t) => t.id == task.id).status,
      task.status,
    );
    expect(store.canUndo, isFalse);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('自定义状态启停与迁移保留任务字段', (t) async {
    await launch(t, 1380, 860);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(() => store.addStatus('等待反馈'));
    final task = store.state.tasks.first;
    await t.runAsync(() => store.moveTask(task.id, 'custom:等待反馈'));
    await t.runAsync(() => store.toggleStatus('custom:等待反馈'));
    expect(store.state.displayStatuses, contains('custom:等待反馈'));
    await t.runAsync(() => store.deleteStatus('custom:等待反馈', 'doing'));
    expect(
      store.state.tasks.firstWhere((t) => t.id == task.id).title,
      task.title,
    );
    expect(store.state.statuses, isNot(contains('custom:等待反馈')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('看板跨列拖放保存并可撤销', (t) async {
    await launch(t, 1380, 860);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final task = store.visible.firstWhere((t) => t.status == 'todo');
    await t.runAsync(() async {
      await t.drag(find.text(task.title), const Offset(500, 0));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (store.busy && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(store.busy, isFalse, reason: '拖动保存必须完成');
    });
    await t.pumpAndSettle();
    expect(
      store.state.tasks.firstWhere((x) => x.id == task.id).status,
      'doing',
    );
    await t.runAsync(store.undo);
    await t.pumpAndSettle();
    expect(store.state.tasks.firstWhere((x) => x.id == task.id).status, 'todo');
    expect(t.takeException(), isNull);
  });
  testWidgets('甘特整条拖动按自然日落库与撤销', (t) async {
    final sample = store.visible.firstWhere((x) => x.status == 'todo');
    final fixed = sample.patch({
      'due': dayString(beijingDay().add(const Duration(days: 3))),
      'startDate': dayString(beijingDay()),
    });
    await t.runAsync(
      () => store.commit(store.state.copy(tasks: [fixed]), '甘特拖动合成数据'),
    );
    await t.runAsync(() => store.preference('viewMode', 'gantt'));
    await launch(t, 1380, 860);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final task = store.visible.firstWhere(
      (x) => x.status == 'todo' && x.due.isNotEmpty,
    );
    final before = parseDay(task.due)!;
    await t.runAsync(() async {
      await t.drag(find.text(task.title).last, const Offset(64, 0));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (store.busy && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(store.busy, isFalse, reason: '拖动保存必须完成');
    });
    await t.pumpAndSettle();
    final updated = store.state.tasks.firstWhere((x) => x.id == task.id);
    expect(updated.due, dayString(before.add(const Duration(days: 1))));
    expect(updated.startDate, isNotNull);
    await t.runAsync(store.undo);
    await t.pumpAndSettle();
    expect(
      store.state.tasks.firstWhere((x) => x.id == task.id).startDate,
      task.startDate,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('搜索输入N不会新建；日历查看日期不能清除', (t) async {
    await launch(t, 1380, 860);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final search = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '搜索任务标题与说明',
    );
    await t.tap(search);
    await t.sendKeyEvent(LogicalKeyboardKey.keyN);
    await t.pumpAndSettle();
    expect(find.text('新建任务'), findsNothing);
    await t.runAsync(() => store.preference('viewMode', 'calendar'));
    await t.pumpAndSettle();
    await t.tap(find.byType(DateField));
    await t.pumpAndSettle();
    expect(find.byType(DatePopover), findsOneWidget);
    expect(find.text('清除'), findsNothing);
    await capture(t, 'light-date-popover');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(DatePopover), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('日历日周月子模式和持久化无溢出', (t) async {
    await t.runAsync(() => store.preference('viewMode', 'calendar'));
    await launch(t, 1020, 640);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final mode in ['day', 'week', 'month']) {
      await t.runAsync(() => store.preference('calendarMode', mode));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: mode);
    }
    expect(
      (await t.runAsync(
        () => SpaceRepository(directory).load(),
      ))!.settings['calendarMode'],
      'month',
    );
  });
  testWidgets('图文格式与上传附件保存重开，日期清除不生成伪排期', (t) async {
    final file = File('${directory.path}/中文附件.txt');
    await t.runAsync(() => file.writeAsString('独立附件内容'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DesktopHost.channel, (call) async {
          if (call.method == 'openFiles') return [file.path];
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DesktopHost.channel, null),
    );
    await launch(t, 1380, 860);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.tap(
      find.byWidgetPredicate(
        (w) => w is IconButtonS && w.label == '新建任务（⌘N / N）',
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '下一步要做什么？',
      ),
      '图文附件回归',
    );
    await t.ensureVisible(find.byType(DateField).last);
    await t.tap(find.byType(DateField).last);
    await t.pumpAndSettle();
    await t.tap(find.text('明天').last);
    await t.pumpAndSettle();
    await t.tap(find.byType(DateField).last);
    await t.pumpAndSettle();
    await t.tap(find.text('清除').last);
    await t.pumpAndSettle();
    final editor = t.widget<q.QuillEditor>(find.byType(q.QuillEditor));
    editor.controller.replaceText(
      0,
      0,
      '加粗与下划线',
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    await t.pumpAndSettle();
    expect(find.text('加粗'), findsNothing);
    expect(find.text('下划线'), findsNothing);
    editor.controller.formatText(0, 2, q.Attribute.bold);
    editor.controller.formatText(0, 2, q.Attribute.underline);
    await t.ensureVisible(find.text('上传附件'));
    await t.runAsync(() async {
      await t.tap(find.text('上传附件'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await t.pumpAndSettle();
    expect(find.text('中文附件.txt'), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.text('创建任务'));
      final until = DateTime.now().add(const Duration(seconds: 10));
      while (store.busy && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pumpAndSettle();
    final saved = (await t.runAsync(
      () => SpaceRepository(directory).load(),
    ))!.tasks.firstWhere((x) => x.title == '图文附件回归');
    expect(saved.due, isEmpty);
    expect(saved.startDate, isNull);
    expect(utf8.decode(saved.attachments.single.data), '独立附件内容');
    final runs = FlatRtfd.decode(base64Decode(saved.richDescription!));
    expect(
      runs.where((r) => r.bold && r.underline).map((r) => r.text).join(),
      '加粗',
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('卡片等高、单行省略、分类日期同排；流光无需悬停', (t) async {
    final first = store.state.tasks.first;
    await t.runAsync(
      () => store.commit(
        store.state.copy(
          tasks: [
            first.patch({'title': '长标题' * 20, 'description': '长说明\n' * 40}),
            ...store.state.tasks.skip(1),
          ],
        ),
        '布局数据',
      ),
    );
    await launch(t, 1020, 860);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final cards = find.byType(TaskCard);
    final heights = [
      for (final e in cards.evaluate())
        t.getSize(find.byWidget(e.widget)).height,
    ];
    expect(heights.toSet().length, 1);
    final longTitle = t.widget<Text>(find.text('长标题' * 20));
    expect(longTitle.maxLines, 1);
    expect(longTitle.softWrap, false);
    expect(longTitle.overflow, TextOverflow.ellipsis);
    final card = cards.first;
    final category = find.descendant(
      of: card,
      matching: find.byType(CategoryLabel),
    );
    final due = find.descendant(
      of: card,
      matching: find.byWidgetPredicate(
        (w) => w is SpaceIcon && w.name == 'calendar',
      ),
    );
    expect((t.getCenter(category).dy - t.getCenter(due).dy).abs(), lessThan(3));
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await t.pump();
    final before = t.widget<CardFlow>(find.byType(CardFlow).first).time;
    await t.pump(const Duration(milliseconds: 150));
    expect(
      t.widget<CardFlow>(find.byType(CardFlow).first).time,
      greaterThan(before),
    );
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('项目管理入口、改名及停用；菜单使用独立浮层', (t) async {
    await launch(t, 1380, 860);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.tap(
      find.byWidgetPredicate((w) => w is IconButtonS && w.label == '项目管理'),
    );
    await t.pumpAndSettle();
    final project = store.state.projects.single;
    await t.tap(
      find.byWidgetPredicate(
        (w) => w is IconButtonS && w.label == '编辑项目名称：${project.name}',
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, '改名后的项目');
    await t.runAsync(() async {
      await t.tap(find.text('保存名称'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await t.pumpAndSettle();
    expect(store.state.projects.single.name, '改名后的项目');
    await t.runAsync(() async {
      await t.tap(
        find.byWidgetPredicate(
          (w) => w is IconButtonS && w.label == '停用项目：改名后的项目',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await t.pumpAndSettle();
    expect(store.state.projects.single.disabled, isTrue);
    await capture(t, 'light-project-management');
    await t.tap(find.text('完成').last);
    await t.pumpAndSettle();
    await t.tap(
      find
          .byWidgetPredicate((w) => w is IconButtonS && w.label == '任务操作')
          .first,
    );
    await t.pumpAndSettle();
    expect(find.byType(PopupSurface), findsOneWidget);
    await capture(t, 'light-task-menu');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('粘贴图像保存重开不生成附件', (t) async {
    final imageBytes = (await t.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(2, 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return data!.buffer.asUint8List();
    }))!;
    await launch(t, 1380, 860);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.tap(
      find.byWidgetPredicate(
        (w) => w is IconButtonS && w.label == '新建任务（⌘N / N）',
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '下一步要做什么？',
      ),
      '仅内嵌图片',
    );
    final editor = t.widget<q.QuillEditor>(find.byType(q.QuillEditor));
    final encoded = await editor
        .controller
        .config
        // Quill exposes clipboard hooks through its experimental config.
        // ignore: experimental_member_use
        .clipboardConfig!
        .onImagePaste!(imageBytes);
    editor.controller.replaceText(
      0,
      0,
      q.BlockEmbed.image(encoded!),
      const TextSelection.collapsed(offset: 1),
    );
    await t.pumpAndSettle();
    // Exercise both desktop clipboard routes in addition to Quill's image hook.
    final clipboardFile = File('${directory.path}/clipboard.png');
    await t.runAsync(() => clipboardFile.writeAsBytes(imageBytes));
    var filePaste = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DesktopHost.channel, (call) async {
          if (call.method == 'clipboardFiles') {
            return filePaste ? [clipboardFile.path] : <String>[];
          }
          if (call.method == 'clipboardImage') return imageBytes;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DesktopHost.channel, null),
    );
    for (final fromFile in [false, true]) {
      filePaste = fromFile;
      // ignore: experimental_member_use
      expect(
        await t.runAsync(
          // ignore: experimental_member_use
          () => editor.controller.config.clipboardConfig!.onClipboardPaste!(),
        ),
        isTrue,
      );
      await t.pumpAndSettle();
    }

    await t.runAsync(() async {
      await t.tap(find.text('创建任务'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await t.pumpAndSettle();
    final saved = (await t.runAsync(
      () => SpaceRepository(directory).load(),
    ))!.tasks.firstWhere((x) => x.title == '仅内嵌图片');
    expect(saved.attachments, isEmpty);
    expect(
      FlatRtfd.decode(
        base64Decode(saved.richDescription!),
      ).where((r) => r.image != null).length,
      3,
    );
    expect(t.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    testWidgets('${dark ? '暗' : '亮'}主题紧凑表单与下拉浮层层次', (t) async {
      await t.runAsync(() => store.preference('dark', '$dark'));
      await launch(t, 1020, 640);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.tap(
        find.byWidgetPredicate(
          (w) => w is IconButtonS && w.label == '新建任务（⌘N / N）',
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('任务说明 / 可选'), findsNothing);
      expect(find.text('支持图文混排'), findsNothing);
      expect(find.text('新建'), findsOneWidget);
      await capture(t, '${dark ? 'dark' : 'light'}-compact-editor');
      await t.tap(
        find.byWidgetPredicate((w) => w is SpaceSelect && w.label == '所属分类'),
      );
      await t.pumpAndSettle();
      expect(find.byType(PopupSurface), findsOneWidget);
      await capture(t, '${dark ? 'dark' : 'light'}-editor-options');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('空标题错误显示在标题下并保留草稿', (t) async {
    await launch(t, 1380, 860);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.tap(
      find.byWidgetPredicate(
        (w) => w is IconButtonS && w.label == '新建任务（⌘N / N）',
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('创建任务'));
    await t.pumpAndSettle();
    expect(find.text('请输入任务标题。'), findsOneWidget);
    expect(store.state.tasks.length, 9);
    expect(store.error, isNull);
    final input = t.widget<SpaceInput>(
      find.byWidgetPredicate((w) => w is SpaceInput && w.label == '任务标题'),
    );
    expect(input.invalid, isTrue);
    final decoration = find.descendant(
      of: find.byWidgetPredicate((w) => w is SpaceInput && w.label == '任务标题'),
      matching: find.byType(InputDecorator),
    );
    expect(t.getSize(decoration).height, 40);
    final editable = find.descendant(
      of: decoration,
      matching: find.byType(EditableText),
    );
    expect(InputDecorator.containerOf(t.element(editable))!.size.height, 40);
    expect(input.focusNode!.hasFocus, isTrue);
    expect(t.takeException(), isNull);
  });
}
