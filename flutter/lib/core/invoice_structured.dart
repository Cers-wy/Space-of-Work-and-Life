import 'dart:math' as math;

/// 2026-11-12：按 output/invoice-parser/parser.js 的本地验证原型移植。
/// PDF 文本层与 OCR 共用「词坐标 -> 视觉行 -> 发票结构」解析，避免把整份
/// 文本压成一行后靠正则猜测左右栏和明细列。
class InvoiceWord {
  final double x, y, w, h;
  final String text;

  const InvoiceWord(this.x, this.y, this.w, this.h, this.text);

  double get right => x + w;
  String get compact => text.replaceAll(RegExp(r'\s+'), '');
}

class InvoiceTextLine {
  final double y;
  final List<InvoiceWord> words;

  const InvoiceTextLine(this.y, this.words);

  String get text => words.map((w) => w.text).join(' ');
  String get plain => words.map((w) => w.text).join();
  String get compact => plain.replaceAll(RegExp(r'\s+'), '');
  double get left => words.isEmpty ? 0 : words.first.x;
}

/// 逐字符导出的 PDF 按横向紧邻关系还原成词；OCR 行本身已是词，无需合并。
///
/// PDFium 的 `FPDFText_GetCharBox` 返回字形紧边框，不含字距，因此不能像
/// pdf.js 那样用固定 1.5pt 判断：按字符高度估算字距（约半字）更稳，既能把
/// 被拆开的「苏州恒力…」「208.35」拼回去，也不会跨过「名称 | 值」的栏间距。
List<InvoiceWord> mergeInvoiceChars(List<InvoiceWord> chars) {
  final sorted = [...chars]..sort((a, b) {
    final byY = a.y.compareTo(b.y);
    return byY != 0 ? byY : a.x.compareTo(b.x);
  });
  final out = <List<InvoiceWord>>[];
  for (final word in sorted) {
    final group = out.isEmpty ? null : out.last;
    final last = group?.last;
    // 用字符起点间距判断：PDFium 的字形盒宽度不可靠，字距更稳定。
    final pitch = last == null ? 0.0 : word.x - last.x;
    final limit = last == null
        ? 0.0
        : math.max(1.5, math.max(word.h, last.h) * 1.15);
    if (last != null &&
        (word.y - last.y).abs() < 1.2 &&
        word.x >= last.x - 0.5 &&
        pitch < limit) {
      group!.add(word);
    } else {
      out.add([word]);
    }
  }
  return [
    for (final group in out)
      InvoiceWord(
        group.first.x,
        group.first.y,
        group.last.right - group.first.x,
        group.map((w) => w.h).reduce(math.max),
        group.map((w) => w.text).join(),
      ),
  ];
}

/// 按基线 y 聚类为视觉行，行内按 x 排序。tol 需随字体大小/扫描抖动调整。
List<InvoiceTextLine> invoiceLines(
  List<InvoiceWord> words, {
  double tolerance = 4,
}) {
  final sorted = [...words]..sort((a, b) {
    final byY = a.y.compareTo(b.y);
    return byY != 0 ? byY : a.x.compareTo(b.x);
  });
  final groups = <List<InvoiceWord>>[];
  for (final word in sorted) {
    final group = groups.isEmpty ? null : groups.last;
    if (group != null && (word.y - group.first.y).abs() <= tolerance) {
      group.add(word);
    } else {
      groups.add([word]);
    }
  }
  return [
    for (final group in groups)
      InvoiceTextLine(
        group.first.y,
        [...group]..sort((a, b) => a.x.compareTo(b.x)),
      ),
  ];
}

const moneyCharacters = '壹贰叁肆伍陆柒捌玖拾佰仟万亿零圆元角分整正';

String _cleanMoney(String value) =>
    value.replaceAll(RegExp(r'[¥￥,，\s]'), '');

bool _isNumberToken(String value) =>
    RegExp(r'^-?\d+(?:\.\d+)?%?$').hasMatch(_cleanMoney(value));

int? _moneyCents(String? value) {
  if (value == null) return null;
  final clean = _cleanMoney(value);
  if (!RegExp(r'^-?\d{1,12}\.\d{2}$').hasMatch(clean)) return null;
  final negative = clean.startsWith('-');
  final parts = clean.replaceFirst('-', '').split('.');
  return (int.parse(parts[0]) * 100 + int.parse(parts[1])) *
      (negative ? -1 : 1);
}

