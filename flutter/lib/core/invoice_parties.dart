import 'invoice_structured.dart';

String normalizeInvoiceLabels(String value) => value
    .replaceAll(RegExp(r'购\s*买\s*方'), '购买方')
    .replaceAll(RegExp(r'销\s*售\s*方'), '销售方')
    .replaceAll(RegExp(r'购\s*货\s*单\s*位'), '购货单位')
    .replaceAll(RegExp(r'销\s*货\s*单\s*位'), '销货单位');

const _taxLabel = r'(?:统一社会信用代码(?:[/／]纳税人识别号)?|纳税人识别号)';
const _boundary =
    r'统一社会信用代码|纳税人识别号|地址|电话|开户|发票号码|开票日期|填开日期|购买方|销售方|购货单位|销货单位|项目名称|货物或应税劳务|价税合计';

String? _company(String raw) {
  var value = raw
      .split(RegExp(_boundary))
      .first
      .replaceFirst(RegExp(r'^[：:\s]+'), '')
      .trim();
  // 竖排「购/销…方」标签单字在 PDF 中常与公司名归入同一视觉行（如
  // 「购 苏州恒力…」「销 大连滴滴…」），剥掉开头的标签字，避免名称带前缀。
  // 仅当剩余部分仍是较长名称时才剥，防止误伤以这些字开头的真实字号。
  final lead = RegExp(r'^[购买销售货单位]{1,3}');
  final stripped = value.replaceFirst(lead, '');
  if (stripped.length >= 2 && value.length - stripped.length <= 2) {
    value = stripped;
  }
  if (value.length < 2 ||
      value.length > 200 ||
      value.contains('税务局') ||
      RegExp(r'^(信息|名称|购|买|销|售|方|单位|[0-9A-Z]+)$').hasMatch(value)) {
    return null;
  }
  return value;
}

/// 从税号标签后的字符串中提取合法税号。页面边缘竖排的干扰字（如下载次数
/// 「1」）会贴在税号右侧，形成 19 位错误串；这里按合法长度优先 18 位截取，
/// 并校验字符集，避免取到截断或掺入干扰字符的错误税号。
String? _extractTaxIdAfterLabel(String source) {
  final m = RegExp('$_taxLabel[：:/／]?').firstMatch(source);
  return m == null ? null : _extractTaxId(source.substring(m.end));
}

String? _extractTaxId(String afterLabel) {
  final alnum = RegExp(r'^[A-Z0-9]+').firstMatch(afterLabel.trim())?.group(0);
  if (alnum == null) return null;
  // 按合法长度优先 18 位截取（统一社会信用代码 18 位，旧号 15/17/20 位）。
  // 关键：干扰字贴在税号右侧会形成 19 位错误串，优先取 18 位即可剔除尾部干扰。
  // 这里不校验字符集，以免误伤合成/测试税号以及含字母的旧纳税人识别号。
  for (final len in [18, 20, 17, 15]) {
    if (alnum.length >= len) return alnum.substring(0, len);
  }
  return null;
}

/// Explicit labels are safe even when coordinates are unavailable.
Map<String, Object?> invoicePartiesFromText(String source) {
  final text = normalizeInvoiceLabels(source)
      .replaceAll(RegExp(r'[ \t\u3000]'), '');
  final out = <String, Object?>{};
  for (final side in ['buyer', 'seller']) {
    final label = side == 'buyer' ? r'购买方|购货单位' : r'销售方|销货单位';
    for (final match in RegExp(
      '(?:$label)(?:信息)?(?:名称)?[：:]?',
    ).allMatches(text)) {
      final rest = text
          .substring(match.end)
          .split(RegExp(r'购买方|销售方|购货单位|销货单位|项目名称|货物或应税劳务|价税合计'))
          .first;
      final lines = rest.split('\n').where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) continue;
      var candidate = lines.first;
      if (candidate.startsWith('名称')) candidate = candidate.substring(2);
      final name = _company(candidate);
      if (name != null) out[side] = name;
      final tax = _extractTaxIdAfterLabel(rest);
      if (tax != null) out['${side}_tax'] = tax;
    }
  }
  return out;
}

