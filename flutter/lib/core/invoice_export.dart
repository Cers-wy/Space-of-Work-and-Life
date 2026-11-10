import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';

import 'invoices.dart';

enum InvoiceColumn {
  name('文件名'),
  number('发票号码'),
  issued('开票日期'),
  seller('销售方'),
  amount('金额'),
  spent('消费时间'),
  purpose('用途'),
  month('报销月份'),
  project('报销项目'),
  state('报销状态'),
  attachments('附件');

  final String title;
  const InvoiceColumn(this.title);

  Object value(InvoiceEntry e, Map<String, String> projects) => switch (this) {
    name => e.original.name,
    number => e.info.number,
    issued => e.info.issued,
    seller => e.info.seller,
    amount => e.info.cents == null ? '' : e.info.cents! / 100,
    spent => e.info.spent,
    purpose => e.info.purpose,
    month => e.info.month,
    project => projects[e.info.project] ?? '',
    state => e.info.reimbursed ? '已报销' : '未报销',
    attachments => e.attachments.map((f) => f.name).join('\n'),
  };
}

Future<void> exportInvoiceSheet(
  InvoiceRepository repo,
  String destination,
  List<InvoiceEntry> entries,
  Map<String, String> projects,
  List<InvoiceColumn> columns,
) => Isolate.run(() {
  repo.checkDestination(destination);
  if (entries.isEmpty || columns.isEmpty) throw StateError('请选择记录和导出字段');
  final archive = Archive();
  void add(String path, String xml) {
    final bytes = utf8.encode('<?xml version="1.0" encoding="UTF-8"?>$xml');
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('[Content_Types].xml', '''
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>''');
  add('_rels/.rels', '''
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');
  add('xl/workbook.xml', '''
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="发票台账" sheetId="1" r:id="rId1"/></sheets></workbook>''');
  add('xl/_rels/workbook.xml.rels', '''
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>''');
  final sheet = StringBuffer(
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>',
  );
  final control = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]');
  void row(int index, Iterable<Object> values) {
    sheet.write('<row r="$index">');
    var col = 65;
    for (final value in values) {
      final ref = '${String.fromCharCode(col++)}$index';
      if (value is num) {
        sheet.write('<c r="$ref"><v>$value</v></c>');
      } else {
        final text = const HtmlEscape().convert(
          value.toString().replaceAll(control, ''),
        );
        sheet.write(
          '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">$text</t></is></c>',
        );
      }
    }
    sheet.write('</row>');
  }

  row(1, columns.map((c) => c.title));
  for (var i = 0; i < entries.length; i++) {
    row(i + 2, columns.map((c) => c.value(entries[i], projects)));
  }
  sheet.write('</sheetData></worksheet>');
  add('xl/worksheets/sheet1.xml', sheet.toString());
  final bytes = ZipEncoder().encodeBytes(archive);
  writeInvoiceOutput(destination, (path) => File(path).writeAsBytesSync(bytes));
});
