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
  final value = raw
      .split(RegExp(_boundary))
      .first
      .replaceFirst(RegExp(r'^[：:\s]+'), '')
      .trim();
  if (value.length < 2 ||
      value.length > 200 ||
      value.contains('税务局') ||
      RegExp(r'^(信息|名称|购|买|销|售|方|单位|[0-9A-Z]+)$').hasMatch(value)) {
    return null;
  }
  return value;
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
      final tax = RegExp('$_taxLabel[：:/／]?([A-Z0-9]{15,20})(?![A-Z0-9])')
          .firstMatch(rest)
          ?.group(1);
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
  final regions = <({String text, double x, double y, double h})>[];
  for (final line in lines) {
    // Split at column boundaries, including labels that follow a long company.
    final groups = <List<InvoiceWord>>[];
    for (final w in line.words) {
      if (groups.isEmpty ||
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
                    ((v.y - r.y).abs() <= r.h * .6 && v.x > r.x) ||
                    (v.y > r.y &&
                        v.y - r.y <= r.h * 2 &&
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
    var tax = RegExp('$_taxLabel[：:/／]?([A-Z0-9]{15,20})(?![A-Z0-9])')
        .firstMatch(r.text)
        ?.group(1);
    if (tax == null && RegExp('^$_taxLabel[：:/／]?\$').hasMatch(r.text)) {
      tax = valuesNearLabel()
          .where((v) => RegExp(r'^[A-Z0-9]{15,20}$').hasMatch(v.text))
          .firstOrNull
          ?.text;
    }
    if (tax != null) out.putIfAbsent('${side}_tax', () => tax);
  }
  return out;
}
