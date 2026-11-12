import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as image;
import 'package:pdfium_flutter/pdfium_flutter.dart' as pdfium;

import 'invoices.dart';
import 'invoice_pdf.dart';

/// Both desktop platforms use the same PDF geometry, renderer and object import.
/// Only native printing remains platform specific. PDF work stays off the UI
/// isolate and is serialized with Windows' printing plugin, which also uses PDFium.
abstract final class NativeInvoicePdf {
  static Future<void> _idle = Future.value();

  static Future<T> serial<T>(Future<T> Function() work) {
    final result = _idle.then((_) => work());
    _idle = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static Future<T> _work<T>(T Function(_Engine) work) =>
      serial(() => _run(work));

  static Future<T> _run<T>(T Function(_Engine) work) => Isolate.run(() {
    // Initialization must survive short-lived worker isolates and hot restarts.
    pdfium.PdfiumProcessGate.enable();
    pdfium.PdfiumProcessGate.acquire();
    try {
      // Flutter tests bundle a dylib instead of linking the Darwin framework.
      // pdfium_dart 0.4.1's test loader still looks for the old YAML manifest;
      // Flutter 3.47 writes native_assets.json, so use its known build output.
      final api =
          Platform.isMacOS && Platform.environment.containsKey('FLUTTER_TEST')
          ? pdfium.getPdfium(
              modulePath: File(
                'build/native_assets/macos/libpdfium.dylib',
              ).absolute.path,
            )
          : pdfium.pdfiumBindings;
      if (pdfium.PdfiumProcessGate.claimInit()) api.FPDF_InitLibrary();
      return work(_Engine(api));
    } finally {
      pdfium.PdfiumProcessGate.release();
    }
  });

  static Future<List<InvoiceSourcePage>> inspect(
    String path, {
    required bool trim,
  }) => _work((engine) {
    validateInvoiceFile(path);
    return engine.withSource(
      path,
      (doc) => [
        for (var i = 0; i < engine.api.FPDF_GetPageCount(doc); i++)
          engine.withPage(doc, i, (page, width, height) {
            final crop = trim
                ? engine.contentBounds(page, width, height)
                : [0.0, 0.0, width, height];
            return (
              path: path,
              page: i + 1,
              x: crop[0],
              y: crop[1],
              width: crop[2],
              height: crop[3],
            );
          }),
      ],
    );
  });

  static Future<InvoicePreview> preview(String path, int index) => _work(
    (engine) => engine.withSource(path, (doc) {
      final count = engine.api.FPDF_GetPageCount(doc);
      return engine.withPage(doc, index - 1, (page, width, height) {
        final raster = engine.raster(page, width, height, 1200);
        return InvoicePreview(image.encodePng(raster), count);
      });
    }),
  );

  static Future<Uint8List> render(Map<String, Object> sheet) => _work(
    (engine) => engine.withSheets(
      [sheet],
      (doc) => engine.withPage(
        doc,
        0,
        (page, width, height) =>
            image.encodePng(engine.raster(page, width, height, 1600)),
      ),
    ),
  );

  static Future<void> write(String path, List<Map<String, Object>> sheets) =>
      _work(
        (engine) => engine.withSheets(sheets, (doc) {
          final file = File(path).openSync(mode: FileMode.write);
          try {
            engine.save(doc, (bytes) => file.writeFromSync(bytes));
          } finally {
            file.closeSync();
          }
        }),
      );

  static Future<Uint8List> compose(List<Map<String, Object>> sheets) =>
      serial(() => composeForPrint(sheets));

  /// Caller holds [serial] until Windows' native print dialog has completed.
  static Future<Uint8List> composeForPrint(List<Map<String, Object>> sheets) =>
      _run(
        (engine) => engine.withSheets(sheets, (doc) {
          final bytes = BytesBuilder();
          engine.save(doc, bytes.add);
          return bytes.takeBytes();
        }),
      );
}

class _Engine {
  final pdfium.PDFium api;
  _Engine(this.api);

  T withBytes<T>(Uint8List bytes, T Function(pdfium.FPDF_DOCUMENT) use) {
    final buffer = malloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final doc = api.FPDF_LoadMemDocument64(
        buffer.cast(),
        bytes.length,
        nullptr,
      );
      if (doc == nullptr) throw StateError('无法打开 PDF，文件可能已损坏或加密');
      try {
        return use(doc);
      } finally {
        api.FPDF_CloseDocument(doc);
      }
    } finally {
      malloc.free(buffer);
    }
  }

