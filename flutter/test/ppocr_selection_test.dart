import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/invoice_recognition.dart';
import 'package:space_flutter/core/ppocr.dart';
import 'package:space_ocr/space_ocr.dart';

void main() {
  test('不把模糊金额当成可靠数据，仍保留清晰日期', () {
    final text = reliableInvoiceOcrText(
      const PpocrResult('', .99, [
        {
          'text': '金额￥322.18元',
          'confidence': .84,
          'x': 100.0,
          'y': 200.0,
          'height': 30.0,
        },
        {
          'text': '2026年10月15日',
          'confidence': .996,
          'x': 100.0,
          'y': 100.0,
          'height': 30.0,
        },
      ]),
    );
    expect(text, isNot(contains('322.18')));
    expect(parseInvoiceText(text).fields['cents'], isNull);
    expect(parseInvoiceText(text).fields['issued'], '2026-10-15');
  });
  test('出租车上下排列的发票号码标签仍能关联前导零', () {
    final text = reliableInvoiceOcrText(
      const PpocrResult('', .99, [
        {'text': '发票', 'confidence': .99, 'x': 10.0, 'y': 70.0, 'height': 46.0},
        {
          'text': '号码',
          'confidence': .99,
          'x': 10.0,
          'y': 100.0,
          'height': 46.0,
        },
        {
          'text': '01065004',
          'confidence': .999,
          'x': 120.0,
          'y': 77.0,
          'height': 53.0,
        },
      ]),
    );
    expect(parseInvoiceText(text).fields['number'], '01065004');
  });
  test('两档模型关键金额冲突时不自动采用其中一个', () {
    final merged = mergeInvoiceRecognition(
      const InvoiceRecognition({'number': '01065004', 'cents': 2210}, ''),
      const InvoiceRecognition({'number': '01065004', 'cents': 32218}, ''),
    );
    expect(merged.fields['number'], '01065004');
    expect(merged.fields['cents'], isNull);
    expect(merged.message, contains('差异'));
  });
}
