import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../host.dart';
import 'files.dart';
import 'invoices.dart';
import 'invoice_pdf_windows.dart';

class InvoicePreview {
  final Uint8List bytes;
  final int pages;
  const InvoicePreview(this.bytes, this.pages);
}

typedef InvoiceSourcePage = ({
  String path,
  int page,
  double x,
  double y,
  double width,
  double height,
});

class InvoiceLayout {
  static const pointPerMillimeter = 72 / 25.4;
  final bool landscape, cutLines;
  final int perPage;
  final double top, right, bottom, left, gap;

  const InvoiceLayout({
    this.landscape = false,
    this.cutLines = true,
    this.perPage = 2,
    this.top = 5,
    this.right = 5,
    this.bottom = 5,
    this.left = 5,
    this.gap = 10,
  });

  double get width => (landscape ? 297 : 210) * pointPerMillimeter;
  double get height => (landscape ? 210 : 297) * pointPerMillimeter;

  List<Map<String, Object>> arrange(
    List<InvoiceSourcePage> invoices,
    List<InvoiceSourcePage> attachments,
  ) {
    if (perPage < 1 || perPage > 4) throw StateError('请选择每页 1–4 张发票');
    final leftPt = left * pointPerMillimeter,
        bottomPt = bottom * pointPerMillimeter;
    final usableW = width - (left + right) * pointPerMillimeter;
    final usableH = height - (top + bottom) * pointPerMillimeter;
    if ([top, right, bottom, left, gap].any((v) => !v.isFinite || v < 0) ||
        usableW < 10 * pointPerMillimeter ||
        usableH < 10 * pointPerMillimeter) {
      throw StateError('边距与票间距需为非负数字，纸张至少保留 10 × 10 mm 的排版区域');
    }
    final gapPt = gap * pointPerMillimeter;
    final columns = perPage == 4
        ? 2
        : landscape
        ? perPage
        : 1;
    final rows = perPage == 4
        ? 2
        : landscape
        ? 1
        : perPage;

    // 按「满格」计算槽位，末页发票数量不足时沿用同样大小，避免跨页尺寸跳变。
    final slotW = (usableW - (columns - 1) * gapPt) / columns;
    final slotH = (usableH - (rows - 1) * gapPt) / rows;
    if (slotW < 10 * pointPerMillimeter || slotH < 10 * pointPerMillimeter) {
      throw StateError('票间距或边距过大，当前纸张放不下这么多发票');
    }

    Map<String, Object> sheet(
      List<InvoiceSourcePage> sources, {
      bool attachment = false,
    }) {
      final cols = attachment ? 1 : columns;
      final cellW = attachment ? usableW : slotW;
      final cellH = attachment ? usableH : slotH;
      // 同一页统一比例：所有发票按最小可用比例缩放，保持字号与票面一致。
      var scale = double.infinity;
      for (final s in sources) {
        scale = math.min(scale, math.min(cellW / s.width, cellH / s.height));
      }
      if (!scale.isFinite || scale <= 0) scale = 1;
      final usedRows = (sources.length + cols - 1) ~/ cols;
      final heights = <double>[];
      for (var r = 0; r < usedRows; r++) {
        var rowHeight = 0.0;
        for (var c = 0; c < cols; c++) {
          final i = r * cols + c;
          if (i < sources.length) {
            rowHeight = math.max(rowHeight, sources[i].height * scale);
          }
        }
        heights.add(rowHeight);
      }
      final contentH =
          heights.fold<double>(0, (a, b) => a + b) +
          math.max(0, usedRows - 1) * gapPt;
      // 内容整体在可用区域内垂直居中，余量平均分给上下两侧。
      var cursor = bottomPt + (usableH + contentH) / 2;
      final startTop = cursor;
      final slots = <Map<String, Object>>[];
      for (var r = 0; r < usedRows; r++) {
        final rowBottom = cursor - heights[r];
        for (var c = 0; c < cols; c++) {
          final i = r * cols + c;
          if (i >= sources.length) continue;
          final s = sources[i];
          final w = s.width * scale, h = s.height * scale;
          slots.add({
            'path': s.path,
            'page': s.page,
            'crop': [s.x, s.y, s.width, s.height],
            'rect': [
              leftPt + c * (slotW + gapPt) + (cellW - w) / 2,
              rowBottom + (heights[r] - h) / 2,
              w,
              h,
            ],
          });
        }
        cursor = rowBottom - gapPt;
      }
      final lines = <List<double>>[];
      if (cutLines && !attachment && sources.length > 1) {
        // 虚线落在相邻两张票之间的空白中线上，便于对折裁剪。
        var y = startTop;
        for (var r = 0; r < usedRows - 1; r++) {
          y -= heights[r] + gapPt / 2;
          lines.add([leftPt, y, leftPt + usableW, y]);
        }
        for (var c = 1; c < cols; c++) {
          final x = leftPt + c * (slotW + gapPt) - gapPt / 2;
          lines.add([x, bottomPt, x, bottomPt + usableH]);
        }
      }
      return {
        'width': width,
        'height': height,
        'slots': slots,
        'lines': lines,
      };
    }

    return [
      for (var i = 0; i < invoices.length; i += perPage)
        sheet(invoices.sublist(i, math.min(i + perPage, invoices.length))),
      for (final attachment in attachments)
        sheet([attachment], attachment: true),
    ];
  }
}