String? _firstMatch(String source, String pattern, {int group = 1}) => RegExp(
  pattern,
  multiLine: true,
).firstMatch(source)?.group(group)?.trim();

String _isoDate(String raw) {
  final m = RegExp(
    r'(20\d{2})[年/.-](\d{1,2})[月/.-](\d{1,2})',
  ).firstMatch(raw);
  if (m == null) return '';
  final value =
      '${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}';
  return DateTime.tryParse(value)?.toIso8601String().startsWith(value) == true
      ? value
      : '';
}

class StructuredInvoice {
  final Map<String, Object?> fields;
  final Map<String, Object?> structure;
  final String message;

  const StructuredInvoice(this.fields, this.structure, this.message);
  bool get complete =>
      ['title', 'number', 'issued', 'cents'].every(fields.containsKey);
}

/// 把 OCR 的带坐标行转换为与 PDF 文本层相同的词；低置信度数字更严格。
List<InvoiceWord> invoiceWordsFromOcr(
  List<Map<String, dynamic>> lines, {
  double minConfidence = .90,
}) {
  final words = <InvoiceWord>[];
  for (final line in lines) {
    final text = (line['text'] as String? ?? '').trim();
    if (text.isEmpty) continue;
    final confidence = (line['confidence'] as num?)?.toDouble() ?? 0;
    final numeric = RegExp(
      r'[¥￥]|\d+\.\d{2}|^\d{8,20}$',
    ).hasMatch(text);
    if (confidence < (numeric ? .98 : minConfidence)) continue;
    final x = (line['x'] as num?)?.toDouble() ?? 0;
    final y = (line['y'] as num?)?.toDouble() ?? 0;
    final h = (line['height'] as num?)?.toDouble() ?? 12;
    // OCR 不返回词宽，按字符数估算；仅用于分栏与同线排序，不参与金额判断。
    final width = text.codeUnits.fold<double>(
      0,
      (sum, unit) => sum + (unit > 0x2e80 ? h : h * .55),
    );
    words.add(InvoiceWord(x, y, width, h, text));
  }
  return words;
}

/// 同一视觉行里按 x 的明显间隙切栏（购买方 / 销售方 / 右侧附加列）。
/// 间隙阈值取 45pt，正常字距和标签到取值的空隙不会被切开。
List<List<InvoiceWord>> _lineSegments(InvoiceTextLine line) {
  final words = [...line.words]..sort((a, b) => a.x.compareTo(b.x));
  final out = <List<InvoiceWord>>[];
  var current = <InvoiceWord>[];
  for (final word in words) {
    if (current.isNotEmpty && word.x - current.last.right >= 45) {
      out.add(current);
      current = [];
    }
    current.add(word);
  }
  if (current.isNotEmpty) out.add(current);
  return out;
}

/// 明细行里的「96.12」「3%」常被拆成单字符，按紧邻关系拼回数值词。
InvoiceTextLine _mergeNumberWords(InvoiceTextLine line) {
  final numeric = RegExp(r'^[0-9¥￥.,%+-]+$');
  final out = <InvoiceWord>[];
  for (final word in line.words) {
    final last = out.isEmpty ? null : out.last;
    final gap = last == null ? 0.0 : word.x - last.right;
    // 只在「半个数」边界拼接：小数点开头/结尾、百分号，或两个纯整数片段。
    // 两个已经完整的小数（如单价和金额）即使框贴在一起也不能拼。
    final decimals = last != null && last.text.contains('.')
        ? last.text.split('.').last.length
        : 0;
    final joinable =
        last != null &&
        (last.text.endsWith('.') ||
            word.text.startsWith('.') ||
            word.text.startsWith('%') ||
            (!last.text.contains('.') && !word.text.contains('.')) ||
            // 小数位还没补齐（如 "96.1" + "2"）继续拼；两位以上已是完整金额。
            (last.text.contains('.') && decimals <= 1));
    if (last != null &&
        numeric.hasMatch(last.text) &&
        numeric.hasMatch(word.text) &&
        joinable &&
        // 允许字形框轻微重叠，但明显重叠说明是相邻两列，不能拼。
        gap > -1.5 &&
        gap < 8) {
      out[out.length - 1] = InvoiceWord(
        last.x,
        last.y,
        math.max(last.right, word.right) - last.x,
        math.max(last.h, word.h),
        '${last.text}${word.text}',
      );
    } else {
      out.add(word);
    }
  }
  return InvoiceTextLine(line.y, out);
}

