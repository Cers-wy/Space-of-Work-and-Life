import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as image;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'invoice_pdf.dart';

class WindowsInvoicePdf {
  // The Windows printing plugin owns the bundled PDFium library. Keep our
  // worker calls and the plugin's print calls from entering it concurrently.
  static Future<void> _idle = Future.value();

  static Future<T> _serial<T>(Future<T> Function() work) {
    final result = _idle.then((_) => work());
    _idle = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static Future<List<InvoiceSourcePage>> inspect(
    String path,
    String extension, {
    required bool trim,
  }) => _serial(
    () => Isolate.run(() {
      final bytes = File(path).readAsBytesSync();
      if (extension != 'pdf') {
        final picture = _picture(bytes);
        return [
          (
            path: path,
            page: 1,
            x: 0.0,
            y: 0.0,
            width: picture.width.toDouble(),
            height: picture.height.toDouble(),
          ),
        ];
      }
      return _pdfium.withDocument(
        bytes,
        (document) => [
          for (var index = 0; index < _pdfium.pageCount(document); index++)
            _pdfium.withPage(document, index, (page, width, height) {
              final (x, y, w, h) = trim
                  ? _bounds(
                      _pdfium.raster(page, width, height, 560),
                      width,
                      height,
                    )
                  : (0.0, 0.0, width, height);
              return (
                path: path,
                page: index + 1,
                x: x,
                y: y,
                width: w,
                height: h,
              );
            }),
        ],
      );
    }),
  );

  static Future<InvoicePreview> preview(String path, int index) => _serial(
    () => Isolate.run(
      () => _pdfium.withDocument(
        File(path).readAsBytesSync(),
        (document) =>
            _pdfium.withPage(document, index - 1, (page, width, height) {
              final raster = _pdfium.raster(page, width, height, 900);
              return InvoicePreview(
                image.encodePng(raster),
                _pdfium.pageCount(document),
              );
            }),
      ),
    ),
  );

  static Future<Uint8List> render(Map<String, Object> sheet) => _serial(
    () => Isolate.run(() async {
      final pdf = await _compose([sheet], limit: 1150);
      return _pdfium.withDocument(
        pdf,
        (document) => _pdfium.withPage(
          document,
          0,
          (page, width, height) =>
              image.encodePng(_pdfium.raster(page, width, height, 880)),
        ),
      );
    }),
  );

  static Future<Uint8List> compose(List<Map<String, Object>> sheets) =>
      _serial(() => Isolate.run(() => _compose(sheets)));

  static Future<void> print(
    InvoiceLayout layout,
    List<Map<String, Object>> sheets,
  ) => _serial(() async {
    final bytes = await Isolate.run(() => _compose(sheets));
    await Printing.layoutPdf(
      name: '发票合并.pdf',
      format: PdfPageFormat(layout.width, layout.height),
      dynamicLayout: false,
      onLayout: (_) => bytes,
    );
  });

  static image.Image _picture(Uint8List bytes) {
    final decoded = image.decodeImage(bytes);
    if (decoded == null) throw StateError('无法打开图片');
    return image.bakeOrientation(decoded).convert(
      format: image.Format.uint8,
      numChannels: 4,
    );
  }

  static (double, double, double, double) _bounds(
    image.Image raster,
    double width,
    double height,
  ) {
    var left = raster.width, top = raster.height, right = -1, bottom = -1;
    for (final pixel in raster) {
      if (pixel.r < 246 || pixel.g < 246 || pixel.b < 246) {
        left = math.min(left, pixel.x);
        top = math.min(top, pixel.y);
        right = math.max(right, pixel.x);
        bottom = math.max(bottom, pixel.y);
      }
    }
    if (right < 0) return (0, 0, width, height);
    final xScale = width / raster.width, yScale = height / raster.height;
    final x = math.max(0.0, left * xScale - 4);
    final y = math.max(0.0, height - (bottom + 1) * yScale - 4);
    return (
      x,
      y,
      math.min(width, (right + 1) * xScale + 4) - x,
      math.min(height, height - top * yScale + 4) - y,
    );
  }

  static Future<Uint8List> _compose(
    List<Map<String, Object>> sheets, {
    int limit = 2600,
  }) async {
    if (sheets.isEmpty) throw StateError('没有可保存的发票');
    final document = PdfDocument(deflate: zlib.encode);
    for (final sheet in sheets) {
      final page = PdfPage(
        document,
        pageFormat: PdfPageFormat(
          sheet['width']! as double,
          sheet['height']! as double,
        ),
      );
      final graphics = page.getGraphics();
      for (final slot in sheet['slots']! as List<Map<String, Object>>) {
        final path = slot['path']! as String;
        final crop = slot['crop']! as List<double>;
        final rect = slot['rect']! as List<double>;
        final bytes = File(path).readAsBytesSync();
        final image.Image content;
        if (path.toLowerCase().endsWith('.pdf')) {
          content = _pdfium.withDocument(
            bytes,
            (source) => _pdfium.withPage(source, (slot['page']! as int) - 1, (
              sourcePage,
              width,
              height,
            ) {
              final raster = _pdfium.raster(sourcePage, width, height, limit);
              return _crop(raster, crop, width, height);
            }),
          );
        } else {
          final picture = _picture(bytes);
          content = math.max(picture.width, picture.height) <= limit
              ? picture
              : image.copyResize(
                  picture,
                  width: picture.width >= picture.height ? limit : null,
                  height: picture.height > picture.width ? limit : null,
                  interpolation: image.Interpolation.average,
                );
        }
        graphics.drawImage(
          PdfImage(
            document,
            image: content.getBytes(order: image.ChannelOrder.rgba),
            width: content.width,
            height: content.height,
          ),
          rect[0],
          rect[1],
          rect[2],
          rect[3],
        );
      }
      graphics
        ..setStrokeColor(const PdfColor(.58, .58, .58))
        ..setLineWidth(.5)
        ..setLineDashPattern([4, 3]);
      for (final line in sheet['lines']! as List<List<double>>) {
        graphics.drawLine(line[0], line[1], line[2], line[3]);
      }
      graphics.strokePath();
    }
    return document.save();
  }

  static image.Image _crop(
    image.Image raster,
    List<double> crop,
    double width,
    double height,
  ) {
    final x = (crop[0] * raster.width / width).floor().clamp(
      0,
      raster.width - 1,
    );
    final y = ((height - crop[1] - crop[3]) * raster.height / height)
        .floor()
        .clamp(0, raster.height - 1);
    final right = ((crop[0] + crop[2]) * raster.width / width).ceil().clamp(
      x + 1,
      raster.width,
    );
    final bottom = ((height - crop[1]) * raster.height / height).ceil().clamp(
      y + 1,
      raster.height,
    );
    return image.copyCrop(
      raster,
      x: x,
      y: y,
      width: right - x,
      height: bottom - y,
    );
  }
}

final _pdfium = _Pdfium();

class _Pdfium {
  final _library = DynamicLibrary.open('pdfium.dll');
  late final _open = _library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Size, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Void>, int, Pointer<Utf8>)
      >('FPDF_LoadMemDocument64');
  late final _close = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('FPDF_CloseDocument');
  late final pageCount = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('FPDF_GetPageCount');
  late final _loadPage = _library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Int32),
        Pointer<Void> Function(Pointer<Void>, int)
      >('FPDF_LoadPage');
  late final _closePage = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('FPDF_ClosePage');
  late final _width = _library
      .lookupFunction<
        Float Function(Pointer<Void>),
        double Function(Pointer<Void>)
      >('FPDF_GetPageWidthF');
  late final _height = _library
      .lookupFunction<
        Float Function(Pointer<Void>),
        double Function(Pointer<Void>)
      >('FPDF_GetPageHeightF');
  late final _bitmap = _library
      .lookupFunction<
        Pointer<Void> Function(Int32, Int32, Int32, Pointer<Void>, Int32),
        Pointer<Void> Function(int, int, int, Pointer<Void>, int)
      >('FPDFBitmap_CreateEx');
  late final _destroy = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('FPDFBitmap_Destroy');
  late final _fill = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Int32, Int32, Int32, UnsignedLong),
        int Function(Pointer<Void>, int, int, int, int, int)
      >('FPDFBitmap_FillRect');
  late final _render = _library
      .lookupFunction<
        Void Function(
          Pointer<Void>,
          Pointer<Void>,
          Int32,
          Int32,
          Int32,
          Int32,
          Int32,
          Int32,
        ),
        void Function(
          Pointer<Void>,
          Pointer<Void>,
          int,
          int,
          int,
          int,
          int,
          int,
        )
      >('FPDF_RenderPageBitmap');

  T withDocument<T>(Uint8List bytes, T Function(Pointer<Void>) use) {
    final buffer = malloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final document = _open(buffer.cast(), bytes.length, nullptr);
      if (document == nullptr) throw StateError('无法打开 PDF，文件可能已损坏或加密');
      try {
        return use(document);
      } finally {
        _close(document);
      }
    } finally {
      malloc.free(buffer);
    }
  }

  T withPage<T>(
    Pointer<Void> document,
    int index,
    T Function(Pointer<Void>, double, double) use,
  ) {
    if (index < 0 || index >= pageCount(document)) {
      throw StateError('PDF 页码超出范围');
    }
    final page = _loadPage(document, index);
    if (page == nullptr) throw StateError('无法读取 PDF 页');
    try {
      final width = _width(page), height = _height(page);
      if (!width.isFinite || !height.isFinite || width < 1 || height < 1) {
        throw StateError('PDF 页面尺寸无效');
      }
      return use(page, width, height);
    } finally {
      _closePage(page);
    }
  }

  image.Image raster(
    Pointer<Void> page,
    double width,
    double height,
    int limit,
  ) {
    final scale = limit / math.max(width, height);
    final w = math.max(1, (width * scale).round());
    final h = math.max(1, (height * scale).round());
    final size = w * h * 4;
    final pixels = malloc<Uint8>(size);
    try {
      const bgra = 4;
      final bitmap = _bitmap(w, h, bgra, pixels.cast(), w * 4);
      if (bitmap == nullptr) throw StateError('无法生成 PDF 预览');
      try {
        if (_fill(bitmap, 0, 0, w, h, 0xffffffff) == 0) {
          throw StateError('无法初始化 PDF 预览');
        }
        const annotations = 1;
        _render(bitmap, page, 0, 0, w, h, 0, annotations);
        return image.Image.fromBytes(
          width: w,
          height: h,
          bytes: pixels.asTypedList(size).buffer,
          numChannels: 4,
          order: image.ChannelOrder.bgra,
        );
      } finally {
        _destroy(bitmap);
      }
    } finally {
      malloc.free(pixels);
    }
  }
}
