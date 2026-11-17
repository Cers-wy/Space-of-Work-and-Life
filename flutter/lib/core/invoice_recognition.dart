import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:space_ocr/space_ocr.dart' show PpocrResult;

import 'ppocr.dart';
import 'invoice_pdf_engine.dart';
import 'invoice_structured.dart';
import 'invoices.dart';
import 'invoice_parties.dart';

class InvoiceRecognition {
  final Map<String, Object?> fields;
  final String message;

  /// 2026-11-12：识别出的发票结构化数据（明细、合计、人员、金额校验），
  /// 由台账写入 recognition 字段，供详情与后续核对使用。
  final Map<String, Object?>? structured;

  /// PDF 文本层元数据（仅文本层路径设置）：字符数与全文是否出现「发票」。
  /// 用于识别非发票文档（行程单等）并决定 OCR 兜底策略。
  final ({int characters, bool invoiceKeyword})? textLayer;
  const InvoiceRecognition(
    this.fields,
    this.message, {
    this.structured,
    this.textLayer,
  });
}

/// Deterministic parsing shared by both desktop platforms. Notes are deliberately absent.
InvoiceRecognition parseInvoiceText(String source) {
  final text = normalizeInvoiceLabels(source)
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
  final railway = compact.contains('铁路电子客票');
  final aviation = compact.contains('航空运输电子客票行程单');
  if (railway) fields['title'] = '电子发票（铁路电子客票）';
  if (aviation) {
    fields['title'] = compact.contains('电子发票')
        ? '电子发票（航空运输电子客票行程单）'
        : '航空运输电子客票行程单';
  }
  final taxi = compact.contains('出租') || compact.contains('TAXI');
  final number =
      match(r'发票(?:号码|号)[:]?\s*([0-9]{8,20})(?![0-9])') ??
      match(r'^([0-9]{20})$', input: compact);
  if (number != null) fields['number'] = number;
  final dateLabel = aviation
      ? r'(?:填开日期|开票日期)'
      : railway
      ? '开票日期'
      : taxi
      ? r'(?:开票日期|乘车日期|日期)'
      : '开票日期';
  final standaloneDates = RegExp(r'(20[0-9]{2})年([0-9]{1,2})月([0-9]{1,2})日')
      .allMatches(compact)
      .toList();
  final dateMatch =
      RegExp(
        '$dateLabel[:]?\\s*(20[0-9]{2})[年/.-]\\s*([0-9]{1,2})[月/.-]\\s*([0-9]{1,2})',
      ).firstMatch(compact) ??
      (!railway &&
              !aviation &&
              standaloneDates.length == 1 &&
              (taxi || !compact.contains(RegExp(r'乘车日期|乘机日期|出发日期')))
          ? standaloneDates.single
          : null);
  if (dateMatch != null) {
    final value =
        '${dateMatch[1]}-${dateMatch[2]!.padLeft(2, '0')}-${dateMatch[3]!.padLeft(2, '0')}';
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

  final travelTotal = railway
      ? match(r'票价[:]?\s*[¥￥]?\s*(-?[0-9,]+\.[0-9]{2})(?![0-9])')
      : aviation
      ? match(r'(?:^|\n)合计[:]?\s*[¥￥]?\s*(-?[0-9,]+\.[0-9]{2})(?![0-9])')
      : null;
  final total =
      travelTotal ??
      match(
        r'(?:价税合计(?:\(大写\))?[^\n0-9]{0,35}?|小写[):]?)[:]?\s*[¥￥Y]?\s*(-?[0-9,]+\.[0-9]{2})(?![0-9])',
      ) ??
      // A standalone amount label is a fallback, never a substring of net/item amounts.
      match(r'(?:^|\n)金额[:]?\s*[¥￥Y]?\s*(-?[0-9,]+\.[0-9]{2})(?![0-9])') ??
      (taxi ? match(r'[¥￥]\s*(-?[0-9,]+\.[0-9]{2})') : null);
  final cents = money((railway || aviation) ? travelTotal : total);
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
  fields.addAll(invoicePartiesFromText(compact));
  if (aviation) {
    final issuer = match(r'填开单位[:]?([^\n:]{2,200})');
    if (issuer != null) {
      fields['seller'] = issuer
          .split(RegExp(r'填开日期|购买方|统一社会信用代码|纳税人识别号'))
          .first;
    }
  }
  final missing = [
    for (final key in invoiceRequiredFields(fields))
      if (!fields.containsKey(key)) key,
  ];
  return InvoiceRecognition(
    fields,
    missing.isEmpty ? '' : '部分票面字段未能可靠提取，请核对原件。',
  );
}

/// Parse each page independently. Attachments never fill another page's fields.
InvoiceRecognition parseInvoicePages(Map<String, Object?> payload) {
  final pages = (payload['pages'] as List? ?? [payload]).cast<Map>();
  final candidates = <InvoiceRecognition>[];
  for (final raw in pages) {
    final page = Map<String, Object?>.from(raw);
    final structured = parseStructuredPayload(page);
    final text = (page['lines'] as List? ?? [])
        .map(
          (line) => ((line as Map)['words'] as List)
              .map((word) => '${(word as Map)['text'] ?? ''}')
              .join(' '),
        )
        .join('\n');
    final fallback = parseInvoiceText(text);
    final fields = <String, Object?>{...fallback.fields, ...structured.fields};
    final complete = invoiceRequiredFields(fields).every(fields.containsKey);
    candidates.add(
      InvoiceRecognition(
        fields,
        !complete
            ? '部分票面字段未能可靠提取，请核对原件。'
            : structured.message.contains('校验')
            ? structured.message
            : '',
        structured: {...structured.structure, 'page': page['page'] ?? 0},
      ),
    );
  }
  if (candidates.isEmpty) {
    return const InvoiceRecognition({}, '未检测到 PDF 文本层，请核对原件。');
  }
  final chosen =
      candidates
          .where(
            (r) =>
                r.fields.containsKey('number') && r.fields.containsKey('title'),
          )
          .firstOrNull ??
      candidates.first;
  final numbers = candidates
      .map((r) => r.fields['number'])
      .whereType<String>()
      .toSet();
  return numbers.length > 1
      ? InvoiceRecognition(
          chosen.fields,
          '检测到多张发票，仅识别首张票面，请拆分后分别导入并核对。',
          structured: chosen.structured,
        )
      : chosen;
}

abstract final class InvoiceRecognizer {
  static const requiredKeys = ['title', 'number', 'issued', 'cents'];
  static bool _complete(Map<String, Object?> fields) =>
      invoiceRequiredFields(fields).every(fields.containsKey);

  /// preferOcr 来自设置中的「优先使用 OCR」开关（默认关闭）。
  /// 默认优先 PDF 文本层：词坐标结构化解析更准，也不需要 OCR 模型。
  /// 2026-11-17 起的兜底策略（与用户确认）：
  /// - 个人购买方票面本就没有购方税号，required 规则已按组织/个人区分，
  ///   判为完整即直接返回，不再触发 OCR；
  /// - 文本层完整却没有票种标题、全文无「发票」字样的文档（行程单等）
  ///   不是发票：直接退出 PDF 解析，只做一次小模型 OCR 复核；
  /// - 其余不完整情形才保留原有 OCR 兜底（渲染 + 两轮识别）。
  /// 同一文件重复识别走结果缓存（大小+修改时间校验），约 0.1ms 命中。
  static Future<InvoiceRecognition> recognize(
    InvoiceFile file, {
    bool preferOcr = false,
  }) async {
    final cached = _results[file.path];
    if (cached != null && cached.$3 == preferOcr) {
      try {
        final stat = await File(file.path).stat();
        if (stat.size == cached.$1 && stat.modified == cached.$2) {
          return cached.$4;
        }
      } catch (_) {}
      _results.remove(file.path);
    }
    final result = await _recognize(file, preferOcr);
    try {
      final stat = await File(file.path).stat();
      _results[file.path] = (stat.size, stat.modified, preferOcr, result);
      while (_results.length > 64) {
        _results.remove(_results.keys.first);
      }
    } catch (_) {}
    return result;
  }

  /// 识别结果缓存：路径 -> (大小, 修改时间, preferOcr, 结果)。
  static final Map<String, (int, DateTime, bool, InvoiceRecognition)>
  _results = {};

  static Future<InvoiceRecognition> _recognize(
    InvoiceFile file,
    bool preferOcr,
  ) async {
    if (!file.isPdf) return _image(file.path);
    final pdf = await _pdfText(file.path);
    if (!preferOcr) {
      if (pdf.message.isEmpty && _complete(pdf.fields)) return pdf;
      final text = pdf.textLayer;
      if (text != null &&
          text.characters >= 120 &&
          pdf.fields['title'] == null &&
          !text.invoiceKeyword) {
        return _nonInvoiceReview(pdf, file.path);
      }
    }
    final ocr = await _pdfOcr(
      file.path,
      pageIndex: pdf.structured?['page'] as int? ?? 0,
    );
    if (ocr == null) return pdf;
    return preferOcr ? _merge(ocr, pdf) : _merge(pdf, ocr);
  }

  /// 非发票文档（行程单等）：一次小模型 OCR 复核；仍识别不出票面字段
  /// 即维持「不是发票」结论，不再做增强轮。
  static Future<InvoiceRecognition> _nonInvoiceReview(
    InvoiceRecognition pdf,
    String path,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'space-invoice-ocr-',
    );
    try {
      final bytes = await NativeInvoicePdf.ocrImage(path);
      final image = '${directory.path}/page.png';
      await File(image).writeAsBytes(bytes);
      final small = await LocalPpocr.recognize(image);
      final ocr = await _ocr(small);
      if (ocr.fields.isEmpty) {
        return InvoiceRecognition(
          pdf.fields,
          '未识别出发票票面，请核对原件。',
          structured: pdf.structured,
          textLayer: pdf.textLayer,
        );
      }
      return _merge(pdf, ocr);
    } catch (_) {
      // OCR 模型或组件不可用时保留文本层结果，不让整次识别失败。
      return pdf;
    } finally {
      await directory.delete(recursive: true);
    }
  }

  static InvoiceRecognition _merge(
    InvoiceRecognition primary,
    InvoiceRecognition fallback,
  ) {
    if (primary.fields['number'] != null &&
        fallback.fields['number'] != null &&
        primary.fields['number'] != fallback.fields['number']) {
      return InvoiceRecognition(
        primary.fields,
        '文字层与 OCR 票号不同，已保留当前页结果，请核对原件。',
        structured: primary.structured,
      );
    }
    final fields = <String, Object?>{...fallback.fields, ...primary.fields};
    return InvoiceRecognition(
      fields,
      !_complete(fields)
          ? '部分票面字段未能可靠提取，请核对原件。'
          : primary.message.contains('校验') || primary.message.contains('多张')
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
    final recognition = await Isolate.run(() => parseInvoicePages(payload));
    return InvoiceRecognition(
      recognition.fields,
      recognition.message,
      structured: recognition.structured,
      textLayer: (
        characters: pdf.characters,
        invoiceKeyword: _mentionsInvoice(payload),
      ),
    );
  }

  /// 文本层任何一页是否出现「发票」字样。行程单等非发票文档没有。
  static bool _mentionsInvoice(Map<String, Object?> payload) {
    bool pageHas(Map<Object?, Object?> page) {
      for (final line in (page['lines'] as List? ?? const [])) {
        for (final word in ((line as Map)['words'] as List? ?? const [])) {
          if ('${(word as Map)['text'] ?? ''}'.contains('发票')) return true;
        }
      }
      return false;
    }

    if (pageHas(payload)) return true;
    for (final page in (payload['pages'] as List? ?? const [])) {
      if (pageHas(page as Map)) return true;
    }
    return false;
  }

  static Future<InvoiceRecognition?> _pdfOcr(
    String path, {
    int pageIndex = 0,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'space-invoice-ocr-',
    );
    try {
      final bytes = await NativeInvoicePdf.ocrImage(path, pageIndex: pageIndex);
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
        : math.max(3.0, words.map((w) => w.h).reduce(math.max) * .6);
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
        !_complete(fields) ? '部分票面字段未能可靠提取，请核对原件。' : structured.message,
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
  for (final key in [
    'number',
    'issued',
    'cents',
    'tax_cents',
    'net_cents',
    'buyer',
    'seller',
    'buyer_tax',
    'seller_tax',
  ]) {
    final a = initial.fields[key], b = enhanced.fields[key];
    if (a != null && b != null && a != b) {
      fields.remove(key);
      conflicts.add(key);
    }
  }
  final complete =
      ['title', 'number', 'issued', 'cents'].every(fields.containsKey) &&
      invoiceRequiredFields(fields).every(fields.containsKey);
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