/// 有些 PDF 把小数点、冒号单独画在略低的基线上，会被当成独立一行。
/// 这类纯标点行按 x 重叠并回最近的有内容的行，保证「208.35」「名称：」完整。
List<InvoiceTextLine> _mergePunctuationLines(List<InvoiceTextLine> lines) {
  final punctuation = RegExp(r'^[.:：,，;；]+$');
  final out = <InvoiceTextLine>[];
  for (final line in lines) {
    if (line.words.isEmpty) continue;
    if (punctuation.hasMatch(line.compact)) {
      final previous = out.isEmpty ? null : out.last;
      final overlaps =
          previous != null &&
          line.words.first.x <= previous.words.last.x + 20 &&
          line.words.last.x >= previous.words.first.x - 20;
      // 小数点、冒号是标在基线附近的，语义上属于它上方那一行；只并入紧邻的
      // 上一行，避免把明细的小数点并到下一行的「合计」。
      if (previous != null &&
          overlaps &&
          (previous.y - line.y).abs() <= 12) {
        final merged = [...previous.words, ...line.words]
          ..sort((a, b) => a.x.compareTo(b.x));
        out[out.length - 1] = InvoiceTextLine(previous.y, merged);
        continue;
      }
    }
    out.add(line);
  }
  return out;
}

