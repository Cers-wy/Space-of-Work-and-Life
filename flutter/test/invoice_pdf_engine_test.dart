import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:pdfium_flutter/pdfium_flutter.dart' as pdfium;
import 'package:space_flutter/core/invoice_pdf.dart';
import 'package:space_flutter/core/invoice_pdf_engine.dart';

// Synthetic data only: PNG predictor 15, RGB QR pattern, transparent red seal,
// 16-bit icon, nonzero/out-of-range CropBox and a footer outside the visible page.
void main() {
  const fixture = 'test/fixtures/invoice-predictor-crop.pdf';
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('space-pdf-engine-');
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'visible page excludes the cropped footer and retains fine issuer text',
    () async {
      final full = (await InvoicePdf.inspect(fixture, trim: false)).single;
      expect(full.width, closeTo(595.275, .01));
      expect(full.height, closeTo(409, .01));
      final trimmed = (await InvoicePdf.inspect(fixture, trim: true)).single;
      expect(
        trimmed.y,
        greaterThan(15),
        reason: 'outside footer must not extend crop',
      );
      expect(trimmed.y, lessThan(23), reason: 'fine issuer text must remain');
      expect(trimmed.height, inExclusiveRange(370, 380));
    },
  );

  test(
    'object import preserves predictor image bytes and supports save/preview',
    () async {
      final source = (await InvoicePdf.inspect(fixture, trim: true)).single;
      final sheets = const InvoiceLayout().arrange([source, source], []);
      final bytes = await NativeInvoicePdf.compose(sheets);
      expect(
        _imageHashes(bytes),
        _imageHashes(await File(fixture).readAsBytes()),
      );
      final target = '${directory.path}/merged.pdf';
      await NativeInvoicePdf.write(target, sheets);
      expect(
        _imageHashes(await File(target).readAsBytes()),
        _imageHashes(bytes),
      );
      final rendered = image.decodePng(await InvoicePdf.render(sheets.single))!;
      final saved = await InvoicePdf.preview(target, 1);
      expect(saved.pages, 1);
      expect(image.decodePng(saved.bytes), isNotNull);
      final red = rendered
          .where((p) => p.r > 150 && p.g < 150 && p.b < 150)
          .length;
      expect(red, greaterThan(1000), reason: 'transparent seal remains red');
      await expectLater(InvoicePdf.preview(target, 2), throwsStateError);
    },
  );

  test(
    'rotation and nonzero CropBox use the same coordinates in inspection and export',
    () async {
      final sources = await InvoicePdf.inspect(
        'test/fixtures/invoice-rotations.pdf',
        trim: true,
      );
      expect(sources.length, 4);
      expect(sources[0].width, closeTo(sources[2].width, 1));
      expect(sources[0].height, closeTo(sources[1].width, 1));
      expect(sources[0].width, closeTo(sources[1].height, 1));
      for (var i = 0; i < sources.length; i++) {
        final sheets = const InvoiceLayout(
          perPage: 1,
        ).arrange([sources[i]], []);
        final bytes = await NativeInvoicePdf.compose(sheets);
        expect(_imageHashes(bytes).length, 3);
        final raster = image.decodePng(await InvoicePdf.render(sheets.single))!;
        expect(
          raster.where((p) => p.r > 150 && p.g < 150 && p.b < 150).length,
          greaterThan(300),
          reason: 'rotation $i must preserve visible seal',
        );
      }
    },
  );

  test(
    'image inputs and independent attachments compose without PDF-only assumptions',
    () async {
      final picture = image.Image(width: 320, height: 160, numChannels: 4);
      image.fill(picture, color: image.ColorRgba8(220, 20, 30, 255));
      final png = File('${directory.path}/image.png');
      await png.writeAsBytes(image.encodePng(picture));
      final source = (await InvoicePdf.inspect(png.path, trim: true)).single;
      expect(source.width, closeTo(320, .01));
      final attachment = (await InvoicePdf.inspect(
        fixture,
        trim: false,
      )).single;
      final sheets = const InvoiceLayout().arrange([source], [attachment]);
      expect(sheets.length, 2);
      expect(sheets.last['lines'], isEmpty);
      final path = '${directory.path}/with-attachment.pdf';
      await NativeInvoicePdf.write(path, sheets);
      expect((await InvoicePdf.preview(path, 2)).pages, 2);
      final raster = image.decodePng(await InvoicePdf.render(sheets.first))!;
      expect(
        raster.where((p) => p.r > 150 && p.g < 100).length,
        greaterThan(10000),
      );
    },
  );
}

Set<String> _imageHashes(Uint8List bytes) {
  // The shared engine has initialized PDFium before these synchronous checks.
  pdfium.PdfiumProcessGate.acquire();
  final buffer = malloc<Uint8>(bytes.length);
  try {
    final api = Platform.isMacOS
        ? pdfium.getPdfium(
            modulePath: File(
              'build/native_assets/macos/libpdfium.dylib',
            ).absolute.path,
          )
        : pdfium.pdfiumBindings;
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    final doc = api.FPDF_LoadMemDocument64(
      buffer.cast(),
      bytes.length,
      nullptr,
    );
    if (doc == nullptr) throw StateError('fixture cannot be opened');
    final hashes = <String>{};
    void visit(pdfium.FPDF_PAGEOBJECT object) {
      final type = api.FPDFPageObj_GetType(object);
      if (type == pdfium.FPDF_PAGEOBJ_IMAGE) {
        final size = api.FPDFImageObj_GetImageDataRaw(object, nullptr, 0);
        final data = malloc<Uint8>(size);
        try {
          api.FPDFImageObj_GetImageDataRaw(object, data.cast(), size);
          hashes.add(sha256.convert(data.asTypedList(size)).toString());
        } finally {
          malloc.free(data);
        }
      } else if (type == pdfium.FPDF_PAGEOBJ_FORM) {
        for (var i = 0; i < api.FPDFFormObj_CountObjects(object); i++) {
          visit(api.FPDFFormObj_GetObject(object, i));
        }
      }
    }

    try {
      for (var i = 0; i < api.FPDF_GetPageCount(doc); i++) {
        final page = api.FPDF_LoadPage(doc, i);
        try {
          for (var j = 0; j < api.FPDFPage_CountObjects(page); j++) {
            visit(api.FPDFPage_GetObject(page, j));
          }
        } finally {
          api.FPDF_ClosePage(page);
        }
      }
    } finally {
      api.FPDF_CloseDocument(doc);
    }
    return hashes;
  } finally {
    malloc.free(buffer);
    pdfium.PdfiumProcessGate.release();
  }
}
