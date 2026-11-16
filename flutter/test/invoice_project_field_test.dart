import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/invoice_details.dart';
import 'package:space_flutter/ui/invoice_workspace.dart';
import 'package:space_flutter/ui/theme.dart';

import 'support/file_preview.dart';

void main() {
  late Directory dir;
  late SpaceStore store;
  late InvoiceSession session;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('space-project-picker-');
    store = SpaceStore(SpaceRepository(dir));
    await store.initialize();
    session = InvoiceSession(store.repository);
    final source = File('${dir.path}/isolated.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
    await session.repo.importFiles([source.path]);
    await session.refresh();
  });
  tearDown(() async {
    session.dispose();
    store.dispose();
    await dir.delete(recursive: true);
  });
  testWidgets(
    'invoice project input is half width, creates only on save, and persists its project',
    (t) async {
      t.view.physicalSize = const Size(1120, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final id = session.ledger!.entries.single.id;
      await t.pumpWidget(
        MaterialApp(
          theme: spaceTheme(false),
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => showInvoiceDetails(c, store, session, id),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await t.runAsync(() => t.tap(find.text('打开')));
        await t.pumpAndSettle();
        await settleFilePreview(t);
      }

      final project = find.byWidgetPredicate(
        (w) => w is SpaceInput && w.label == '报销项目',
      );
      await open();
      await t.ensureVisible(project);
      await t.pumpAndSettle();
      expect(find.byTooltip('管理共用项目'), findsNothing);
      await t.enterText(
        find.descendant(of: project, matching: find.byType(TextField)),
        '隔离新项目',
      );
      expect(store.state.projects.where((p) => p.name == '隔离新项目'), isEmpty);
      await t.tap(find.byTooltip('关闭发票详情'));
      await t.pumpAndSettle();
      await t.tap(find.text('不保存'));
      await t.pumpAndSettle();
      expect(store.state.projects.where((p) => p.name == '隔离新项目'), isEmpty);
      await open();
      await t.ensureVisible(project);
      await t.pumpAndSettle();
      await t.enterText(
        find.descendant(of: project, matching: find.byType(TextField)),
        '隔离新项目',
      );
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(find.text('保存更改'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await t.pumpAndSettle();
      final created = store.state.projects.singleWhere(
        (p) => p.name == '隔离新项目',
      );
      final saved = await t.runAsync(() => session.repo.find(id));
      expect(saved!.info.project, created.id);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