/// 解析视觉行。mid 由页面宽度给出，左右两栏分别对应购买方/销售方。
StructuredInvoice parseStructuredInvoice(
  List<InvoiceTextLine> lines, {
  double width = 297.6,
  String source = 'pdf-text',
}) {
  lines = _mergePunctuationLines(lines);
  final mid = width / 2;
  final all = lines.map((l) => l.compact).join('\n');
  final fields = <String, Object?>{};
  final items = <Map<String, Object?>>[];
  var invoiceType = '', specialType = '', totalInWords = '';
  var amount = '', taxAmount = '', total = '';
  final people = <String, Object?>{'payee': '', 'reviewer': '', 'drawer': ''};

  for (final line in lines) {
    final t = line.compact;
    if (invoiceType.isEmpty) {
      if (t.contains('电子发票') && t.contains('增值税专用发票')) {
        invoiceType = '电子发票（增值税专用发票）';
      } else if (t.contains('电子发票') && t.contains('普通发票')) {
        invoiceType = '电子发票（普通发票）';
      } else if (t.contains('增值税专用发票')) {
        invoiceType = '增值税专用发票';
      } else if (t.contains('增值税普通发票')) {
        invoiceType = '增值税普通发票';
      }
    }
    if (t.contains('成品油')) specialType = '成品油';
    if (t.contains('旅客运输服务') && specialType.isEmpty) {
      specialType = '旅客运输服务';
    }
  }
  if (invoiceType.isNotEmpty) fields['title'] = invoiceType;

  final number = _firstMatch(all, r'发票号码[:：]?\s*(\d{8,20})');
  if (number != null) fields['number'] = number;
  final code = _firstMatch(all, r'发票代码[:：]?\s*(\d{10,12})');
  final date = _firstMatch(
    all,
    r'开票日期[:：]?\s*(\d{4}年\d{1,2}月\d{1,2}日|\d{4}[-/]\d{1,2}[-/]\d{1,2})',
  );
  final issued = _isoDate(date ?? '');
  if (issued.isNotEmpty) fields['issued'] = issued;

  var buyer = '', seller = '', buyerTax = '', sellerTax = '';
  // 2026-11-12：数电票的购销方标签常被拆成单字、冒号另起一行，按「词」取值
  // 不可靠。改为把同一视觉行按 x 的明显间隙切成栏，再在每栏文本里做正则。
  final nameLabels = <(double, double)>[];
  for (final line in lines) {
    for (final segment in _lineSegments(line)) {
      final text = segment.map((w) => w.compact).join();
      if (!text.contains('名称') || text.contains('项目名称')) continue;
      final match = RegExp(r'名称[:：]?(.+)$').firstMatch(text);
      final value = match
          ?.group(1)
          ?.replaceAll(RegExp(r'[，,、;；:：\s]'), '')
          .replaceFirst(RegExp(r'^(购|销|买|售|方|信息)+'), '');
      if (value == null || value.isEmpty) {
        // 少数版式把「名称：」单独画在取值上方一行，先记下位置稍后配对。
        nameLabels.add((segment.first.x, line.y));
        continue;
      }
      if (segment.first.x < mid) {
        if (buyer.isEmpty) buyer = value;
      } else if (seller.isEmpty) {
        seller = value;
      }
    }
  }
  if (nameLabels.isNotEmpty) {
    for (final label in nameLabels) {
      var bestScore = double.infinity;
      List<InvoiceWord>? bestSegment;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if ((line.y - label.$2).abs() > 16) continue;
        for (final segment in _lineSegments(line)) {
          final text = segment.map((w) => w.compact).join();
          if (text.isEmpty ||
              text.contains('名称') ||
              text.contains('识别号') ||
              text.contains('项目') ||
              text.contains(RegExp(r'^[购销售买方]+$'))) {
            continue;
          }
          final dx = (segment.first.x - label.$1).abs();
          if (dx > 60) continue;
          final score = dx + (line.y - label.$2).abs();
          if (score < bestScore) {
            bestScore = score;
            bestSegment = segment;
          }
        }
      }
      if (bestSegment == null) continue;
      final value = bestSegment
          .map((w) => w.compact)
          .join()
          .replaceAll(RegExp(r'[，,、;；:：\s]'), '')
          .replaceFirst(RegExp(r'^(购|销|买|售|方|信息)+'), '');
      if (value.isEmpty) continue;
      if (label.$1 < mid) {
        if (buyer.isEmpty) buyer = value;
      } else if (seller.isEmpty) {
        seller = value;
      }
    }
  }
  for (final line in lines) {
    for (final segment in _lineSegments(line)) {
      final text = segment.map((w) => w.compact).join();
      if (!text.contains('纳税人识别号') && !text.contains('统一社会信用代码')) {
        continue;
      }
      final value =
          RegExp(
            r'(?:统一社会信用代码|纳税人识别号)[:：/]?([0-9A-Z]{15,20})',
          ).firstMatch(text)?.group(1) ??
          RegExp(r'\b([0-9A-Z]{15,20})\b').firstMatch(text)?.group(1) ??
          '';
      if (value.isEmpty || value == number) continue;
      if (segment.first.x < mid) {
        if (buyerTax.isEmpty) buyerTax = value;
      } else if (sellerTax.isEmpty) {
        sellerTax = value;
      }
    }
  }
  if (buyer.isNotEmpty && !buyer.contains('税务局')) fields['buyer'] = buyer;
  if (seller.isNotEmpty && !seller.contains('税务局')) fields['seller'] = seller;
  if (buyerTax.isNotEmpty) fields['buyer_tax'] = buyerTax;
  if (sellerTax.isNotEmpty) fields['seller_tax'] = sellerTax;

  // 明细区：表头之后、合计行之前。表头里被拆开的单字列名先拼回去。
  var headIdx = -1, totalIdx = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].compact.contains(RegExp(r'项目名称|货物或应税劳务|服务名称'))) {
      headIdx = i;
      break;
    }
  }
  var headers = <String>[];
  if (headIdx >= 0) {
    final headerWords = lines[headIdx].words;
    for (var i = 0; i < headerWords.length; i++) {
      final t = headerWords[i].compact;
      if (headers.isNotEmpty &&
          headers.last.length == 1 &&
          t.length == 1 &&
          i > 0 &&
          headerWords[i].x - headerWords[i - 1].x < 25) {
        headers.last = headers.last + t;
      } else {
        headers.add(t);
      }
    }
    for (var i = headIdx + 1; i < lines.length; i++) {
      if (lines[i].compact.startsWith('合计') ||
          lines[i].compact.startsWith('价税合计')) {
        totalIdx = i;
        break;
      }
    }
  }
  final detail = headIdx < 0
      ? <InvoiceTextLine>[]
      : lines
            .sublist(
              headIdx + 1,
              totalIdx > headIdx ? totalIdx : lines.length,
            )
            .map(_mergeNumberWords)
            .toList();
  var hasUnit = false, hasSpec = false, hasQuantity = false;
  for (final h in headers) {
    if (h.contains('单位')) hasUnit = true;
    if (h.contains('规格')) hasSpec = true;
    if (h.contains('数量')) hasQuantity = true;
  }

  for (final line in detail) {
    final numbers = <InvoiceWord>[];
    var firstNumber = -1;
    for (var i = 0; i < line.words.length; i++) {
      if (_isNumberToken(line.words[i].text)) {
        numbers.add(line.words[i]);
        if (firstNumber < 0) firstNumber = i;
      }
    }
    var rateIdx = -1;
    for (var i = 0; i < numbers.length; i++) {
      if (numbers[i].text.endsWith('%')) {
        rateIdx = i;
        break;
      }
    }
    if (rateIdx < 0 || numbers.length <= rateIdx + 1) {
      // 项目名称跨行续行：把左侧文本接回上一条明细。
      final t = line.compact;
      if (items.isNotEmpty &&
          t.isNotEmpty &&
          line.words.isNotEmpty &&
          line.words.first.x < mid &&
          !RegExp(r'^[备注注]$').hasMatch(t) &&
          !t.startsWith('开票人') &&
          !t.contains(RegExp(r'出行人|有效身份证件|销方开户银行|微信认证'))) {
        final last = items.last;
        last['name'] = '${last['name']}$t';
        last['raw'] = '${last['raw']} ${line.text}';
      }
      continue;
    }
    var quantity = '', unitPrice = '', itemAmount = '';
    final before = numbers.sublist(0, rateIdx);
    // 税率左侧最后一个是金额；再往前依次是单价、数量。比按表头名字映射稳，
    // 因为表头里的「金额」常被拆字或漏抽。
    if (before.isNotEmpty) {
      itemAmount = _cleanMoney(before.last.text);
      if (before.length >= 3 && hasQuantity) {
        quantity = _cleanMoney(before[before.length - 3].text);
        unitPrice = _cleanMoney(before[before.length - 2].text);
      }
    }
    final textWords = (firstNumber > 0
        ? line.words.sublist(0, firstNumber)
        : line.words).toList();
    var unit = '';
    if (hasUnit &&
        textWords.isNotEmpty &&
        textWords.last.compact.length <= 2) {
      unit = textWords.removeLast().text;
    }
    final parts = textWords
        .map((w) => w.text)
        .join(' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    var specification = '';
    if (hasSpec && parts.length >= 2) specification = parts.removeLast();
    final name = parts.join('');
    items.add({
      'name': name,
      'specification': specification,
      'unit': unit,
      'quantity': quantity,
      'unit_price': unitPrice,
      'amount': itemAmount,
      'tax_rate': numbers[rateIdx].text,
      'tax': _cleanMoney(numbers[rateIdx + 1].text),
      'raw': line.text,
    });
  }

  for (final line in lines) {
    if (!line.compact.startsWith('合计')) continue;
    // 小数点和数字常被拆成多个词，直接在整行文本上取两位小数最稳。
    final figures = RegExp(
      r'-?\d+\.\d{2}',
    ).allMatches(line.compact).map((m) => m.group(0)!).toList();
    if (figures.length >= 2) {
      amount = figures[0];
      taxAmount = figures[1];
    }
    break;
  }
  for (final line in lines) {
    if (!line.compact.contains('价税合计')) continue;
    final words = RegExp('[$moneyCharacters]{4,}').firstMatch(line.compact);
    if (words != null) totalInWords = words.group(0)!;
    final figures = RegExp(
      r'-?\d+\.\d{2}',
    ).allMatches(line.compact).map((m) => m.group(0)!).toList();
    if (figures.isNotEmpty) total = figures.last;
    break;
  }
  if (amount.isEmpty && items.isNotEmpty) {
    double sum(Iterable<Map<String, Object?>> source, String key) => source.fold(
      0.0,
      (value, item) => value + (double.tryParse('${item[key] ?? ''}') ?? 0),
    );
    amount = sum(items, 'amount').toStringAsFixed(2);
    taxAmount = sum(items, 'tax').toStringAsFixed(2);
  }
  final cents = _moneyCents(total);
  final taxCents = _moneyCents(taxAmount);
  final netCents = _moneyCents(amount);
  if (cents != null) fields['cents'] = cents;
  if (taxCents != null) fields['tax_cents'] = taxCents;
  if (netCents != null) fields['net_cents'] = netCents;

  // 人员标签常挤在同一视觉行，用下一个标签作为边界，避免把后面的人名吞进来。
  for (final entry in {
    'payee': ('收款人', '复核人|开票人'),
    'reviewer': ('复核人', '收款人|开票人'),
    'drawer': ('开票人', '收款人|复核人'),
  }.entries) {
    final value = _firstMatch(
      all,
      '${entry.value.$1}[:：]?(.+?)(?=${entry.value.$2}|\\n|\$)',
    );
    if (value != null && value.isNotEmpty) people[entry.key] = value;
  }

  double numeric(String value) =>
      double.tryParse(_cleanMoney(value).replaceAll('%', '')) ?? 0;
  final checks = <Map<String, Object?>>[];
  if (items.isNotEmpty) {
    final first = items.first;
    final quantity = numeric('${first['quantity']}');
    final unitPrice = numeric('${first['unit_price']}');
    if (quantity > 0 && unitPrice > 0) {
      final expected = quantity * unitPrice;
      checks.add({
        'name': '数量 × 单价 ≈ 金额',
        'expected': expected.toStringAsFixed(2),
        'actual': first['amount'],
        'ok': (expected - numeric('${first['amount']}')).abs() <= .02,
      });
    }
    final expectedTax =
        numeric('${first['amount']}') * numeric('${first['tax_rate']}') / 100;
    checks.add({
      'name': '金额 × 税率 ≈ 税额',
      'expected': expectedTax.toStringAsFixed(2),
      'actual': first['tax'],
      'ok': (expectedTax - numeric('${first['tax']}')).abs() <= .02,
    });
  }
  final expectedTotal = numeric(amount) + numeric(taxAmount);
  // 没有取到价税合计时不做金额一致性断言，避免把「无数据」误报成「校验失败」。
  final totalCheck = total.isEmpty ||
      (expectedTotal - numeric(total)).abs() <= .02;
  checks.add({
    'name': '金额 + 税额 = 价税合计',
    'expected': expectedTotal.toStringAsFixed(2),
    'actual': total,
    'ok': totalCheck,
  });
  final moneyConsistent =
      checks.isEmpty || checks.every((c) => c['ok'] == true);

  final structure = <String, Object?>{
    'source': source,
    'invoice_type': invoiceType,
    'special_category': specialType,
    'invoice_code': code ?? '',
    'buyer': {'name': buyer, 'tax_id': buyerTax},
    'seller': {'name': seller, 'tax_id': sellerTax},
    'items': items,
    'totals': {
      'amount': amount,
      'tax_amount': taxAmount,
      'total_in_words': totalInWords,
      'total': total,
      'currency': 'CNY',
    },
    'people': people,
    'checks': checks,
  };
  final missing = [
    for (final key in ['title', 'number', 'issued', 'cents'])
      if (!fields.containsKey(key)) key,
  ];
  final message = missing.isNotEmpty
      ? '部分票面字段未能可靠提取，请核对原件。'
      : !moneyConsistent
      ? '金额校验未通过，请核对原件。'
      : '';
  return StructuredInvoice(fields, structure, message);
}

