import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/ui/image_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('4K预览按物理像素解码、重建复用，关闭后移除专属缓存', (t) async {
    final source = (await t.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(4000, 2000);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return base64Encode(data!.buffer.asUint8List());
    }))!;
    Widget preview() => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2),
        child: Center(
          child: SizedBox(width: 480, child: RichImagePreview(source: source)),
        ),
      ),
    );
    await t.pumpWidget(preview());
    final provider = t.widget<Image>(find.byType(Image)).image;
    final size = await t.runAsync(() async {
      // Start the asynchronous platform decoder outside the fake test clock.
      await provider.evict();
      final decoded = Completer<Size>();
      final stream = provider.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener((info, _) {
        if (!decoded.isCompleted) {
          decoded.complete(
            Size(info.image.width.toDouble(), info.image.height.toDouble()),
          );
        }
      }, onError: decoded.completeError);
      stream.addListener(listener);
      try {
        return await decoded.future.timeout(const Duration(seconds: 10));
      } finally {
        stream.removeListener(listener);
      }
    });
    expect(size, const Size(960, 480));
    await t.pumpWidget(preview());
    expect(
      identical(t.widget<Image>(find.byType(Image)).image, provider),
      isTrue,
    );
    final key = await provider.obtainKey(ImageConfiguration.empty);
    await t.pumpWidget(const SizedBox());
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(
      PaintingBinding.instance.imageCache.statusForKey(key).keepAlive,
      isFalse,
    );
    expect(
      PaintingBinding.instance.imageCache.statusForKey(key).pending,
      isFalse,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('无效预览数据保留错误提示，图片替换后不复用旧内容', (t) async {
    const source =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==';
    Widget preview(String value) =>
        MaterialApp(home: RichImagePreview(source: value));
    await t.pumpWidget(preview(source));
    final provider = t.widget<Image>(find.byType(Image)).image;
    await t.pumpWidget(preview('invalid%%%'));
    expect(find.text('图片无法预览，原字节已保留'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await t.pumpWidget(preview(source));
    expect(
      identical(t.widget<Image>(find.byType(Image)).image, provider),
      isFalse,
    );
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });
}
