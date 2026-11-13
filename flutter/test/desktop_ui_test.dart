import 'dart:convert';
import 'dart:io';
import 'support/file_preview.dart';
import 'dart:ui' show CheckedState;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/invoices.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/main.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/invoice_details.dart';
import 'package:space_flutter/ui/invoice_workspace.dart';
import 'package:space_flutter/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SpaceStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('space-desktop-ui-');
    store = SpaceStore(SpaceRepository(directory));
    await store.initialize();
    await store.commit(demoState(), '演示数据');
    await store.reload();
    store.notice = null;
  });
  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  void narrowWindow(WidgetTester t) {
    t.view.physicalSize = const Size(1020, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  testWidgets('窄窗口四种任务视图在概览展开及收起时都能直接切换', (t) async {
    narrowWindow(t);
    await t.runAsync(
      () => store.preferences({
        'navCollapsed': 'false',
        'overviewCollapsed': 'false',
      }),
    );
    await t.pumpWidget(SpaceApp(store: store));
    await t.pumpAndSettle();
    final title = find.byKey(const ValueKey('workspace-titlebar'));
    final sidebar = find.byKey(const ValueKey('navigation-sidebar'));
    expect(t.getSize(title).height, 40);
    expect(t.getSize(sidebar).width, 224);
    for (final collapsed in [false, true]) {
      await t.runAsync(
        () => store.preference('overviewCollapsed', '$collapsed'),
      );
      await t.pumpAndSettle();
      for (final mode in ['board', 'list', 'gantt', 'calendar']) {
        final button = find.byWidgetPredicate(
          (w) => w is IconButtonS && w.icon == mode && w.label.endsWith('视图'),
        );
        expect(button.hitTestable(), findsOneWidget);
        expect(t.getTopLeft(button).dy, greaterThan(t.getRect(title).bottom));
        await t.runAsync(() async {
          await t.tap(button);
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (store.busy && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(store.busy, isFalse);
        });
        await t.pumpAndSettle();
        expect(store.view, mode);
        expect(t.widget<IconButtonS>(button).selected, isTrue);
      }
    }
  });

  testWidgets('任务、工具和发票标题栏仅显示目标主题图标', (t) async {
    narrowWindow(t);
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await t.runAsync(() => store.preference('appearance', 'system'));
    await t.pumpWidget(SpaceApp(store: store));
    await t.pumpAndSettle();

    for (final (area, titleKey) in const [
      (SpaceArea.tasks, 'workspace-titlebar'),
      (SpaceArea.tools, 'tools-titlebar'),
      (SpaceArea.invoices, 'invoices-titlebar'),
    ]) {
      await t.runAsync(() async {
        store.openArea(area);
        await t.pump();
        if (area != SpaceArea.invoices) return;
        final emptyLedger = find.text('拖入发票，开始建立台账');
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (emptyLedger.evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await t.pump();
        }
        expect(emptyLedger, findsOneWidget);
      });
      await t.pumpAndSettle();
      final toggle = find.descendant(
        of: find.byKey(ValueKey(titleKey)),
        matching: find.byType(ThemeToggle),
      );
      final icon = find.descendant(
        of: toggle,
        matching: find.byType(SpaceIcon),
      );
      expect(t.getSize(toggle), const Size(32, 32));
      expect(t.widget<SpaceIcon>(icon).name, 'moon');
      await t.tap(find.byTooltip('切换到暗色主题'));
      await t.pumpAndSettle();
      expect(store.dark, isTrue);
      expect(t.widget<SpaceIcon>(icon).name, 'sun');
      await t.tap(find.byTooltip('切换到明亮主题'));
      await t.pumpAndSettle();
      expect(store.dark, isFalse);
      expect(store.appearance, 'system');
      expect(t.widget<SpaceIcon>(icon).name, 'moon');
    }
  });

  testWidgets('发票台账圆形全选支持部分选中、空格和窄窗口滚动', (t) async {
    narrowWindow(t);
    final session = InvoiceSession(store.repository)
      ..ledger = InvoiceLedger(
        [
          for (var i = 0; i < 24; i++)
            InvoiceEntry(
              '$i',
              InvoiceFile('$i', '发票 $i.pdf', '/tmp/space-invoice-$i.pdf'),
              const [],
              InvoiceInfo(number: '000$i', cents: 1200 + i),
            ),
        ],
        {for (final p in store.state.projects) p.id: p.name},
      );
    addTearDown(session.dispose);
    final semantics = t.ensureSemantics();
    store.openArea(SpaceArea.invoices);
    await t.pumpWidget(
      MaterialApp(
        theme: spaceTheme(false),
        darkTheme: spaceTheme(true),
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(left: 248),
            child: InvoiceWorkspace(
              store: store,
              session: session,
              showTools: false,
              filterAnchor: GlobalKey(),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final all = find.byTooltip('全选当前结果');
    final first = find.byTooltip('选择 发票 0.pdf');
    expect(t.getSize(all), const Size(32, 32));
    expect(t.widget<Text>(find.text('金额')).textAlign, TextAlign.right);
    expect(t.widget<Text>(find.text('12.00')).textAlign, TextAlign.right);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: t.getCenter(first));
    await t.pump();
    await mouse.down(t.getCenter(first));
    await t.pump(const Duration(milliseconds: 100));
    await mouse.up();
    await mouse.removePointer();
    await t.pumpAndSettle();
    expect(session.selected, {'0'});
    expect(
      t
          .getSemantics(find.bySemanticsLabel('全选当前结果'))
          .getSemanticsData()
          .flagsCollection
          .isChecked,
      CheckedState.mixed,
    );
    semantics.dispose();
    final hitTarget = find.descendant(of: all, matching: find.byType(InkWell));
    final inkChild = t.widget<InkWell>(hitTarget).child!;
    Focus.of(t.element(find.byWidget(inkChild))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(session.selected.length, 24);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(session.selected, isEmpty);

    final table = find.byType(SingleChildScrollView).first;
    await t.drag(table, const Offset(-240, 0));
    await t.pumpAndSettle();
    expect(
      t.widget<SingleChildScrollView>(table).controller!.offset,
      greaterThan(0),
    );
    await t.drag(find.byType(ListView), const Offset(0, -280));
    await t.pumpAndSettle();
    expect(
      t.widget<ListView>(find.byType(ListView)).controller!.offset,
      greaterThan(0),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('发票编辑可用键盘选择任务项目并保存', (t) async {
    narrowWindow(t);
    final session = InvoiceSession(store.repository);
    addTearDown(session.dispose);
    final file = File('${directory.path}/演示发票.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
    await t.runAsync(() => session.import([file.path]));
    final id = session.ledger!.entries.single.id;
    final project = store.state.projects.single;
    await t.pumpWidget(
      MaterialApp(
        theme: spaceTheme(false),
        home: Scaffold(
          body: Builder(
            builder: (context) => SpaceButton(
              onPressed: () => showInvoiceDetails(context, store, session, id),
              child: const Text('开发票'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('开发票'));
    await t.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      final preview = find.byType(Image);
      while (preview.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await t.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(preview, findsOneWidget);
    });
    await t.pumpAndSettle();
    final picker = find.byWidgetPredicate(
      (w) => w is SpaceSelect && w.label == '选择报销项目',
    );
    await t.scrollUntilVisible(
      picker,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(picker);
    await t.pumpAndSettle();
    expect(find.text(project.name), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(t.widget<SpaceSelect>(picker).value, project.id);
    await t.runAsync(() async {
      await t.tap(find.text('保存更改'));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (session.ledger!.entries.single.info.project != project.id &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await t.pumpAndSettle();
    // 2.3.2 起保存成功后详情自动关闭，提示进入台账会话通知。
    expect(find.byTooltip('关闭发票详情'), findsNothing);
    expect(session.notice, '发票信息已保存');
    final persisted = await t.runAsync(session.repo.load);
    expect(persisted!.entries.single.info.project, project.id);
    expect(store.modal, isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('点击详情左侧空白关闭，有修改时先询问是否保存', (t) async {
    narrowWindow(t);
    final session = InvoiceSession(store.repository);
    addTearDown(session.dispose);
    final file = File('${directory.path}/空白关闭.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
    await t.runAsync(() => session.import([file.path]));
    final id = session.ledger!.entries.single.id;
    await t.pumpWidget(
      MaterialApp(
        theme: spaceTheme(false),
        home: Scaffold(
          body: Builder(
            builder: (context) => SpaceButton(
              onPressed: () => showInvoiceDetails(context, store, session, id),
              child: const Text('开发票'),
            ),
          ),
        ),
      ),
    );
    final sheet = find.byKey(const ValueKey('invoice-details-sheet'));
    await t.tap(find.text('开发票'));
    await t.pumpAndSettle();
    await settleFilePreview(t);
    expect(sheet, findsOneWidget);
    await t.tap(find.byKey(const ValueKey('invoice-details-dismiss-area')));
    await t.pumpAndSettle();
    expect(find.text('保存修改？'), findsNothing, reason: '无修改不应询问');
    expect(sheet, findsNothing, reason: '没有修改时点击左侧空白直接关闭');
    expect(store.modal, isFalse);

    await t.tap(find.text('开发票'));
    await t.pumpAndSettle();
    await settleFilePreview(t);
    final titleInput = find.descendant(
      of: find.byKey(const ValueKey('invoice-field-发票名称')),
      matching: find.byType(TextField),
    );
    await t.enterText(titleInput, '手工修改的票面名称');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('invoice-details-dismiss-area')));
    await t.pumpAndSettle();
    expect(find.text('保存修改？'), findsOneWidget);
    expect(find.text('不保存'), findsOneWidget);
    expect(sheet, findsOneWidget, reason: '询问期间详情不关闭');
    // 详情底部也有「取消」，询问弹窗里的按钮按 Dialog 范围定位。
    Future<void> tapDialog(String label) => t.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text(label)),
    );
    await tapDialog('取消');
    await t.pumpAndSettle();
    expect(sheet, findsOneWidget, reason: '取消后继续编辑');
    await t.tap(find.byKey(const ValueKey('invoice-details-dismiss-area')));
    await t.pumpAndSettle();
    expect(find.text('保存修改？'), findsOneWidget);
    await tapDialog('不保存');
    await t.pumpAndSettle();
    expect(sheet, findsNothing, reason: '放弃修改后关闭详情');
    final persisted = await t.runAsync(session.repo.load);
    expect(
      persisted!.entries.single.info.title,
      isNot('手工修改的票面名称'),
      reason: '放弃的修改不应落库',
    );
    // 2.3.2 自动识别的 OCR worker 有 25 秒空闲定时器，快进后收尾。
    await t.pump(const Duration(seconds: 26));
    expect(t.takeException(), isNull);
  });
}