/// Isolate 之间只传基础类型，自定义类实例不能直接发送。
Map<String, Object?> structuredLinesPayload(
  double width,
  List<InvoiceTextLine> lines, {
  String source = 'pdf-text',
  int characters = 0,
}) => {
  'source': source,
  'width': width,
  'characters': characters,
  'lines': [
    for (final line in lines)
      {
        'y': line.y,
        'words': [
          for (final word in line.words)
            {
              'x': word.x,
              'y': word.y,
              'w': word.w,
              'h': word.h,
              'text': word.text,
            },
        ],
      },
  ],
};

StructuredInvoice parseStructuredPayload(Map<String, Object?> payload) {
  double number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  final lines = <InvoiceTextLine>[];
  for (final raw in (payload['lines'] as List? ?? const [])) {
    final row = Map<String, Object?>.from(raw as Map);
    final words = <InvoiceWord>[];
    for (final item in (row['words'] as List? ?? const [])) {
      final word = Map<String, Object?>.from(item as Map);
      words.add(
        InvoiceWord(
          number(word['x']),
          number(word['y']),
          number(word['w']),
          number(word['h']),
          '${word['text'] ?? ''}',
        ),
      );
    }
    lines.add(InvoiceTextLine(number(row['y']), words));
  }
  return parseStructuredInvoice(
    lines,
    width: number(payload['width']),
    source: '${payload['source'] ?? 'pdf-text'}',
  );
}
