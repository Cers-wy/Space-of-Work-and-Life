import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/invoices.dart';
import 'package:space_flutter/core/invoice_recognition.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/invoice_workspace.dart';
import 'package:space_flutter/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SpaceStore store;
  late InvoiceSession session;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('space-page-');
    store = SpaceStore(SpaceRepository(directory));
    await store.initialize();
    final db = store.repository.openInvoiceDatabase();
    try {
      db.execute("INSERT INTO projects(id,name) VALUES ('trip','客户差旅')");
      db.execute('BEGIN');
      for (var i = 0; i < 121; i++) {
        db.execute(
          'INSERT INTO invoices(id,title,number,month,project,purpose,cents,reimbursed,recognition) VALUES (?,?,?,?,?,?,?,?,?)',
          [
            '$i',
            '发票 $i',
            '$i',
            i < 60 ? '2026-10' : '2026-11',
            'trip',
            i == 0 ? 'Äpfel 100%_特别' : '备注',
            12345,
            i.isEven ? 1 : 0,
            '{}',
          ],
        );
        db.execute(
          'INSERT INTO invoice_files(id,invoice,name,extension,original) VALUES (?,?,?,?,1)',
          ['$i', '$i', '发票 $i.pdf', 'pdf'],
        );
      }
      db.execute(
        "INSERT INTO invoice_files(id,invoice,name,extension,original) VALUES ('receipt','0','行程单.pdf','pdf',0)",
      );
      db.execute('COMMIT');
    } finally {
      db.close();
    }
    await store.reload();
    session = InvoiceSession(store.repository);
    await session.refresh();
  });
  tearDown(() async {
    session.dispose();
    store.dispose();
    await directory.delete(recursive: true);
  });

  test('SQL分页只返回当前50张，顺序稳定、末页自动收敛，月份来自全库', () async {
    expect(session.ledger!.entries.length, 50);
    expect(session.ledger!.entries.first.id, '120');
    expect(session.ledger!.entries.last.id, '71');
    expect(session.total, 121);
    expect(session.months, ['2026-11', '2026-10']);
    expect(session.pageCount, 3);
    session.selected.add('120');
    await session.goToPage(1);
    expect(session.selected, isEmpty);
    expect(session.ledger!.entries.first.id, '70');
    final last = await session.repo.loadPage(page: 99);
    expect(last.page, 2);
    expect(last.ledger.entries.length, 21);
    expect(last.ledger.entries.last.attachments.single.name, '行程单.pdf');
    for (var i = 0; i < 21; i++) {
      await session.repo.delete('$i');
    }
    await session.goToPage(2);
    expect(session.page, 1);
    expect(session.total, 100);
    expect(session.pageCount, 2);
  });

  test('跨页多条件交集、附件/金额/项目/Unicode搜索与字面特殊字符', () async {
    const query = InvoiceQuery(
      text: 'ÄPFEL 行程单 123.45 客户 100%_',
      month: '2026-10',
      project: 'trip',
      status: 'yes',
    );
    final result = await session.repo.loadPage(query: query);
    expect(result.total, 1);
    expect(result.ledger.entries.single.id, '0');
    expect(result.totalAll, 121);
    expect(
      (await session.repo.loadPage(
        query: const InvoiceQuery(text: "' OR 1=1 --"),
      )).total,
      0,
    );
    expect(
      (await session.repo.loadPage(
        query: const InvoiceQuery(month: '2026-10', status: 'no'),
      )).total,
      30,
    );
    final all = await session.repo.matching(
      const InvoiceQuery(project: 'trip'),
    );
    expect(
      all.entries.length,
      121,
    ); // Explicit full export is not limited to page 1.
    expect((await session.repo.find('0'))!.attachments.length, 1);
    expect(await session.repo.find('deleted'), isNull);
  });

  test('快速筛选只采纳最新查询，重置页码；刷新不覆盖新查询', () async {
    await session.goToPage(2);
    session.update(() => session.query = '不存在');
    session.update(() {
      session.query = '行程单';
      session.month = '2026-10';
    });
    await session.refresh();
    expect(session.page, 0);
    expect(session.total, 1);
    expect(session.filtered.single.id, '0');
    expect(session.pageLoading, isFalse);
    session.update(() {
      session.query = '';
      session.month = '';
    });
    await session.refresh();
    expect(session.total, 121);
    expect(session.ledger!.entries.length, 50);
  });

  test('批量修改离开筛选范围后刷新为正确总数，详情可独立重新读取', () async {
    session.update(() => session.month = '2026-10');
    await session.refresh();
    final id = session.filtered.first.id;
    expect(
      await session.updateReimbursement([
        id,
      ], const InvoiceReimbursementPatch(month: '2026-12')),
      isTrue,
    );
    expect(session.total, 59);
    expect(session.filtered.any((e) => e.id == id), isFalse);
    expect((await session.repo.find(id))!.info.month, '2026-12');
  });

  test('自动识别覆盖非当前页，主动识别无需全量载入', () async {
    final db = store.repository.openInvoiceDatabase();
    db.execute("UPDATE invoices SET recognition='' WHERE id IN ('0','120')");
    db.close();
    final calls = <String>[];
    session.recognizeFile = (file, {required preferOcr}) async {
      calls.add(file.id);
      return const InvoiceRecognition({'seller': '已识别'}, '');
    };
    await session.load();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while ((session.recognizing || calls.length < 2) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(calls.toSet(), {'0', '120'});
    expect(session.ledger!.entries.length, 50);
    expect((await session.repo.find('0'))!.info.seller, '已识别');
    expect(await session.repo.pendingRecognitionIds(), isEmpty);
  });

  testWidgets('翻页按钮沿用图标/提示，窄窗口和文字缩放无溢出', (t) async {
    await t.binding.setSurfaceSize(const Size(720, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    store.openArea(SpaceArea.invoices);
    for (final dark in [false, true]) {
      await t.pumpWidget(
        MaterialApp(
          theme: spaceTheme(dark),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(720, 700),
              textScaler: TextScaler.linear(1.4),
            ),
            child: Scaffold(
              body: InvoiceWorkspace(
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
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.byTooltip('全选当前页'), findsOneWidget);
      final next = find.byTooltip('下一页发票');
      expect(next, findsOneWidget);
      await t.runAsync(() async {
        await t.tap(next);
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (session.pageLoading && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await t.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.runAsync(() => session.goToPage(0));
      await t.pumpAndSettle();
    }
  });
}