  T withSource<T>(String path, T Function(pdfium.FPDF_DOCUMENT) use) {
    if (!path.toLowerCase().endsWith('.pdf')) {
      return withImage(path, use);
    }
    final nativePath = path.toNativeUtf8();
    try {
      final doc = api.FPDF_LoadDocument(nativePath.cast(), nullptr);
      if (doc == nullptr) throw StateError('无法打开 PDF，文件可能已损坏或加密');
      try {
        return use(doc);
      } finally {
        api.FPDF_CloseDocument(doc);
      }
    } finally {
      malloc.free(nativePath);
    }
  }

  T withImage<T>(String path, T Function(pdfium.FPDF_DOCUMENT) use) {
    var picture = image.decodeImage(File(path).readAsBytesSync());
    if (picture == null) throw StateError('无法打开图片');
    picture = image.bakeOrientation(picture);
    if (math.max(picture.width, picture.height) > 2600) {
      picture = image.copyResize(
        picture,
        width: picture.width >= picture.height ? 2600 : null,
        height: picture.height > picture.width ? 2600 : null,
        interpolation: image.Interpolation.average,
      );
    }
    final rgba = picture.convert(format: image.Format.uint8, numChannels: 4);
    final data = rgba.getBytes(order: image.ChannelOrder.bgra);
    final pixels = malloc<Uint8>(data.length);
    pdfium.FPDF_BITMAP bitmap = nullptr;
    pdfium.FPDF_DOCUMENT doc = nullptr;
    try {
      pixels.asTypedList(data.length).setAll(0, data);
      bitmap = api.FPDFBitmap_CreateEx(
        rgba.width,
        rgba.height,
        pdfium.FPDFBitmap_BGRA,
        pixels.cast(),
        rgba.width * 4,
      );
      if (bitmap == nullptr) throw StateError('无法读取图片');
      doc = api.FPDF_CreateNewDocument();
      if (doc == nullptr) throw StateError('无法准备图片页');
      final page = api.FPDFPage_New(
        doc,
        0,
        rgba.width.toDouble(),
        rgba.height.toDouble(),
      );
      if (page == nullptr) throw StateError('无法准备图片页');
      try {
        final object = api.FPDFPageObj_NewImageObj(doc);
        if (object == nullptr) throw StateError('无法导入图片');
        if (api.FPDFImageObj_SetBitmap(nullptr, 0, object, bitmap) == 0) {
          api.FPDFPageObj_Destroy(object);
          throw StateError('无法导入图片');
        }
        api.FPDFPageObj_Transform(
          object,
          rgba.width.toDouble(),
          0,
          0,
          rgba.height.toDouble(),
          0,
          0,
        );
        api.FPDFPage_InsertObject(page, object);
        if (api.FPDFPage_GenerateContent(page) == 0) {
          throw StateError('无法生成图片页');
        }
      } finally {
        api.FPDF_ClosePage(page);
      }
      return use(doc);
    } finally {
      if (doc != nullptr) api.FPDF_CloseDocument(doc);
      if (bitmap != nullptr) api.FPDFBitmap_Destroy(bitmap);
      malloc.free(pixels);
    }
  }

  T withPage<T>(
    pdfium.FPDF_DOCUMENT doc,
    int index,
    T Function(pdfium.FPDF_PAGE, double, double) use,
  ) {
    if (index < 0 || index >= api.FPDF_GetPageCount(doc)) {
      throw StateError('PDF 页码超出范围');
    }
    final page = api.FPDF_LoadPage(doc, index);
    if (page == nullptr) throw StateError('无法读取 PDF 页');
    try {
      // PDFium applies CropBox ∩ MediaBox, their nonzero origin and /Rotate.
      final width = api.FPDF_GetPageWidthF(page);
      final height = api.FPDF_GetPageHeightF(page);
      if (!width.isFinite || !height.isFinite || width < 1 || height < 1) {
        throw StateError('PDF 页面尺寸无效');
      }
      return use(page, width, height);
    } finally {
      api.FPDF_ClosePage(page);
    }
  }

