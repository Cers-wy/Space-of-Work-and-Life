import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/invoices.dart';
import 'package:space_flutter/core/invoice_recognition.dart';
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/invoice_batch_update.dart';
import 'package:space_flutter/ui/invoice_workspace.dart';
import 'package:space_flutter/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SpaceStore store;
  late InvoiceSession session;
  late List<InvoiceEntry> entries;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('space-batch-update-');
    store = SpaceStore(SpaceRepository(directory));
    await store.initialize();
    await store.commit(
      store.state.copy(projects: [Project('trip', '差旅')]),
      'Fixture',
    );
    await store.reload();
    session = InvoiceSession(store.repository);
    final file = File('${directory.path}/fixture.pdf')
      ..writeAsStringSync('%PDF-1.7\nfixture');
    await session.repo.importFiles([file.path, file.path, file.path]);
    await session.refresh();
    for (final e in session.ledger!.entries) {
      await session.repo.save(
        e.id,
        const InvoiceInfo(
          title: '原票名',
          number: '00001234',
          issued: '2026-10-02',
          spent: '2026-10-01',
          month: '2026-10',
          purpose: '原备注',
          cents: 10600,
          reimbursed: true,
        ),
      );
      await session.repo.recognitionError(e.id, 'Fixture');
    }
    await session.refresh();
    entries = session.ledger!.entries;
  });
  tearDown(() async {
    session.dispose();
    store.dispose();
    await directory.delete(recursive: true);
  });

  test('空白不更新，去重后只更新选中项的非空报销字段', () async {
    await session.repo.importFiles([
      entries.first.original.path,
    ], attachmentTo: entries.first.id);
    final ids = [entries[0].id, entries[1].id, entries[0].id, 'removed'];
    expect(
      await session.repo.updateReimbursement(
        ids,
        const InvoiceReimbursementPatch(
          month: '  ',
          project: '',
          purpose: '\n ',
        ),
      ),
      0,
    );
    expect(
      await session.repo.updateReimbursement(
        ids,
        const InvoiceReimbursementPatch(
          month: ' 2026-11 ',
          purpose: ' 新备注\n第二行 ',
        ),
      ),
      2,
    );
    final result = await session.repo.load();
    for (final e in result.entries) {
      expect(e.info.month, e.id == entries[2].id ? '2026-10' : '2026-11');
      expect(e.info.purpose, e.id == entries[2].id ? '原备注' : '新备注\n第二行');
      expect(e.info.project, '');
      expect(e.info.number, '00001234');
      expect(e.info.title, '原票名');
      expect(e.info.cents, 10600);
      expect(e.info.spent, '2026-10-01');
      expect(e.info.reimbursed, isTrue);
    }
    expect(result.entries.first.attachments, hasLength(1));
    expect(
      await session.repo.updateReimbursement([
        entries[0].id,
      ], const InvoiceReimbursementPatch(project: 'trip')),
      1,
    );
    expect((await session.repo.load()).entries.first.info.project, 'trip');
  });

  test('无效月份或已删除项目不产生部分更新', () async {
    for (final month in ['2026-13', '2026-1', '0000-01', 'abc']) {
      await expectLater(
        session.repo.updateReimbursement(
          entries.map((e) => e.id).toList(),
          InvoiceReimbursementPatch(month: month, purpose: '不应写入'),
        ),
        throwsStateError,
      );
    }
    await expectLater(
      session.repo.updateReimbursement(
        entries.map((e) => e.id).toList(),
        const InvoiceReimbursementPatch(month: '2026-11', project: 'deleted'),
      ),
      throwsStateError,
    );
    for (final e in (await session.repo.load()).entries) {
      expect(e.info.month, '2026-10');
      expect(e.info.purpose, '原备注');
    }
  });

  test('后台识别期间更新月份和备注，迟到识别不会覆盖', () async {
    final started = Completer<void>(), gate = Completer<void>();
    session.recognizeFile = (file, {required preferOcr}) async {
      started.complete();
      await gate.future;
      return const InvoiceRecognition({
        'number': '99999999',
        'issued': '2026-09-01',
      }, '');
    };
    final job = session.recognizeSelected([entries.first.id]);
    await started.future;
    expect(session.busy, isFalse);
    expect(
      await session.updateReimbursement(
        [entries.first.id],
        const InvoiceReimbursementPatch(
          month: '2026-12',
          project: 'trip',
          purpose: '批量手工备注',
        ),
      ),
      isTrue,
    );
    gate.complete();
    await job;
    final saved = (await session.repo.load()).entries.first.info;
    expect(saved.month, '2026-12');
    expect(saved.project, 'trip');
    expect(saved.purpose, '批量手工备注');
    expect(saved.number, '99999999');
    expect(session.notice, contains('已更新 1 张发票'));
  });

  Future<void> open(
    WidgetTester tester, {
    bool dark = false,
    double width = 800,
  }) async {
    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [Palette(dark)]),
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showInvoiceBatchUpdate(
                c,
                store,
                session,
                entries.take(2).map((e) => e.id).toList(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('弹窗留空禁用、无效值报错、只填月份更新且刷新列表', (tester) async {
    await open(tester);
    SpaceButton submit() => tester.widget<SpaceButton>(
      find.byKey(const ValueKey('invoice-batch-submit')),
    );
    expect(submit().onPressed, isNull);
    final month = find.descendant(
      of: find.byKey(const ValueKey('invoice-batch-month')),
      matching: find.byType(TextField),
    );
    await tester.enterText(month, '2026-99');
    await tester.pump();
    await tester.runAsync(
      () => (submit().onPressed! as Future<void> Function())(),
    );
    await tester.pumpAndSettle();
    expect(find.text('报销月份请输入有效的 YYYY-MM'), findsOneWidget);
    expect(find.text('批量更新发票'), findsOneWidget);
    await tester.enterText(month, '2026-12');
    await tester.pump();
    await tester.runAsync(
      () => (submit().onPressed! as Future<void> Function())(),
    );
    await tester.pumpAndSettle();
    expect(find.text('批量更新发票'), findsNothing);
    expect(session.ledger!.entries.first.info.month, '2026-12');
    expect(session.ledger!.entries.first.info.purpose, '原备注');
    expect(session.ledger!.entries.last.info.month, '2026-10');
    expect(tester.takeException(), isNull);
  });

  testWidgets('暗色窄窗可取消，重新打开字段为空且数据不变', (tester) async {
    await open(tester, dark: true, width: 360);
    final input = find.descendant(
      of: find.byKey(const ValueKey('invoice-batch-purpose')),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, '取消的内容');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, '');
    expect(session.ledger!.entries.first.info.purpose, '原备注');
    expect(tester.takeException(), isNull);
  });

  testWidgets('标题栏更新按钮纯图标、无选择禁用、选中可用', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    store.openArea(SpaceArea.invoices);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [const Palette(false)]),
        home: Scaffold(
          body: InvoiceWorkspace(
            store: store,
            session: session,
            showTools: false,
            filterAnchor: GlobalKey(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byWidgetPredicate(
      (w) => w is IconButtonS && w.label == '批量更新发票',
    );
    expect(tester.widget<IconButtonS>(button).onPressed, isNull);
    final ledger = tester
        .widget<InvoiceWorkspace>(find.byType(InvoiceWorkspace))
        .session;
    ledger.update(() => ledger.selected.add(entries.first.id));
    await tester.pump();
    expect(tester.widget<IconButtonS>(button).onPressed, isNotNull);
    expect(
      find.descendant(of: button, matching: find.byType(Text)),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('窄窗口标题栏保持图标入口且不溢出', (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [const Palette(false)]),
        home: Scaffold(
          body: InvoiceWorkspace(
            store: store,
            session: session,
            showTools: false,
            filterAnchor: GlobalKey(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is IconButtonS && w.label == '批量更新发票'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
