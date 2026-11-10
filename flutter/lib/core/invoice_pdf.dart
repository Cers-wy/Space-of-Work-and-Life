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
  final double top, right, bottom, left;

  const InvoiceLayout({
    this.landscape = false,
    this.cutLines = true,
    this.perPage = 2,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
    this.left = 0,
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
    if ([top, right, bottom, left].any((v) => !v.isFinite || v < 0) ||
        usableW < 10 * pointPerMillimeter ||
        usableH < 10 * pointPerMillimeter) {
      throw StateError('边距需为非负数字，纸张至少保留 10 × 10 mm 的排版区域');
    }
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

    Map<String, Object> sheet(
      List<InvoiceSourcePage> sources, {
      bool attachment = false,
    }) {
      final cols = attachment ? 1 : columns;
      final rowCount = attachment ? 1 : rows;
      final slotW = usableW / cols;
      final slotH = usableH / rowCount;
      final slots = <Map<String, Object>>[];
      for (var i = 0; i < sources.length; i++) {
        final s = sources[i];
        final scale = math.min(slotW / s.width, slotH / s.height);
        final w = s.width * scale, h = s.height * scale;
        slots.add({
          'path': s.path,
          'page': s.page,
          'crop': [s.x, s.y, s.width, s.height],
          'rect': [
            leftPt + i % cols * slotW + (slotW - w) / 2,
            bottomPt + (rowCount - i ~/ cols) * slotH - h,
            w,
            h,
          ],
        });
      }
      return {
        'width': width,
        'height': height,
        'slots': slots,
        'lines': [
          if (cutLines && !attachment) ...[
            for (var i = 1; i < cols; i++)
              [
                leftPt + i * slotW,
                bottomPt,
                leftPt + i * slotW,
                bottomPt + usableH,
              ],
            for (var i = 1; i < rowCount; i++)
              [
                leftPt,
                bottomPt + i * slotH,
                leftPt + usableW,
                bottomPt + i * slotH,
              ],
          ],
        ],
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