  image.Image raster(
    pdfium.FPDF_PAGE page,
    double width,
    double height,
    int limit,
  ) {
    final scale = limit / math.max(width, height);
    final w = math.max(1, (width * scale).round());
    final h = math.max(1, (height * scale).round());
    final pixels = malloc<Uint8>(w * h * 4);
    try {
      final bitmap = api.FPDFBitmap_CreateEx(
        w,
        h,
        pdfium.FPDFBitmap_BGRA,
        pixels.cast(),
        w * 4,
      );
      if (bitmap == nullptr) throw StateError('无法生成 PDF 预览');
      try {
        api.FPDFBitmap_FillRect(bitmap, 0, 0, w, h, 0xffffffff);
        api.FPDF_RenderPageBitmap(
          bitmap,
          page,
          0,
          0,
          w,
          h,
          0,
          pdfium.FPDF_ANNOT,
        );
        return image.Image.fromBytes(
          width: w,
          height: h,
          bytes: pixels.asTypedList(w * h * 4).buffer,
          numChannels: 4,
          order: image.ChannelOrder.bgra,
        );
      } finally {
        api.FPDFBitmap_Destroy(bitmap);
      }
    } finally {
      malloc.free(pixels);
    }
  }

  List<double> contentBounds(
    pdfium.FPDF_PAGE page,
    double width,
    double height,
  ) {
    final rasterImage = raster(page, width, height, 1800);
    var left = rasterImage.width,
        top = rasterImage.height,
        right = -1,
        bottom = -1;
    // Keep ALL visible marks, including fine issuer/footer text. The renderer
    // already excludes anything outside the original effective visible page.
    for (final pixel in rasterImage) {
      if (pixel.r < 242 || pixel.g < 242 || pixel.b < 242) {
        left = math.min(left, pixel.x);
        right = math.max(right, pixel.x);
        top = math.min(top, pixel.y);
        bottom = math.max(bottom, pixel.y);
      }
    }
    if (right < left || bottom < top) return [0, 0, width, height];
    const padding = .5 * InvoiceLayout.pointPerMillimeter;
    final sx = width / rasterImage.width, sy = height / rasterImage.height;
    final x = math.max(0.0, left * sx - padding);
    final y = math.max(0.0, height - (bottom + 1) * sy - padding);
    final r = math.min(width, (right + 1) * sx + padding);
    final t = math.min(height, height - top * sy + padding);
    return [x, y, r - x, t - y];
  }

  T withSheets<T>(
    List<Map<String, Object>> sheets,
    T Function(pdfium.FPDF_DOCUMENT) use,
  ) {
    if (sheets.isEmpty) throw StateError('没有可保存的发票');
    final doc = api.FPDF_CreateNewDocument();
    if (doc == nullptr) throw StateError('无法创建 PDF');
    final templates = <String, pdfium.FPDF_XOBJECT>{};
    try {
      for (var i = 0; i < sheets.length; i++) {
        final sheet = sheets[i];
        final page = api.FPDFPage_New(
          doc,
          i,
          sheet['width']! as double,
          sheet['height']! as double,
        );
        if (page == nullptr) throw StateError('无法创建 PDF 页');
        try {
          for (final slot in sheet['slots']! as List<Map<String, Object>>) {
            final path = slot['path']! as String;
            final index = (slot['page']! as int) - 1;
            final crop = slot['crop']! as List<double>;
            final rect = slot['rect']! as List<double>;
            final key = '$path\u0000$index\u0000${crop.join(',')}';
            final template = templates.putIfAbsent(
              key,
              () => _croppedTemplate(doc, path, index, crop),
            );
            final object = api.FPDF_NewFormObjectFromXObject(template);
            if (object == nullptr) throw StateError('无法放置发票页');
            // The template is normalized to a (0,0) crop origin. Use ONE scale
            // for both axes; never redraw/re-encode the source image objects.
            final scale = math.min(rect[2] / crop[2], rect[3] / crop[3]);
            api.FPDFPageObj_Transform(
              object,
              scale,
              0,
              0,
              scale,
              rect[0],
              rect[1],
            );
            api.FPDFPage_InsertObject(page, object);
          }
          for (final line in sheet['lines']! as List<List<double>>) {
            final path = api.FPDFPageObj_CreateNewPath(line[0], line[1]);
            if (path == nullptr) throw StateError('无法绘制裁剪线');
            api.FPDFPath_LineTo(path, line[2], line[3]);
            api.FPDFPageObj_SetStrokeColor(path, 166, 173, 184, 255);
            api.FPDFPageObj_SetStrokeWidth(path, .4);
            final dash = calloc<Float>(2);
            try {
              dash[0] = 3;
              dash[1] = 3;
              api.FPDFPageObj_SetDashArray(path, dash, 2, 0);
            } finally {
              calloc.free(dash);
            }
            api.FPDFPath_SetDrawMode(path, 0, 1);
            api.FPDFPage_InsertObject(page, path);
          }
          if (api.FPDFPage_GenerateContent(page) == 0) {
            throw StateError('无法生成 PDF 页内容');
          }
        } finally {
          api.FPDF_ClosePage(page);
        }
      }
      return use(doc);
    } finally {
      for (final template in templates.values) {
        api.FPDF_CloseXObject(template);
      }
      api.FPDF_CloseDocument(doc);
    }
  }

