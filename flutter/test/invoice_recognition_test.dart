import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/invoice_recognition.dart';
import 'package:space_flutter/core/invoices.dart';
import 'package:space_flutter/core/repository.dart';

void main() {
  test('价税合计优先于较早出现的未税金额与明细金额', () {
    final result = parseInvoiceText(
      '电子发票（普通发票）\n发票号码：26327000000000000123\n开票日期：2026年11月13日\n金额：100.00\n未税金额：100.00\n税额：6.00\n价税合计（小写）：¥106.00',
    );
    expect(result.fields['cents'], 10600);
    expect(result.fields['net_cents'], 10000);
    expect(result.fields['tax_cents'], 600);
    final incomplete = parseInvoiceText('电子发票（普通发票）\n未税金额：100.00\n税额：6.00');
    expect(incomplete.fields.containsKey('cents'), isFalse);
  });
  test('电子发票提取票面标题、前导零和金额，不产生个人备注', () {
    final r = parseInvoiceText(
      '电子发票（普通发票）\n发票号码：00123456789012345678\n开票日期：2026年11月12日\n销售方名称：示例酒店有限公司\n价税合计（小写）￥680.00\n备注：票面示例',
    );
    expect(r.fields['title'], '电子发票（普通发票）');
    expect(r.fields['number'], '00123456789012345678');
    expect(r.fields['issued'], '2026-11-12');
    expect(r.fields['cents'], 68000);
    expect(r.fields.containsKey('purpose'), false);
  });
  test('出租车票无税额时保留空值，乘车日期和票面名称可解析', () {
    final r = parseInvoiceText(
      '大连市出租汽车专用发票\n发票号码\n01065004\n日期2026年10月15日\n金额￥22.10元',
    );
    expect(r.fields['title'], '大连市出租汽车专用发票');
    expect(r.fields['number'], '01065004');
    expect(r.fields['issued'], '2026-10-15');
    expect(r.fields['cents'], 2210);
    expect(r.fields.containsKey('tax_cents'), false);
  });
  test('无效日期和无法提取的金额不填默认值', () {
    final r = parseInvoiceText('开票日期：2026年02月31日\n金额不清晰');
    expect(r.fields['issued'], isNull);
    expect(r.fields['cents'], isNull);
    expect(r.message, isNotEmpty);
  });

  test('编辑备注期间完成识别，保存备注不会清空新识别字段', () async {
    final dir = await Directory.systemTemp.createTemp('space232-race-');
    addTearDown(() => dir.delete(recursive: true));
    final space = SpaceRepository(dir);
    await space.load();
    final repo = InvoiceRepository(space);
    await repo.load();
    final source = File('${dir.path}/sample.jpg');
    await source.writeAsBytes([255, 216, 255, 224]);
    await repo.importFiles([source.path]);
    final entry = (await repo.load()).entries.single;
    await repo.applyRecognition(entry.id, {
      'title': '电子发票（普通发票）',
      'number': '00000001',
      'issued': '2026-11-12',
      'cents': 10000,
    }, '');
    await repo.save(
      entry.id,
      const InvoiceInfo(purpose: '新个人备注'),
      baseline: entry.info,
    );
    final info = (await repo.load()).entries.single.info;
    expect(info.title, '电子发票（普通发票）');
    expect(info.cents, 10000);
    expect(info.purpose, '新个人备注');
    expect(info.issued, '2026-11-12');
  });
  test('结构化识别数据随发票记录保存，且不写入个人备注与报销状态', () async {
    final dir = await Directory.systemTemp.createTemp('space232-structure-');
    addTearDown(() => dir.delete(recursive: true));
    final space = SpaceRepository(dir);
    await space.load();
    final repo = InvoiceRepository(space);
    await repo.load();
    final f = File('${dir.path}/sample.jpg');
    await f.writeAsBytes([255, 216, 255, 224]);
    await repo.importFiles([f.path]);
    final entry = (await repo.load()).entries.single;
    await repo.applyRecognition(
      entry.id,
      {'title': '电子发票（普通发票）', 'number': '00000001'},
      '',
      structured: {
        'source': 'ocr',
        'items': [
          {'name': '*汽油*92号车用汽油(ⅥB)', 'amount': '208.35'},
        ],
        'totals': {'total': '235.44'},
        'checks': [
          {'name': '金额 + 税额 = 价税合计', 'ok': true},
        ],
      },
    );
    final info = (await repo.load()).entries.single.info;
    expect(info.title, '电子发票（普通发票）');
    expect(info.purpose, isEmpty, reason: '识别不写个人备注');
    expect(info.reimbursed, isFalse, reason: '识别不改报销状态');
    expect(info.recognitionStructure['source'], 'ocr');
    expect((info.recognitionStructure['items'] as List).length, 1);
    expect((info.recognitionStructure['totals'] as Map)['total'], '235.44');
    // 后续不带明细的识别不会清空已保存的结构化数据。
    await repo.applyRecognition(
      entry.id,
      {'number': '00000002'},
      '部分票面字段未能可靠提取，请核对原件。',
      structured: {'source': 'ocr', 'items': []},
    );
    final again = (await repo.load()).entries.single.info;
    expect((again.recognitionStructure['items'] as List).length, 1);
    expect(again.recognitionNotice, isNotEmpty);
  });

  test('识别保护个人字段以及用户改过的票面值，备份恢复保留票面名称', () async {
    final dir = await Directory.systemTemp.createTemp('space232-invoice-');
    addTearDown(() => dir.delete(recursive: true));
    final space = SpaceRepository(dir);
    await space.load();
    final repo = InvoiceRepository(space);
    await repo.load();
    final f = File('${dir.path}/sample.jpg');
    await f.writeAsBytes([255, 216, 255, 224]);
    await repo.importFiles([f.path]);
    final entry = (await repo.load()).entries.single;
    await repo.save(
      entry.id,
      const InvoiceInfo(
        purpose: '个人备注',
        seller: '人工销售方',
        spent: '2026-10-01',
        month: '2026-12',
        reimbursed: true,
      ),
    );
    await repo.applyRecognition(entry.id, {
      'title': '电子发票（普通发票）',
      'seller': '识别销售方',
      'number': '00000001',
      'issued': '2026-11-12',
      'cents': 2210,
    }, '');
    final info = (await repo.load()).entries.single.info;
    expect(info.title, '电子发票（普通发票）');
    expect(info.purpose, '个人备注');
    expect(info.seller, '人工销售方');
    expect(info.spent, '2026-10-01');
    expect(info.month, '2026-12');
    expect(info.reimbursed, true);
    final backup = '${dir.path}/recognition.sqlite';
    await space.exportSQLite(backup);
    final target = SpaceRepository(Directory('${dir.path}/restored'));
    await target.load();
    await target.importInvoiceLedger(backup);
    expect(
      (await InvoiceRepository(target).load()).entries.single.info.title,
      info.title,
    );
  });
}
