import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:space_flutter/core/invoices.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/main.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/theme.dart';

/// 2.3.1 界面改动的可视化验收：默认模块、分类标签常态、列宽提示线贴边、
/// 发票列表整行选中，以及发票详情定宽 520 后「发票与附件」单入口、滚轮切换与
/// 两列票面信息，以及报销信息的日期、项目、已报销与备注重排。
/// 2026-11-12 同步 2.3.2：票面信息仍为两列，新增「发票名称」与「更多票面字段」
/// 折叠区；个人备注改为两行输入。截图写入 verification/screenshots/2.3.2。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final shot = GlobalKey();
  late Directory dir;
  late SpaceStore store;

  Future<void> loadFont() async {
    final file = File('../work/flutter-qa/test-fonts/Chinese-glyphs.ttf');
    if (!file.existsSync()) return;
    final loader = FontLoader('PingFang SC')
      ..addFont(file.readAsBytes().then((b) => ByteData.sublistView(b)));
    await loader.load();
  }

  setUp(() async {
    await loadFont();
    dir = await Directory.systemTemp.createTemp('space-v231-');
    store = SpaceStore(SpaceRepository(dir));
    await store.initialize();
    await store.commit(demoState(), '2.3.1 验收数据');
    await store.reload();
    store.notice = null;
  });

  tearDown(() async {
    store.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> launch(
    WidgetTester t, {
    Size size = const Size(1280, 820),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1;
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await t.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: SpaceApp(store: store),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> capture(WidgetTester t, String name) async {
    await t.runAsync(() async {
      final boundary =
          shot.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = Directory('verification/screenshots/2.3.2');
      await out.create(recursive: true);
      await File('${out.path}/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> waitFor(WidgetTester t, Finder finder) async {
    await t.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await t.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
  }

  Future<void> waitGone(WidgetTester t, Finder finder) async {
    await t.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (finder.evaluate().isNotEmpty &&
          DateTime.now().isBefore(deadline)) {
        await t.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
  }

  String receipt(String path) {
    final page = img.Image(width: 880, height: 1240);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      page,
      x1: 40,
      y1: 44,
      x2: 840,
      y2: 200,
      color: img.ColorRgb8(236, 241, 249),
    );
    img.fillRect(
      page,
      x1: 40,
      y1: 236,
      x2: 600,
      y2: 268,
      color: img.ColorRgb8(206, 211, 219),
    );
    for (var i = 0; i < 17; i++) {
      final y = 330 + i * 44;
      img.fillRect(
        page,
        x1: 40,
        y1: y,
        x2: i.isEven ? 840 : 660,
        y2: y + 12,
        color: img.ColorRgb8(230, 233, 238),
      );
    }
    img.fillRect(
      page,
      x1: 40,
      y1: 1150,
      x2: 340,
      y2: 1172,
      color: img.ColorRgb8(198, 64, 64),
    );
    File(path).writeAsBytesSync(img.encodePng(page));
    return path;
  }

  testWidgets('默认进入任务模块，标题栏分类标签不显示选中态', (t) async {
    for (final dark in [false, true]) {
      await t.runAsync(
        () => store.preferences({
          'dark': '$dark',
          'viewMode': 'board',
          'navCollapsed': 'false',
          'overviewCollapsed': 'true',
        }),
      );
      await launch(t);
      expect(store.area.name, 'tasks');
      final quick = find.byWidgetPredicate(
        (w) =>
            w is SpaceButton &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('category-quick-'),
      );
      expect(quick, findsWidgets);
      for (final button in t.widgetList<SpaceButton>(quick)) {
        expect(button.selected, isFalse, reason: '分类标签不能出现选中态');
      }
      // 点击后仍不出现选中态，只改变筛选结果。
      await t.tap(quick.first);
      await t.pumpAndSettle();
      for (final button in t.widgetList<SpaceButton>(quick)) {
        expect(button.selected, isFalse);
      }
      await capture(t, 'tasks-default-${dark ? 'dark' : 'light'}');
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('看板列宽提示线贴合列标题栏右边界', (t) async {
    for (final dark in [false, true]) {
      await t.runAsync(
        () => store.preferences({
          'dark': '$dark',
          'viewMode': 'board',
          'navCollapsed': 'false',
          'overviewCollapsed': 'true',
        }),
      );
      await launch(t);
      final status = store.boardStatuses.first;
      final handle = find.byKey(ValueKey('board-resize-$status'));
      expect(handle, findsOneWidget);
      final gesture = await t.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await t.pump();
      await gesture.moveTo(t.getCenter(handle));
      await t.pump();
      final p = Palette(dark);
      final line = find.descendant(
        of: handle,
        matching: find.byKey(const ValueKey('board-resize-line')),
      );
      expect(line, findsOneWidget);
      expect(t.widget<ColoredBox>(line).color, p.accent);
      final column = t.getRect(find.byKey(ValueKey('board-column-$status')));
      final tip = t.getRect(line);
      expect(
        (tip.right - column.right).abs(),
        lessThan(1),
        reason: '提示线最右边界必须与列右边界重合：line=$tip column=$column',
      );
      expect(tip.width, lessThanOrEqualTo(3.5));
      expect(tip.top, column.top);
      expect(tip.height, lessThanOrEqualTo(44.5));
      await capture(t, 'board-resize-line-${dark ? 'dark' : 'light'}');
      await gesture.removePointer();
      await t.pump();
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('发票列表整行选中，详情定宽 520 后单入口预览与两列票面信息', (t) async {
    final repo = InvoiceRepository(store.repository);
    final first = receipt('${dir.path}/滴滴出行-行程单.png');
    final second = receipt('${dir.path}/酒店住宿增值税发票.png');
    await t.runAsync(() => repo.importFiles([first, second]));
    final ledger = (await t.runAsync(repo.load))!;
    final project = store.state.projects.first.id;
    for (final (index, entry) in ledger.entries.indexed) {
      await t.runAsync(
        () => repo.save(
          entry.id,
          InvoiceInfo(
            number: index == 0 ? '0000 1234 5678' : '0000 8765 4321',
            issued: index == 0 ? '2026-10-26' : '2026-10-28',
            seller: index == 0 ? '滴滴出行科技有限公司' : '杭州云栖酒店有限公司',
            sellerTax: '91330106MA2GX8K73B',
            buyer: '杭州云枢科技有限公司',
            buyerTax: '91330106MA2GX8K73B',
            cents: index == 0 ? 8640 : 128000,
            taxCents: index == 0 ? 489 : 7245,
            netCents: index == 0 ? 8151 : 120755,
            spent: index == 0 ? '2026-10-25' : '2026-10-27',
            purpose: index == 0 ? '客户拜访用车' : '客户到访住宿',
            month: '2026-10',
            project: project,
            reimbursed: index == 0,
          ),
        ),
      );
    }
    final loaded = (await t.runAsync(repo.load))!;
    final entry = loaded.entries.first;
    await t.runAsync(
      () => repo.importFiles([
        receipt('${dir.path}/酒店水单-附件.png'),
      ], attachmentTo: entry.id),
    );
    final withAttachment = (await t.runAsync(repo.load))!;
    final target = withAttachment.entries.first;
    expect(target.attachments.length, 1);

    Future<void> theme(WidgetTester t, bool dark) async {
      await t.runAsync(() => store.preferences({'dark': '$dark'}));
      await t.pumpAndSettle();
    }

    // 整行选中：勾选后整行铺满底色，而不是中间一条。
    Future<void> shootRow(WidgetTester t, String suffix) async {
      final checks = find.byWidgetPredicate(
        (w) => w is SpaceCheckbox && w.label.startsWith('选择 '),
      );
      expect(checks, findsNWidgets(2));
      expect(
        t.widgetList<SpaceCheckbox>(checks).first.value,
        isTrue,
        reason: '$suffix 轮勾选未生效',
      );
      final row = find.byKey(ValueKey(target.id));
      expect(t.getRect(row).height, greaterThanOrEqualTo(56));
      final tint = find
          .descendant(of: row, matching: find.byType(AnimatedContainer))
          .first;
      final decoration = t.widget<AnimatedContainer>(tint).decoration;
      expect(decoration, isA<BoxDecoration>());
      expect(
        (decoration! as BoxDecoration).color,
        isNot(Colors.transparent),
        reason: '选中后必须有底色',
      );
      expect(t.getSize(tint), t.getSize(row), reason: '选中底色必须铺满整行，而不是中间一条');
      await capture(t, 'invoice-row-selected-$suffix');
    }

    // 详情：上面是「发票与附件」单入口与预览，下面是两列票面信息。
    Future<void> shootDetails(WidgetTester t, String suffix) async {
      await t.tap(find.byTooltip('查看发票详情').first);
      await t.pumpAndSettle();
      await waitFor(
        t,
        find.byKey(ValueKey('invoice-preview-${target.original.id}')),
      );
      await waitGone(t, find.text('正在加载图片…'));

      final sheet = t.getRect(
        find.byKey(const ValueKey('invoice-details-sheet')),
      );
      expect(
        sheet.width,
        closeTo(520, 0.5),
        reason: '详情面板在 390 基础上再增加 1/3，宽度应为 520',
      );
      expect(find.text('发票与附件'), findsOneWidget);
      expect(find.text('共 2 个'), findsOneWidget, reason: '标题旁显示数量合计');
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'invoice-file-chip-',
              ),
        ),
        findsNothing,
        reason: '附件不再逐个展开成标签页',
      );
      final preview = t.getRect(
        find.byKey(ValueKey('invoice-preview-${target.original.id}')),
      );
      final field = t.getRect(find.text('票面信息'));
      expect(preview.height, greaterThanOrEqualTo(180));
      expect(field.top, greaterThan(preview.bottom), reason: '票面信息在预览下方');

      // 标签在控件上方；2.3.2 票面信息仍为两列：
      // 第一行「发票名称 | 发票号码」，第二行「销售方名称 | 开票日期」。
      final title = find.byKey(const ValueKey('invoice-field-发票名称'));
      final number = find.byKey(const ValueKey('invoice-field-发票号码'));
      final seller = find.byKey(const ValueKey('invoice-field-销售方名称'));
      final issued = find.byKey(const ValueKey('invoice-field-开票日期'));
      for (final key in [title, number, seller, issued]) {
        expect(key, findsOneWidget);
      }
      final titleBox = t.getRect(title);
      final numberBox = t.getRect(number);
      final sellerBox = t.getRect(seller);
      final issuedBox = t.getRect(issued);
      expect(titleBox.top, numberBox.top, reason: '发票名称与发票号码同一行');
      expect(numberBox.left, greaterThan(titleBox.right));
      expect(titleBox.width, closeTo(numberBox.width, 1));
      expect(sellerBox.top, issuedBox.top, reason: '销售方名称与开票日期同一行');
      expect(issuedBox.left, greaterThan(sellerBox.right));
      expect(sellerBox.top, greaterThan(titleBox.bottom), reason: '第二行在第一行下方');
      final label = t.getRect(
        find.descendant(of: title, matching: find.text('发票名称')),
      );
      final input = t.getRect(
        find.descendant(of: title, matching: find.byType(TextField)),
      );
      expect(label.bottom, lessThanOrEqualTo(input.top), reason: '标签在输入上方');

      // 「更多票面字段」默认收起，展开后同样是两列。
      expect(find.text('更多票面字段'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('invoice-field-购买方')),
        findsNothing,
        reason: '更多票面字段默认收起',
      );
      await t.tap(find.text('更多票面字段'));
      await t.pumpAndSettle();
      final sellerTax = t.getRect(
        find.byKey(const ValueKey('invoice-field-销售方社会信用代码')),
      );
      final buyer = t.getRect(find.byKey(const ValueKey('invoice-field-购买方')));
      expect(sellerTax.top, buyer.top, reason: '展开字段成对同行');
      expect(buyer.left, greaterThan(sellerTax.right));
      await t.tap(find.text('更多票面字段'));
      await t.pumpAndSettle();
      await capture(t, 'invoice-details-$suffix');

      // 报销信息：日期在报销项目上方，项目与「已报销」各占半行，备注独占整行。
      await t.ensureVisible(find.text('报销信息'));
      await t.pumpAndSettle();
      final month = find.byKey(const ValueKey('invoice-field-报销月份'));
      final spent = find.byKey(const ValueKey('invoice-field-消费日期'));
      final project = find.byKey(const ValueKey('invoice-field-报销项目'));
      final reimbursed = find.byKey(const ValueKey('invoice-field-是否报销'));
      final purpose = find.byKey(const ValueKey('invoice-field-备注'));
      for (final key in [month, spent, project, reimbursed, purpose]) {
        expect(key, findsOneWidget);
      }
      final monthBox = t.getRect(month);
      final spentBox = t.getRect(spent);
      final projectBox = t.getRect(project);
      final reimbursedBox = t.getRect(reimbursed);
      final purposeBox = t.getRect(purpose);
      expect(monthBox.top, spentBox.top, reason: '报销月份与消费日期同一行');
      expect(spentBox.left, greaterThan(monthBox.right), reason: '消费日期在右半');
      expect(spentBox.width, closeTo(monthBox.width, 1));
      expect(
        monthBox.bottom,
        lessThanOrEqualTo(projectBox.top),
        reason: '日期行移到报销项目上方',
      );
      expect(projectBox.top, reimbursedBox.top, reason: '项目与已报销同一行');
      expect(
        projectBox.width,
        closeTo(monthBox.width, 1),
        reason: '报销项目与报销月份同为半宽',
      );
      expect(
        reimbursedBox.left,
        greaterThan(projectBox.right),
        reason: '标记已报销的复选框在项目右侧',
      );
      expect(purposeBox.top, greaterThan(projectBox.bottom), reason: '备注是最后一行');
      expect(
        purposeBox.width,
        greaterThan(projectBox.width * 1.8),
        reason: '备注占满整行',
      );
      final reimbursedControl = find.byKey(
        const ValueKey('invoice-reimbursed-control'),
      );
      final projectControl = find.byWidgetPredicate(
        (w) => w is SpaceSelect && w.label == '选择报销项目',
      );
      expect(
        t.getCenter(reimbursedControl).dy,
        closeTo(t.getCenter(projectControl).dy, .01),
        reason: '已报销中线与同行项目选择框中线对齐，不能只比较32高输入框',
      );
      expect(projectBox.height, closeTo(reimbursedBox.height, .01));
      final purposeInput = find.descendant(
        of: purpose,
        matching: find.byType(TextField),
      );
      expect(
        t.getSize(purposeInput).height,
        greaterThan(t.getSize(reimbursedControl).height),
        reason: '2.3.2 起个人备注是两行输入，高于 32 的紧凑复选框',
      );
      expect(
        t.widget<SpaceCheckbox>(reimbursedControl).dense,
        isTrue,
        reason: '使用紧凑的圆形复选框与文字标签',
      );
      expect(
        find.descendant(
          of: reimbursed,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                // 圆形指示器本身带装饰，不算输入框式底色。
                (w.decoration! as BoxDecoration).shape != BoxShape.circle,
          ),
        ),
        findsNothing,
        reason: '复选框不套输入框式底色与描边',
      );
      await capture(t, 'invoice-details-reimbursement-$suffix');
      await t.ensureVisible(find.text('票面信息'));
      await t.pumpAndSettle();

      // 预览区滚轮切换文件。
      final area = t.getCenter(
        find.byKey(const ValueKey('invoice-file-preview')),
      );
      t.binding.handlePointerEvent(
        PointerScrollEvent(position: area, scrollDelta: const Offset(0, 120)),
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(ValueKey('invoice-preview-${target.attachments.first.id}')),
        findsOneWidget,
        reason: '向下滚动应切换到下一个文件',
      );
      await waitGone(t, find.text('正在加载图片…'));
      await capture(t, 'invoice-details-attachment-$suffix');

      // 箭头按钮也能来回切换。
      await t.tap(find.byTooltip('上一个文件（预览区滚轮也可切换）'));
      await t.pumpAndSettle();
      expect(
        find.byKey(ValueKey('invoice-preview-${target.original.id}')),
        findsOneWidget,
      );
      await t.tap(find.byTooltip('下一个文件（预览区滚轮也可切换）'));
      await t.pumpAndSettle();
      expect(
        find.byKey(ValueKey('invoice-preview-${target.attachments.first.id}')),
        findsOneWidget,
      );
      await t.tap(find.byTooltip('关闭发票详情'));
      await t.pumpAndSettle();
    }

    await t.runAsync(
      () => store.preferences({
        'dark': 'false',
        'navCollapsed': 'false',
        'overviewCollapsed': 'true',
      }),
    );
    await launch(t);
    store.openArea(SpaceArea.invoices);
    await t.pump();
    await waitFor(t, find.text('滴滴出行-行程单.png'));
    final checks = find.byWidgetPredicate(
      (w) => w is SpaceCheckbox && w.label.startsWith('选择 '),
    );
    await t.tap(checks.first);
    await t.pumpAndSettle();

    await shootRow(t, 'light');
    await shootDetails(t, 'light');
    // 同一棵树内切到深色：选中态保留，同时验证深色下整行底色仍清晰。
    await theme(t, true);
    await shootRow(t, 'dark');
    await shootDetails(t, 'dark');

    // 窄窗口：预览高度收缩，表单区独立滚动，票面信息不溢出。
    t.view.physicalSize = const Size(1020, 640);
    await t.pumpAndSettle();
    await theme(t, false);
    await t.tap(find.byTooltip('查看发票详情').first);
    await t.pumpAndSettle();
    await waitFor(
      t,
      find.byKey(ValueKey('invoice-preview-${target.original.id}')),
    );
    await waitGone(t, find.text('正在加载图片…'));
    expect(
      t.getRect(find.byKey(const ValueKey('invoice-details-sheet'))).width,
      closeTo(520, 0.5),
      reason: '1020 宽窗口仍能完整容纳 520 的详情面板',
    );
    await capture(t, 'invoice-details-compact-light');
    // 2.3.2 自动识别的 OCR worker 有 25 秒空闲回收定时器；在 fake async 中
    // 快进触发并关闭，避免测试结束时的 pending timer 断言（与布局无关）。
    await t.pump(const Duration(seconds: 26));
    expect(t.takeException(), isNull);
  });

  testWidgets('发票合并提供可视化排版、排序与一式两份', (t) async {
    await t.runAsync(
      () => store.preferences({
        'dark': 'false',
        'navCollapsed': 'false',
        'overviewCollapsed': 'true',
      }),
    );
    await launch(t);
    store.openArea(SpaceArea.tools);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('打开发票合并'));
    await t.pumpAndSettle();

    expect(find.text('排版方式'), findsOneWidget);
    for (var count = 1; count <= 4; count++) {
      expect(find.byKey(ValueKey('merge-layout-$count')), findsOneWidget);
    }
    expect(
      find.byWidgetPredicate((w) => w is SpaceSelect && w.label == '排序设置'),
      findsOneWidget,
    );
    final doubleCopy = find.byWidgetPredicate(
      (w) => w is SpaceCheckbox && w.label == '一式两份',
    );
    expect(doubleCopy, findsOneWidget);
    await capture(t, 'invoice-merge-settings-light');

    final gapMode = find.byWidgetPredicate(
      (w) => w is SpaceSelect && w.label == '票间距模式',
    );
    expect(t.widget<SpaceSelect>(gapMode).value, 'auto');
    await t.ensureVisible(gapMode);
    await t.tap(gapMode);
    await t.pumpAndSettle();
    await t.tap(find.text('指定间距').last);
    await t.pumpAndSettle();
    final gapInput = find.byWidgetPredicate(
      (w) => w is SpaceInput && w.label == '票间距',
    );
    expect(gapInput, findsOneWidget);
    await t.ensureVisible(gapInput);
    await t.enterText(
      find.descendant(of: gapInput, matching: find.byType(TextField)),
      '7',
    );
    await t.pumpAndSettle();
    await capture(t, 'invoice-merge-manual-gap-light');
    await t.ensureVisible(gapMode);
    await t.tap(gapMode);
    await t.pumpAndSettle();
    await t.tap(find.text('自动分配').last);
    await t.pumpAndSettle();
    expect(gapInput, findsNothing);

    await t.ensureVisible(doubleCopy);
    await t.tap(doubleCopy);
    await t.pumpAndSettle();
    expect(t.widget<SpaceCheckbox>(doubleCopy).value, isTrue);
    expect(find.textContaining('2 张（一式两份）'), findsWidgets);
    for (final count in [1, 3, 4]) {
      final button = t.widget<SpaceButton>(
        find.byKey(ValueKey('merge-layout-$count')),
      );
      expect(button.onPressed, isNull, reason: '一式两份固定每页 2 张');
    }
    await capture(t, 'invoice-merge-double-light');

    await t.runAsync(() => store.preferences({'dark': 'true'}));
    await t.pumpAndSettle();
    await capture(t, 'invoice-merge-double-dark');
    await t.runAsync(() => store.preferences({'appearance': 'system'}));
    t.view.physicalSize = const Size(1020, 640);
    await t.pumpAndSettle();
    await t.ensureVisible(gapMode);
    await capture(t, 'invoice-merge-gap-compact-system');
    expect(t.takeException(), isNull);
  });
}
