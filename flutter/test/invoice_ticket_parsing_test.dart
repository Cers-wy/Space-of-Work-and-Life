import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/invoice_recognition.dart';
import 'package:space_flutter/core/invoice_structured.dart';

void main() {
  InvoiceTextLine line(double y, double x, String text) =>
      InvoiceTextLine(y, [InvoiceWord(x, y, 180, 10, text)]);
  test(
    'vertical side glyphs and separated name/tax values stay in their section',
    () {
      final result = parseStructuredInvoice([
        line(20, 20, '购'),
        line(32, 20, '买'),
        line(44, 20, '方'),
        const InvoiceTextLine(20, [
          InvoiceWord(50, 20, 30, 10, '名称：'),
          InvoiceWord(140, 20, 140, 10, '隔离采购有限公司'),
        ]),
        line(65, 50, '纳税人识别号：'),
        line(80, 50, '91320000TEST000001'),
        line(220, 20, '销'),
        line(232, 20, '售'),
        line(244, 20, '方'),
        line(235, 50, '名称：隔离销售有限公司'),
        line(265, 50, '纳税人识别号：91320000TEST000002'),
      ], width: 600);
      expect(result.fields['buyer'], '隔离采购有限公司');
      expect(result.fields['buyer_tax'], '91320000TEST000001');
      expect(result.fields['seller'], '隔离销售有限公司');
    },
  );
  test(
    'old VAT upper/lower party labels override identical left-column positions',
    () {
      final parsed = parseStructuredInvoice([
        line(10, 20, '增值税专用发票'),
        line(25, 20, '发票号码：00000001'),
        line(50, 20, '购买方'),
        line(65, 50, '名称：隔离购买有限公司'),
        line(80, 50, '纳税人识别号：91320000TEST000001'),
        line(220, 20, '销售方'),
        line(235, 50, '名称：隔离销售有限公司'),
        line(250, 50, '纳税人识别号：91320000TEST000002'),
      ], width: 600);
      expect(parsed.fields['buyer'], '隔离购买有限公司');
      expect(parsed.fields['seller'], '隔离销售有限公司');
      expect(parsed.fields['buyer_tax'], '91320000TEST000001');
      expect(parsed.fields['seller_tax'], '91320000TEST000002');
    },
  );
  test('explicit reversed left/right labels and missing-party fallback remain safe', () {
    final parsed = parseStructuredInvoice([
      InvoiceTextLine(60, [
        const InvoiceWord(20, 60, 180, 10, '销售方名称：隔离销售有限公司'),
        const InvoiceWord(330, 60, 180, 10, '购买方名称：隔离购买有限公司'),
      ]),
      InvoiceTextLine(80, [
        const InvoiceWord(20, 80, 180, 10, '统一社会信用代码：91320000TEST000002'),
        const InvoiceWord(330, 80, 180, 10, '统一社会信用代码：91320000TEST000001'),
      ]),
    ], width: 600);
    expect(parsed.fields['seller'], '隔离销售有限公司');
    expect(parsed.fields['buyer_tax'], '91320000TEST000001');
    final incomplete = parseInvoiceText(
      '电子发票（普通发票）\n发票号码：00000001\n开票日期：2026年11月16日\n价税合计（小写）￥106.00',
    );
    expect(
      incomplete.message,
      isNotEmpty,
      reason: 'four header fields no longer skip party OCR',
    );
  });
  test('railway keeps invoice date distinct from travel date and absent seller empty', () {
    final r = parseInvoiceText(
      '电子发票（铁路电子客票）\n发票号码：26310000000000000123\n乘车日期：2026年11月10日\n开票日期：2026年11月16日\n票价：￥174.50\n购买方名称：隔离测试有限公司\n统一社会信用代码：91320000TEST000001',
    );
    expect(r.fields['issued'], '2026-11-16');
    expect(r.fields['cents'], 17450);
    expect(r.fields['buyer'], '隔离测试有限公司');
    expect(r.fields['buyer_tax'], '91320000TEST000001');
    expect(r.fields['seller'], isNull);
    expect(r.fields['seller_tax'], isNull);
    expect(
      parseInvoiceText('电子发票（铁路电子客票）\n乘车日期：2026年11月10日').fields['issued'],
      isNull,
    );
  });
  test('aviation uses issuing unit and explicit total excluding insurance', () {
    final r = parseInvoiceText(
      '电子发票（航空运输电子客票行程单）\n发票号码：26310000000000000456\n填开日期：2026年11月16日\n填开单位：隔离航空有限公司\n购买方名称：隔离测试有限公司\n统一社会信用代码：91320000TEST000001\n票价：800.00\n合计：￥950.00\n保险费：40.00',
    );
    expect(r.fields['issued'], '2026-11-16');
    expect(r.fields['seller'], '隔离航空有限公司');
    expect(r.fields['cents'], 95000);
    final table = parseStructuredInvoice([
      line(10, 20, '电子发票（航空运输电子客票行程单）'),
      const InvoiceTextLine(80, [
        InvoiceWord(20, 80, 40, 10, '票价'),
        InvoiceWord(180, 80, 40, 10, '合计'),
        InvoiceWord(300, 80, 40, 10, '保险费'),
      ]),
      const InvoiceTextLine(100, [
        InvoiceWord(20, 100, 40, 10, '800.00'),
        InvoiceWord(180, 100, 40, 10, '950.00'),
        InvoiceWord(300, 100, 40, 10, '40.00'),
      ]),
    ], width: 600);
    expect(table.fields['cents'], 95000);
  });
  test('missing net or tax and travel totals are unassessed instead of false failures', () {
    for (final title in ['电子发票（普通发票）', '电子发票（铁路电子客票）', '电子发票（航空运输电子客票行程单）']) {
      final r = parseStructuredInvoice([
        line(10, 20, title),
        line(30, 20, '价税合计（小写）￥106.00'),
      ], width: 600);
      final check = (r.structure['checks'] as List).last as Map;
      expect(check['ok'], isNull);
      expect(check['status'], 'unassessed');
      expect(r.message.contains('校验未通过'), isFalse);
    }
  });
  test(
    'pages remain independent even when attachment fields share coordinates',
    () {
      final first = structuredLinesPayload(600, [
        line(10, 20, '电子发票（普通发票）'),
        line(25, 20, '发票号码：26310000000000000123'),
        line(50, 20, '购买方名称：首张购买有限公司'),
      ]);
      final attachment = structuredLinesPayload(600, [
        line(10, 20, '附件'),
        line(50, 20, '销售方名称：附件中的其他公司'),
      ]);
      final result = parseInvoicePages({
        'pages': [first, attachment],
      });
      expect(result.fields['buyer'], '首张购买有限公司');
      expect(result.fields['seller'], isNull);
      final other = structuredLinesPayload(600, [
        line(10, 20, '电子发票（普通发票）'),
        line(25, 20, '发票号码：26310000000000000456'),
      ]);
      expect(
        parseInvoicePages({
          'pages': [first, other],
        }).message,
        contains('多张'),
      );
    },
  );
}
