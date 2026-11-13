import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:space_ocr/space_ocr.dart' show PpocrResult;

import 'ppocr.dart';
import 'invoice_pdf_engine.dart';
import 'invoice_structured.dart';
import 'invoices.dart';

class InvoiceRecognition {
  final Map<String, Object?> fields;
  final String message;

  /// 2026-11-12：识别出的发票结构化数据（明细、合计、人员、金额校验），
  /// 由台账写入 recognition 字段，供详情与后续核对使用。
  final Map<String, Object?>? structured;
  const InvoiceRecognition(this.fields, this.message, {this.structured});
}

/// Deterministic parsing shared by both desktop platforms. Notes are deliberately absent.
InvoiceRecognition parseInvoiceText(String source) {
  final text = source
      .replaceAll('：', ':')
      .replaceAll('（', '(')
      .replaceAll('）', ')');
  final compact = text
      .replaceAll(RegExp(r'[ \t\u3000]'), '')
      .replaceAll(RegExp(r'发票\s*号码'), '发票号码')
      .replaceAll(RegExp(r'开票\s*日期'), '开票日期');
  final fields = <String, Object?>{};
  String? match(String pattern, {String? input, int group = 1}) => RegExp(
    pattern,
    multiLine: true,
  ).firstMatch(input ?? compact)?.group(group)?.trim();
  final title =
      match(r'(电子发票\([^\n)]{1,30}\))') ??
      match(r'([^\n]{0,18}出租(?:汽)?车[^\n]{0,10}发票)') ??
      match(r'([^\n]{0,12}增值税[^\n]{0,12}发票)');
  if (title != null) {
    fields['title'] = title.replaceAll('(', '（').replaceAll(')', '）');
  }
  final taxi = compact.contains('出租') || compact.contains('TAXI');
  final number =
      match(r'发票(?:号码|号)[:]?\s*([0-9]{8,20})(?![0-9])') ??
      match(r'^([0-9]{20})$', input: compact);
  if (number != null) fields['number'] = number;
  final date =
      match(
        r'(?:开票日期|乘车日期|日期)[:]?\s*(20[0-9]{2})[年/.-]?\s*([0-9]{1,2})[月/.-]\s*([0-9]{1,2})',
      ) ??
      '';
  final dateMatch = RegExp(
    r'(?:开票日期|乘车日期|日期)[:]?\s*(20[0-9]{2})[年/.-]?\s*([0-9]{1,2})[月/.-]\s*([0-9]{1,2})',
  ).firstMatch(compact);
  final fallback =
      dateMatch ??
      RegExp(r'(20[0-9]{2})年([0-9]{1,2})月([0-9]{1,2})日').firstMatch(compact);
  if (date.isNotEmpty || fallback != null) {
    final m = fallback!;
    final value = '${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}';
    if (DateTime.tryParse(value)?.toIso8601String().startsWith(value) == true) {
      fields['issued'] = value;
    }
  }
  int? money(String? value) {
    if (value == null) return null;
    final clean = value.replaceAll(',', '').replaceAll('，', '');
    if (!RegExp(r'^-?\d{1,12}\.\d{2}$').hasMatch(clean)) return null;
    final negative = clean.startsWith('-');
    final parts = clean.replaceFirst('-', '').split('.');
    return (int.parse(parts[0]) * 100 + int.parse(parts[1])) *
        (negative ? -1 : 1);
  }

  final total =
      match(
        r'(?:价税合计(?:\(大写\))?[^\n0-9]{0,35}?|小写[):]?|金额)[:]?\s*[¥￥Y]?\s*(-?[0-9,]+\.[0-9]{2})(?![0-9])',
      ) ??
      (taxi ? match(r'[¥￥]\s*(-?[0-9,]+\.[0-9]{2})') : null);
  final cents = money(total);
  if (cents != null) fields['cents'] = cents;
  if (!taxi) {
    final tax = money(
      match(r'(?:合计税额|税额合计|税额)[:]?\s*[¥￥]?\s*(-?[0-9,]+\.[0-9]{2})'),
    );
    final net = money(
      match(r'(?:不含税金额|未税金额|合计金额)[:]?\s*[¥￥]?\s*(-?[0-9,]+\.[0-9]{2})'),
    );
    if (tax != null) fields['tax_cents'] = tax;
    if (net != null) fields['net_cents'] = net;
  }
  // Prefer explicit labels, then separate buyer/seller sections. Never use the tax authority as issuer.
  for (final side in ['seller', 'buyer']) {
    final label = side == 'seller' ? '销售方' : '购买方';
    var name = match('$label(?:名称)?[:]?([^\\n:]{3,70})');
    if (name != null && (name.contains('名称') || name.contains('统一社会'))) {
      name = null;
    }
    final section = RegExp('$label[\\s\\S]{0,180}?名称[:]?([^\\n:]{3,70})')
        .firstMatch(compact);
    name ??= section?.group(1);
    if (name != null) {
      name = name.split(RegExp(r'统一社会信用代码|纳税人识别号|地址|电话|开户行|发票号码')).first;
      if (name.length >= 3 && !name.contains('税务局')) fields[side] = name;
    }
    final taxID =
        match('$label[^\\n]{0,80}?(?:统一社会信用代码|纳税人识别号)[:]?([A-Z0-9]{15,20})') ??
        RegExp('$label[\\s\\S]{0,180}?(?:统一社会信用代码|纳税人识别号)[:]?([A-Z0-9]{15,20})')
            .firstMatch(compact)
            ?.group(1);
    if (taxID != null) fields['${side}_tax'] = taxID;
  }
  final missing = [
    for (final key in ['title', 'number', 'issued', 'cents'])
      if (!fields.containsKey(key)) key,
  ];
  return InvoiceRecognition(
    fields,
    missing.isEmpty ? '' : '部分票面字段未能可靠提取，请核对原件。',
  );
}

