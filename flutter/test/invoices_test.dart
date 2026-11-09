import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/invoice_export.dart';
import 'package:space_flutter/core/invoice_pdf.dart';
import 'package:space_flutter/core/invoices.dart';
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('台账共用任务项目，任务保存、改名及删除不会丢失发票', () async {
    final temp = await Directory.systemTemp.createTemp('space-invoice-test-');
    addTearDown(() => temp.delete(recursive: true));
    final space = SpaceRepository(Directory('${temp.path}/space'));
    final initial = await space.load();
    const project = 'shared-project';
    final task = SpaceTask.create(projectID: project).patch({'title': '已有任务'});
    final taskState = await space.save(
      initial.copy(tasks: [task], projects: [Project(project, '客户差旅')]),
    );
    final invoice = InvoiceRepository(space);
    expect((await invoice.load()).entries, isEmpty);
    expect(File('${invoice.root}/ledger.sqlite').existsSync(), isFalse);

    final original = File('${temp.path}/发票.pdf')
      ..writeAsStringSync('%PDF-1.7\n测试');
    final receipt = File('${temp.path}/行程单.pdf')
      ..writeAsStringSync('%PDF-1.7\n附件');
    final invalid = File('${temp.path}/损坏.pdf')..writeAsStringSync('not pdf');
    final imported = await invoice.importFiles([original.path, invalid.path]);
    expect(imported.count, 1);
    expect(imported.errors.single, contains('损坏.pdf'));
    final entry = (await invoice.load()).entries.single;
    await invoice.save(
      entry.id,
      InvoiceInfo(
        number: '0000123456',
        issued: '2026-11-01',
        spent: '2026-10-31',
        month: '2026-11',
        purpose: '会议 & 接送',
        cents: 12345,
        project: project,
        reimbursed: true,
      ),
    );
    expect(
      (await invoice.importFiles([receipt.path], attachmentTo: entry.id)).count,
      1,
    );

    await space.save(taskState, preferencesOnly: true);
    final updated = await space.load();
    expect(updated.tasks.single.id, task.id);
    final renamed = await space.save(
      updated.copy(projects: [Project(project, '客户出差')]),
    );
    final ledger = await InvoiceRepository(space).load();
    final record = ledger.entries.single;
    expect(record.info.reimbursed, isTrue);
    expect(record.info.amount, '123.45');
    expect(record.info.project, project);
    expect(ledger.projects[record.info.project], '客户出差');
    final attached = record.attachments.single;

    final db = sqlite3.open(space.path, mode: OpenMode.readOnly);
    try {
      expect(db.userVersion, 5);
      expect(db.select('SELECT count(*) AS n FROM invoices').single['n'], 1);
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      db.close();
    }

    final download = '${temp.path}/download.pdf';
    await invoice.saveCopy(record.original, download);
    expect(await File(download).readAsBytes(), await original.readAsBytes());
    await expectLater(
      invoice.saveCopy(record.original, space.path),
      throwsStateError,
    );

    final xlsx = '${temp.path}/台账.xlsx';
    await exportInvoiceSheet(invoice, xlsx, ledger.entries, ledger.projects, [
      InvoiceColumn.number,
      InvoiceColumn.amount,
      InvoiceColumn.purpose,
      InvoiceColumn.attachments,
    ]);
    final archive = ZipDecoder().decodeBytes(
      await File(xlsx).readAsBytes(),
      verify: true,
    );
    final xml = String.fromCharCodes(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(xml, contains('t="inlineStr"'));
    expect(xml, contains('0000123456'));
    expect(xml, contains('<v>123.45</v>'));
    expect(xml, contains('&amp;'));
    expect(xml, isNot(contains('type="formula"')));

    await space.save(
      renamed.copy(
        projects: [],
        tasks: [
          task.patch({'projectID': null}),
        ],
      ),
    );
    expect((await invoice.load()).entries.single.info.project, isEmpty);
    await invoice.removeAttachment(entry.id, attached.id);
    expect(await File(attached.path).exists(), isFalse);
    expect((await invoice.load()).entries.single.attachments, isEmpty);
    await invoice.delete(entry.id);
    expect((await invoice.load()).entries, isEmpty);
    expect(await File(record.original.path).exists(), isFalse);
    expect(await original.exists(), isTrue);
    expect((await space.load()).tasks.single.id, task.id);
  });

  test('旧报销项目迁入共用项目，原件、附件和归属完整保留', () async {
    final temp = await Directory.systemTemp.createTemp('space-invoice-v4-');
    addTearDown(() => temp.delete(recursive: true));
    final space = SpaceRepository(temp);
    final initial = await space.load();
    await space.save(initial.copy(projects: [Project('task-id', 'Roadshow')]));
    final db = sqlite3.open(space.path);
    try {
      db.execute('''
CREATE TABLE invoice_projects (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE);
CREATE TABLE invoices (
id TEXT PRIMARY KEY, number TEXT NOT NULL DEFAULT '', issued TEXT NOT NULL DEFAULT '',
seller TEXT NOT NULL DEFAULT '', spent TEXT NOT NULL DEFAULT '', purpose TEXT NOT NULL DEFAULT '',
month TEXT NOT NULL DEFAULT '', project TEXT REFERENCES invoice_projects(id), cents INTEGER,
reimbursed INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE invoice_files (
id TEXT PRIMARY KEY, invoice TEXT NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
name TEXT NOT NULL, extension TEXT NOT NULL, original INTEGER NOT NULL
);
CREATE INDEX invoice_files_parent ON invoice_files(invoice);
CREATE UNIQUE INDEX invoice_original ON invoice_files(invoice) WHERE original=1;
INSERT INTO invoice_projects VALUES ('old-match','roadshow'), ('old-only','仅用于报销');
INSERT INTO invoices (id,number,project,cents,reimbursed) VALUES
  ('one','0001','old-match',12345,1), ('two','0002','old-only',0,0);
INSERT INTO invoice_files VALUES
  ('one-pdf','one','原件.pdf','pdf',1), ('one-receipt','one','附件.pdf','pdf',0),
  ('two-pdf','two','另一张.pdf','pdf',1);
PRAGMA user_version=4;
''');
    } finally {
      db.close();
    }

    final migrated = await space.load();
    expect(migrated.projects.map((item) => item.name), ['Roadshow', '仅用于报销']);
    final repo = InvoiceRepository(space);
    final ledger = await repo.load();
    expect(ledger.entries.map((item) => item.id), ['two', 'one']);
    final first = ledger.entries.last;
    expect(first.info.project, 'task-id');
    expect(first.info.amount, '123.45');
    expect(first.info.reimbursed, isTrue);
    expect(first.original.id, 'one-pdf');
    expect(first.attachments.single.id, 'one-receipt');
    expect(ledger.entries.first.info.project, migrated.projects.last.id);
    expect(
      (await space.load()).projects.map((item) => item.id),
      migrated.projects.map((item) => item.id),
    );
    final check = sqlite3.open(space.path, mode: OpenMode.readOnly);
    try {
      expect(check.userVersion, 5);
      expect(check.select('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      check.close();
    }
  });

  test('A4 排版按 1–4 张分页、顶格对齐、独立附件和毫米边距', () {
    final sample = (
      path: '/invoice.pdf',
      page: 1,
      x: 20.0,
      y: 70.0,
      width: 200.0,
      height: 80.0,
    );
    final invoices = List.filled(5, sample);
    for (final landscape in [false, true]) {
      for (var capacity = 1; capacity <= 4; capacity++) {
        final layout = InvoiceLayout(
          landscape: landscape,
          perPage: capacity,
          top: 7,
          left: 3,
          right: 5,
          bottom: 11,
        );
        final sheets = layout.arrange(invoices, [sample]);
        expect(sheets.length, (5 / capacity).ceil() + 1);
        expect(
          sheets.first['width'],
          closeTo(landscape ? 841.89 : 595.28, 0.01),
        );
        final slots = sheets.first['slots']! as List<Map<String, Object>>;
        expect(slots.length, capacity);
        final rect = slots.first['rect']! as List<double>;
        expect(
          rect[1] + rect[3],
          closeTo(layout.height - 7 * InvoiceLayout.pointPerMillimeter, 0.001),
        );
        expect(
          (sheets.first['lines']! as List).length,
          capacity == 4 ? 2 : capacity - 1,
        );
        expect(sheets.last['lines'], isEmpty);
      }
    }
    expect(
      const InvoiceLayout(cutLines: false).arrange(invoices, []).first['lines'],
      isEmpty,
    );
    expect(
      () => const InvoiceLayout(top: 400).arrange(invoices, []),
      throwsStateError,
    );
  });
}