/// Use explicit horizontal/vertical party labels before pairing names and tax IDs.
/// Unknown single-column labels remain empty instead of assuming left=buyer.
Map<String, Object?> invoiceParties(List<InvoiceTextLine> lines, double width) {
  final out = <String, Object?>{};
  final anchors = <({String side, double x, double y})>[];
  for (final line in lines) {
    for (final word in line.words) {
      final t = normalizeInvoiceLabels(word.compact);
      if (RegExp(r'购买方|购货单位').hasMatch(t)) {
        anchors.add((side: 'buyer', x: word.x, y: line.y));
      }
      if (RegExp(r'销售方|销货单位').hasMatch(t)) {
        anchors.add((side: 'seller', x: word.x, y: line.y));
      }
    }
  }
  // Old VAT forms print the side name vertically, often one glyph per text box.
  final glyphs = [
    for (final l in lines)
      ...l.words.where(
        (w) => w.compact.length == 1 && '购买销售方货单位'.contains(w.compact),
      ),
  ];
  for (final glyph in glyphs) {
    final column =
        glyphs
            .where(
              (w) =>
                  (w.x - glyph.x).abs() <= glyph.h * .65 &&
                  w.y >= glyph.y &&
                  w.y - glyph.y < glyph.h * 7,
            )
            .toList()
          ..sort((a, b) => a.y.compareTo(b.y));
    final text = column.map((w) => w.compact).join();
    if (text.startsWith('购买方') || text.startsWith('购货单位')) {
      anchors.add((side: 'buyer', x: glyph.x, y: glyph.y));
    }
    if (text.startsWith('销售方') || text.startsWith('销货单位')) {
      anchors.add((side: 'seller', x: glyph.x, y: glyph.y));
    }
  }
  final mid = width / 2;
  final regions = <({String text, double x, double y, double h})>[];
  for (final line in lines) {
    // Split at column boundaries, including labels that follow a long company.
    final groups = <List<InvoiceWord>>[];
    for (final w in line.words) {
      // 数电票购销两栏以页面中线为界：部分票（如中石油/滴滴/苏汽）同一视觉
      // 行上两个「统一社会信用代码」字形框仅隔 24–40pt，小于原 45pt 阈值，
      // 会把左右两个税号并进一个 region，只取到购买方税号，销售方税号丢失。
      // 中线是稳定的物理分界，跨中线必定属于另一栏，必须另起 region。
      final crossesMid =
          groups.isNotEmpty && w.x >= mid && groups.last.first.x < mid;
      if (groups.isEmpty ||
          crossesMid ||
          w.x - groups.last.last.right > 45 ||
          (RegExp(r'购买方|销售方|购货单位|销货单位').hasMatch(w.compact) &&
              groups.last.isNotEmpty)) {
        groups.add([]);
      }
      groups.last.add(w);
    }
    for (final group in groups) {
      regions.add((
        text: group.map((w) => w.compact).join(),
        x: group.first.x,
        y: line.y,
        h: group.first.h,
      ));
    }
  }
  final paired = regions.any(
    (r) =>
        r.x < width / 2 &&
        r.text.contains('名称') &&
        !r.text.contains('项目名称') &&
        regions.any(
          (v) =>
              v.x >= width / 2 &&
              (v.y - r.y).abs() < 8 &&
              v.text.contains('名称'),
        ),
  );
  String? sideAt(double x, double y) {
    var score = double.infinity;
    String? side;
    for (final a in anchors) {
      if (a.y > y + 12) continue;
      final value = (a.x - x).abs() + (y - a.y).abs() * .65;
      if (value < score) {
        score = value;
        side = a.side;
      }
    }
    return side ?? (paired ? (x < width / 2 ? 'buyer' : 'seller') : null);
  }

  for (final r in regions) {
    out.addAll(invoicePartiesFromText(r.text));
    final side = sideAt(r.x, r.y);
    if (side == null) continue;
    Iterable<({String text, double x, double y, double h})>
    valuesNearLabel() sync* {
      final nearby =
          regions
              .where(
                (v) =>
                    // 同一视觉行、位于标签右侧（名称：→公司名）。
                    ((v.y - r.y).abs() <= r.h * .6 && v.x > r.x) ||
                    // 标签在上、取值在紧邻下方一行（竖排标签或换行排版）。
                    (v.y > r.y &&
                        v.y - r.y <= r.h * 2 &&
                        (v.x - r.x).abs() < 60) ||
                    // 取值在上、标签在紧邻下方一行。部分滴滴票把公司名印在
                    // 「购/销」那行，而「名称：」标签单独落在下一行，导致
                    // 标签行只有「名称：」空值；需要向上找回同一栏的名称值。
                    (v.y < r.y &&
                        r.y - v.y <= r.h * 2 &&
                        (v.x - r.x).abs() < 60),
              )
              .toList()
            ..sort(
              (a, b) => ((a.y - r.y).abs() * 4 + (a.x - r.x).abs()).compareTo(
                (b.y - r.y).abs() * 4 + (b.x - r.x).abs(),
              ),
            );
      for (final v in nearby) {
        if (sideAt(v.x, v.y) == side &&
            !RegExp('$_boundary|名称').hasMatch(v.text)) {
          yield v;
        }
      }
    }

    final nameMatch = RegExp(r'(?<!项目)名称[：:]?(.*)$').firstMatch(r.text);
    String? name;
    if (nameMatch != null) {
      name = _company(nameMatch[1]!);
      if (name == null &&
          nameMatch[1]!.replaceAll(RegExp(r'[：:]'), '').isEmpty) {
        final next = valuesNearLabel()
            .where((v) => _company(v.text) != null)
            .firstOrNull;
        if (next != null) name = _company(next.text);
      }
    }
    if (name != null) out.putIfAbsent(side, () => name!);
    var tax = _extractTaxIdAfterLabel(r.text);
    if (tax == null && RegExp('^$_taxLabel[：:/／]?\$').hasMatch(r.text)) {
      tax = valuesNearLabel()
          .map((v) => _extractTaxId(v.text))
          .firstOrNull;
    }
    if (tax != null) out.putIfAbsent('${side}_tax', () => tax);
  }
  return out;
}