abstract final class InvoiceRecognizer {
  static const requiredKeys = ['title', 'number', 'issued', 'cents'];
  static bool _complete(Map<String, Object?> fields) =>
      requiredKeys.every(fields.containsKey);

  /// preferOcr 来自设置中的「优先使用 OCR」开关（默认关闭）。
  /// 默认优先 PDF 文本层：词坐标结构化解析更准，也不需要 OCR 模型；
  /// 仅在字段不完整或 PDF 无文本层时才渲染页面走 OCR。
  static Future<InvoiceRecognition> recognize(
    InvoiceFile file, {
    bool preferOcr = false,
  }) async {
    if (!file.isPdf) return _image(file.path);
    InvoiceRecognition? ocr;
    if (preferOcr) {
      ocr = await _pdfOcr(file.path);
      if (ocr != null && ocr.message.isEmpty && _complete(ocr.fields)) {
        return ocr;
      }
    }
    final pdf = await _pdfText(file.path);
    if (!preferOcr && pdf.message.isEmpty && _complete(pdf.fields)) return pdf;
    ocr ??= await _pdfOcr(file.path);
    return ocr == null ? pdf : _merge(pdf, ocr);
  }

  static InvoiceRecognition _merge(
    InvoiceRecognition primary,
    InvoiceRecognition fallback,
  ) {
    final fields = <String, Object?>{
      ...fallback.fields,
      ...primary.fields,
    };
    return InvoiceRecognition(
      fields,
      !_complete(fields)
          ? '部分票面字段未能可靠提取，请核对原件。'
          : primary.message.contains('校验')
          ? primary.message
          : '',
      structured: primary.structured ?? fallback.structured,
    );
  }