  pdfium.FPDF_XOBJECT _croppedTemplate(
    pdfium.FPDF_DOCUMENT dest,
    String path,
    int index,
    List<double> crop,
  ) => withSource(
    path,
    (source) => withPage(source, index, (sourcePage, w, h) {
      if (crop.length != 4 ||
          !crop.every((v) => v.isFinite) ||
          crop[0] < 0 ||
          crop[1] < 0 ||
          crop[2] <= 0 ||
          crop[3] <= 0 ||
          crop[0] + crop[2] > w + .01 ||
          crop[1] + crop[3] > h + .01) {
        throw StateError('发票裁剪范围无效');
      }
      // Flatten printable annotations in memory only; original files are untouched.
      if (api.FPDFPage_Flatten(sourcePage, pdfium.FLAT_PRINT) == 0) {
        throw StateError('无法保留 PDF 批注');
      }
      final scratch = api.FPDF_CreateNewDocument();
      if (scratch == nullptr) throw StateError('无法准备发票页');
      try {
        final page = api.FPDFPage_New(scratch, 0, w, h);
        if (page == nullptr) throw StateError('无法准备发票页');
        try {
          final original = api.FPDF_NewXObjectFromPage(scratch, source, index);
          if (original == nullptr) throw StateError('无法导入原始 PDF 页');
          try {
            final object = api.FPDF_NewFormObjectFromXObject(original);
            if (object == nullptr) throw StateError('无法导入原始 PDF 内容');
            api.FPDFPage_InsertObject(page, object);
            if (api.FPDFPage_GenerateContent(page) == 0) {
              throw StateError('无法生成发票内容');
            }
          } finally {
            api.FPDF_CloseXObject(original);
          }
          // First import normalizes original rotation/nonzero boxes. Cropping the
          // wrapper page gives the final Form a real BBox clip, per invoice.
          api.FPDFPage_SetMediaBox(
            page,
            crop[0],
            crop[1],
            crop[0] + crop[2],
            crop[1] + crop[3],
          );
          api.FPDFPage_SetCropBox(
            page,
            crop[0],
            crop[1],
            crop[0] + crop[2],
            crop[1] + crop[3],
          );
        } finally {
          api.FPDF_ClosePage(page);
        }
        final result = api.FPDF_NewXObjectFromPage(dest, scratch, 0);
        if (result == nullptr) throw StateError('无法裁剪发票页');
        return result;
      } finally {
        api.FPDF_CloseDocument(scratch);
      }
    }),
  );

  void save(pdfium.FPDF_DOCUMENT doc, void Function(Uint8List) write) {
    final writer = calloc<pdfium.FPDF_FILEWRITE>();
    Object? failure;
    final callback =
        NativeCallable<
          Int Function(
            Pointer<pdfium.FPDF_FILEWRITE>,
            Pointer<Void>,
            UnsignedLong,
          )
        >.isolateLocal((
          Pointer<pdfium.FPDF_FILEWRITE> _,
          Pointer<Void> data,
          int size,
        ) {
          try {
            write(data.cast<Uint8>().asTypedList(size));
            return 1;
          } catch (e) {
            failure = e;
            return 0;
          }
        }, exceptionalReturn: 0);
    try {
      writer.ref.version = 1;
      writer.ref.WriteBlock = callback.nativeFunction;
      if (api.FPDF_SaveAsCopy(doc, writer, pdfium.FPDF_NO_INCREMENTAL) == 0 ||
          failure != null) {
        throw StateError('无法保存 PDF${failure == null ? '' : '：$failure'}');
      }
    } finally {
      callback.close();
      calloc.free(writer);
    }
  }
}
