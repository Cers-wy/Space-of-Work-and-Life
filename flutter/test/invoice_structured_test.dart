import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/invoice_pdf_engine.dart';
import 'package:space_flutter/core/invoice_structured.dart';

/// 2026-11-12：按 output/invoice_26327000001934275142.json 的成品油数电票
/// 构造带坐标的视觉行，验证 PDF 文本层与 OCR 共用的结构化解析。
void main() {
  InvoiceWord word(double x, String text, {double y = 0, double w = 30}) =>
      InvoiceWord(x, y, w, 10, text);

  InvoiceTextLine line(double y, List<InvoiceWord> words) =>
      InvoiceTextLine(y, words);

  List<InvoiceTextLine> sampleInvoice() => [
    line(20, [
      word(40, '电子发票', y: 20),
      word(80, '（普通发票）', y: 20),
      word(300, '成品油', y: 20),
    ]),
    line(40, [
      word(40, '发票号码：26327000001934275142', y: 40, w: 160),
      word(330, '开票日期：2026年11月11日', y: 40, w: 140),
    ]),
    line(70, [
      word(20, '购买方名称：苏州恒力智能科技有限公司', y: 70, w: 200),
      word(320, '销售方名称：中国石油天然气股份有限公司江苏苏州销售分公司', y: 70, w: 240),
    ]),
    line(90, [
      word(20, '统一社会信用代码：91320509MA1PBKX066', y: 90, w: 200),
      word(320, '统一社会信用代码：913205067037181312', y: 90, w: 200),
    ]),
    line(120, [
      word(20, '项目名称', y: 120),
      word(90, '规格型号', y: 120),
      word(150, '单位', y: 120),
      word(190, '数量', y: 120),
      word(240, '单价', y: 120),
      word(300, '金额', y: 120),
      word(360, '税率', y: 120),
      word(410, '税额', y: 120),
    ]),
    line(140, [
      word(20, '*汽油*92号车用汽油(ⅥB)', y: 140, w: 120),
      word(90, '92#汽油', y: 140, w: 50),
      word(150, '升', y: 140, w: 12),
      word(190, '29.24757748', y: 140, w: 60),
      word(240, '7.12366691369', y: 140, w: 60),
      word(300, '208.35', y: 140, w: 50),
      word(360, '13%', y: 140, w: 30),
      word(410, '27.09', y: 140, w: 40),
    ]),
    line(160, [
      word(20, '合计', y: 160),
      word(300, '208.35', y: 160, w: 50),
      word(410, '27.09', y: 160, w: 40),
    ]),
    line(180, [
      word(20, '价税合计（大写）贰佰叁拾伍圆肆角肆分', y: 180, w: 200),
      word(330, '（小写）¥235.44', y: 180, w: 100),
    ]),
    line(200, [
      word(20, '收款人：张晓锦', y: 200),
      word(120, '复核人：王芳', y: 200),
      word(220, '开票人：查兰芳', y: 200),
    ]),
  ];

  test('PDF 文本层按左右栏和明细列解析成发票字段与结构化数据', () {
    final result = parseStructuredInvoice(sampleInvoice(), width: 595.2);
    expect(result.fields['title'], '电子发票（普通发票）');
    expect(result.fields['number'], '26327000001934275142');
    expect(result.fields['issued'], '2026-11-11');
    expect(result.fields['buyer'], '苏州恒力智能科技有限公司');
    expect(
      result.fields['seller'],
      '中国石油天然气股份有限公司江苏苏州销售分公司',
    );
    expect(result.fields['buyer_tax'], '91320509MA1PBKX066');
    expect(result.fields['seller_tax'], '913205067037181312');
    expect(result.fields['cents'], 23544);
    expect(result.fields['tax_cents'], 2709);
    expect(result.fields['net_cents'], 20835);
    expect(result.message, isEmpty, reason: '关键字段齐全且金额校验通过');
    expect(result.complete, isTrue);

    final structure = result.structure;
    expect(structure['source'], 'pdf-text');
    expect(structure['special_category'], '成品油');
    final items = structure['items'] as List;
    expect(items.length, 1);
    final item = items.single as Map;
    expect(item['name'], '*汽油*92号车用汽油(ⅥB)');
    expect(item['specification'], '92#汽油');
    expect(item['unit'], '升');
    expect(item['quantity'], '29.24757748');
    expect(item['amount'], '208.35');
    expect(item['tax'], '27.09');
    final totals = structure['totals'] as Map;
    expect(totals['total'], '235.44');
    expect(totals['total_in_words'], '贰佰叁拾伍圆肆角肆分');
    final people = structure['people'] as Map;
    expect(people['drawer'], '查兰芳');
    final checks = structure['checks'] as List;
    expect(checks.length, 3);
    expect(checks.every((c) => (c as Map)['ok'] == true), isTrue);
  });

  test('名称标签、小数点分行时仍能解析购销方与明细金额', () {
    // 复刻数电票里「购 名称 苏州…」「销 名称 江苏…」逐字分框、小数点/冒号
    // 单独落在下一基线的情况（见 2026-11-12 的真实发票验证）。
    final lines = [
      line(70, [
        word(17, '购', y: 70, w: 7),
        word(32, '名称', y: 70, w: 20),
        word(57, '苏州恒力智能科技有限公司', y: 70, w: 106),
        word(302, '销', y: 70, w: 7),
        word(317, '名称', y: 70, w: 20),
        word(340, '江苏苏汽旅游集团有限公司', y: 70, w: 100),
      ]),
      line(90, [
        word(20, '项目名称', y: 90, w: 35),
        word(215, '单价', y: 90),
        word(298, '数量', y: 90),
        word(384, '金额', y: 90),
        word(433, '税率', y: 90),
        word(555, '税额', y: 90),
      ]),
      line(110, [
        word(15, '*交通运输服务*客运费', y: 110, w: 90),
        word(388, '96', y: 110, w: 8),
        word(403, '12', y: 110, w: 6),
        word(455, '3', y: 110, w: 4),
        word(459, '%', y: 110, w: 4),
        word(564, '2', y: 110, w: 4),
        word(573, '88', y: 110, w: 7),
      ]),
      line(116, [
        word(398, '.', y: 116, w: 1),
        word(569, '.', y: 116, w: 1),
      ]),
      line(130, [
        word(58, '合计', y: 130, w: 50),
        word(389, '96', y: 130, w: 8),
        word(403, '12', y: 130, w: 6),
        word(558, '2', y: 130, w: 4),
        word(573, '88', y: 130, w: 7),
      ]),
      line(136, [
        word(398, '.', y: 136, w: 1),
        word(569, '.', y: 136, w: 1),
      ]),
    ];
    final result = parseStructuredInvoice(lines, width: 595.2);
    expect(result.fields['buyer'], '苏州恒力智能科技有限公司');
    expect(result.fields['seller'], '江苏苏汽旅游集团有限公司');
    expect(result.fields['net_cents'], 9612, reason: '合计行的 96.12');
    expect(result.fields['tax_cents'], 288);
    final items = result.structure['items'] as List;
    expect(items.length, 1);
    final item = items.single as Map;
    expect(item['amount'], '96.12');
    expect(item['tax_rate'], '3%');
    expect(item['tax'], '2.88');
  });

  test('逐字符 PDF 导出按 x 紧邻关系合并成词，并按基线聚成视觉行', () {
    final chars = <InvoiceWord>[];
    for (var i = 0; i < '发票号码'.length; i++) {
      chars.add(InvoiceWord(20 + i * 10, 30, 9, 10, '发票号码'[i]));
    }
    chars.add(InvoiceWord(59, 30, 9, 10, '：'));
    chars.add(InvoiceWord(68, 30, 40, 10, '001234'));
    chars.add(InvoiceWord(20, 60, 40, 10, '价税合计'));
    final words = mergeInvoiceChars(chars);
    expect(words.length, 2, reason: '逐字与紧邻标点合并，隔行词不合并');
    expect(words.first.text, '发票号码：001234');
    final lines = invoiceLines(words, tolerance: 4);
    expect(lines.length, 2);
    expect(lines.first.text, '发票号码：001234');
  });

  test('OCR 带坐标行同样解析成结构化字段并过滤低置信数字', () {
    final ocrLines = <Map<String, dynamic>>[
      {'text': '电子发票', 'x': 20.0, 'y': 20.0, 'height': 12.0, 'confidence': .96},
      {'text': '（普通发票）', 'x': 70.0, 'y': 20.0, 'height': 12.0, 'confidence': .93},
      {'text': '发票号码：00123456789012345678', 'x': 20.0, 'y': 45.0, 'height': 12.0, 'confidence': .99},
      {'text': '开票日期：2026年11月12日', 'x': 300.0, 'y': 45.0, 'height': 12.0, 'confidence': .95},
      {'text': '销售方名称：示例酒店有限公司', 'x': 320.0, 'y': 70.0, 'height': 12.0, 'confidence': .92},
      {'text': '价税合计（小写）¥680.00', 'x': 20.0, 'y': 100.0, 'height': 12.0, 'confidence': .99},
      {'text': '￥999.00', 'x': 20.0, 'y': 120.0, 'height': 12.0, 'confidence': .80},
    ];
    final words = invoiceWordsFromOcr(ocrLines);
    expect(words.length, 6, reason: '低置信金额不参与结构化');
    final lines = invoiceLines(words, tolerance: 7);
    final width = words.map((w) => w.right).reduce((a, b) => a > b ? a : b) + 20;
    final result = parseStructuredInvoice(lines, width: width, source: 'ocr');
    expect(result.fields['title'], '电子发票（普通发票）');
    expect(result.fields['number'], '00123456789012345678');
    expect(result.fields['issued'], '2026-11-12');
    expect(result.fields['seller'], '示例酒店有限公司');
    expect(result.fields['cents'], 68000);
    expect(result.structure['source'], 'ocr');
  });

  test('结构化行可序列化后在 isolate 内还原并解析', () {
    final lines = sampleInvoice();
    final payload = structuredLinesPayload(595.2, lines, characters: 420);
    expect(payload['characters'], 420);
    final result = parseStructuredPayload(payload);
    expect(result.fields['number'], '26327000001934275142');
    expect(result.fields['cents'], 23544);
  });

  test('真实 PDFium 字符盒可还原成视觉行并序列化', () async {
    final pdf = await NativeInvoicePdf.structuredText(
      'test/fixtures/invoice-predictor-crop.pdf',
    );
    expect(pdf.width, closeTo(595.275, .01));
    expect(pdf.characters, greaterThan(0));
    expect(pdf.lines, isNotEmpty);
    final parsed = parseStructuredPayload(pdf.payload);
    expect(parsed.structure['source'], 'pdf-text');
    expect(parsed.message, isNotEmpty, reason: '该夹具不是完整发票，应提示核对');
  });

  test('源码里使用的 SpaceIcon / IconButtonS 名称都有对应字形', () {
    // 防止「cloud / reload」这类缺字形落到 default 只画一个空方块。
    final controls = File('lib/ui/controls.dart').readAsStringSync();
    final cases = RegExp(r"case '([^']+)'")
        .allMatches(controls)
        .map((m) => m.group(1)!)
        .toSet();
    final used = <String>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in RegExp(
        r"(?:SpaceIcon|IconButtonS|IconS)\(\s*'([^']+)'",
      ).allMatches(source)) {
        used.add(match.group(1)!);
      }
      for (final match in RegExp(
        r"IconButtonS\.toolbar\(\s*'([^']+)'",
      ).allMatches(source)) {
        used.add(match.group(1)!);
      }
    }
    expect(used.difference(cases), isEmpty);
    expect(cases.containsAll(['cloud', 'reload']), isTrue);
  });
}