  /// PDF 文本层：词坐标 -> 视觉行 -> 结构化发票字段 + 明细/合计/校验。
  static Future<InvoiceRecognition> _pdfText(String path) async {
    final pdf = await NativeInvoicePdf.structuredText(path);
    if (pdf.characters == 0) {
      return const InvoiceRecognition({}, '未检测到 PDF 文本层，请改用 OCR 识别。');
    }
    final payload = pdf.payload;
    return Isolate.run(() {
      final structured = parseStructuredPayload(payload);
      final text = (payload['lines'] as List)
          .map((line) => (line as Map)['words'] as List)
          .map(
            (words) => words
                .map((word) => '${(word as Map)['text'] ?? ''}')
                .join(' '),
          )
          .join('\n');
      final fallback = parseInvoiceText(text);
      final fields = <String, Object?>{
        ...fallback.fields,
        ...structured.fields,
      };
      return InvoiceRecognition(
        fields,
        !_complete(fields)
            ? '部分票面字段未能可靠提取，请核对原件。'
            : structured.message,
        structured: structured.structure,
      );
    });
  }

  static Future<InvoiceRecognition?> _pdfOcr(String path) async {
    final directory = await Directory.systemTemp.createTemp(
      'space-invoice-ocr-',
    );
    try {
      final bytes = await NativeInvoicePdf.ocrImage(path);
      final image = '${directory.path}/page.png';
      await File(image).writeAsBytes(bytes);
      return await _image(image);
    } catch (_) {
      // OCR 模型或组件不可用时仍保留 PDF 文本层结果，不让整次识别失败。
      return null;
    } finally {
      await directory.delete(recursive: true);
    }
  }

  /// 图片与扫描件：OCR 的带坐标行同样转成结构化发票数据。
  static Future<InvoiceRecognition> _image(String path) async {
    final small = await LocalPpocr.recognize(path);
    final initial = await _ocr(small);
    if (initial.message.isEmpty && small.confidence >= .90) return initial;
    final medium = await LocalPpocr.recognize(path, enhanced: true);
    final enhanced = await _ocr(medium);
    return mergeInvoiceRecognition(initial, enhanced);
  }

  static Future<InvoiceRecognition> _ocr(PpocrResult result) async {
    final words = invoiceWordsFromOcr(result.lines);
    final tolerance = words.isEmpty
        ? 4.0
        : math.max(
            3.0,
            words.map((w) => w.h).reduce(math.max) * .6,
          );
    final lines = invoiceLines(words, tolerance: tolerance);
    final width = words.isEmpty
        ? 600.0
        : words.map((w) => w.right).reduce(math.max) + 20;
    final payload = structuredLinesPayload(width, lines, source: 'ocr');
    final text = reliableInvoiceOcrText(result);
    return Isolate.run(() {
      final structured = parseStructuredPayload(payload);
      final fallback = parseInvoiceText(text);
      final fields = <String, Object?>{
        ...fallback.fields,
        ...structured.fields,
      };
      return InvoiceRecognition(
        fields,
        !_complete(fields)
            ? '部分票面字段未能可靠提取，请核对原件。'
            : structured.message,
        structured: structured.structure,
      );
    });
  }
}

InvoiceRecognition mergeInvoiceRecognition(
  InvoiceRecognition initial,
  InvoiceRecognition enhanced,
) {
  final fields = <String, Object?>{...initial.fields, ...enhanced.fields};
  final conflicts = <String>[];
  for (final key in ['number', 'issued', 'cents', 'tax_cents', 'net_cents']) {
    final a = initial.fields[key], b = enhanced.fields[key];
    if (a != null && b != null && a != b) {
      fields.remove(key);
      conflicts.add(key);
    }
  }
  final complete = [
    'title',
    'number',
    'issued',
    'cents',
  ].every(fields.containsKey);
  return InvoiceRecognition(
    fields,
    conflicts.isNotEmpty
        ? '两次识别的关键字段存在差异，已保留空白，请核对原件。'
        : complete
        ? ''
        : '部分票面字段未能可靠提取，请核对原件。',
    structured: initial.structured ?? enhanced.structured,
  );
}