class InvoicePdf {
  static Future<T?> _call<T>(String method, Map<String, Object> args) async {
    if (!Platform.isMacOS) throw StateError('当前平台不支持 PDF 排版预览');
    try {
      return await DesktopHost.channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw StateError(e.message ?? '无法处理 PDF');
    }
  }

  static Future<List<InvoiceSourcePage>> inspect(
    String path, {
    required bool trim,
  }) async {
    final extension = await Isolate.run(() => validateInvoiceFile(path));
    if (Platform.isWindows) {
      return WindowsInvoicePdf.inspect(path, extension, trim: trim);
    }
    final pages = await _call<List<Object?>>('invoiceInspect', {
      'path': path,
      'trim': trim,
    });
    if (pages == null || pages.isEmpty) throw StateError('文件没有可用页');
    return [
      for (var i = 0; i < pages.length; i++)
        (
          path: path,
          page: i + 1,
          x: _coordinate(pages[i], 0),
          y: _coordinate(pages[i], 1),
          width: _coordinate(pages[i], 2),
          height: _coordinate(pages[i], 3),
        ),
    ];
  }

  static double _coordinate(Object? page, int i) =>
      ((page as List)[i] as num).toDouble();

  static Future<InvoicePreview> preview(String path, int page) async {
    if (Platform.isWindows) return WindowsInvoicePdf.preview(path, page);
    final r = (await _call<Map<Object?, Object?>>('invoicePreview', {
      'path': path,
      'page': page,
    }))!;
    return InvoicePreview(r['bytes'] as Uint8List, r['pages'] as int);
  }

  static Future<Uint8List> render(Map<String, Object> page) async =>
      Platform.isWindows
      ? WindowsInvoicePdf.render(page)
      : (await _call<Uint8List>('invoiceRender', {'sheet': page}))!;

  static Future<void> save(
    InvoiceRepository repo,
    String destination,
    List<Map<String, Object>> pages,
  ) async {
    repo.checkDestination(destination);
    final target = fileIdentity(destination);
    for (final page in pages) {
      for (final slot in page['slots']! as List<Map<String, Object>>) {
        if (target == fileIdentity(slot['path']! as String)) {
          throw StateError('请选择与原件不同的输出路径');
        }
      }
    }
    final staged = File(invoiceOutputStage(destination));
    try {
      if (Platform.isWindows) {
        await staged.writeAsBytes(await WindowsInvoicePdf.compose(pages));
      } else {
        await _call<void>('invoiceWrite', {
          'path': staged.path,
          'sheets': pages,
        });
      }
      await staged.rename(destination);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  static Future<void> print(
    InvoiceLayout layout,
    List<Map<String, Object>> pages,
  ) async {
    if (Platform.isWindows) {
      await WindowsInvoicePdf.print(layout, pages);
      return;
    }
    final directory = await Directory.systemTemp.createTemp('space-print-');
    final path = '${directory.path}/发票合并.pdf';
    try {
      await _call<void>('invoiceWrite', {'path': path, 'sheets': pages});
      await _call<void>('invoicePrint', {
        'path': path,
        'width': layout.width,
        'height': layout.height,
        'landscape': layout.landscape,
      });
    } finally {
      await directory.delete(recursive: true);
    }
  }
}
