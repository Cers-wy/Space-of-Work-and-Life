import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/releases.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/settings_panel.dart';
import 'package:space_flutter/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.25, 1.5, 2.0]) {
      testWidgets('${dark ? 'dark' : 'light'} ${scale}x 设置背景/边框四角统一裁剪', (
        t,
      ) async {
        t.view.physicalSize = Size(1000 * scale, 700 * scale);
        t.view.devicePixelRatio = scale;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final dir = (await t.runAsync(
          () => Directory.systemTemp.createTemp('space-corners-'),
        ))!;
        final store = SpaceStore(SpaceRepository(dir));
        await t.runAsync(store.initialize);
        final updates = ReleaseChecker(
          infoLoader: () async => {'version': '2.1.0', 'build': '13'},
          releaseLoader: () async => [
            {
              'tag_name': '2.1.0',
              'draft': false,
              'prerelease': false,
              'html_url': '$projectUrl/releases/tag/2.1.0',
              'assets': [],
            },
          ],
        );
        final key = GlobalKey();
        final font = File('/System/Library/Fonts/STHeiti Medium.ttc');
        await t.runAsync(() async {
          if (font.existsSync()) {
            await (FontLoader(
              'PingFang SC',
            )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
          }
          await (FontLoader('PhosphorSettings')
                ..addFont(rootBundle.load('assets/icons/PhosphorSettings.ttf')))
              .load();
        });
        await t.pumpWidget(
          MaterialApp(
            theme: spaceTheme(dark),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(1000, 700),
                devicePixelRatio: scale,
                disableAnimations: true,
              ),
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: 960,
                    height: 640,
                    child: Material(
                      type: MaterialType.transparency,
                      child: SettingsPanel(store: store, updates: updates),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: scale);
          final raw = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final bytes = raw!.buffer.asUint8List();
          for (final xy in [
            (0, 0),
            (image.width - 1, 0),
            (0, image.height - 1),
            (image.width - 1, image.height - 1),
          ]) {
            expect(
              bytes[(xy.$2 * image.width + xy.$1) * 4 + 3],
              0,
              reason: '四角应完全透明，不应留矩形背景或边框',
            );
          }
          final inside = (20 * scale).round();
          expect(
            bytes[(inside * image.width + inside) * 4 + 3],
            255,
            reason: '圆角内表面应完整',
          );
          int brightness(int offset) {
            final i = (offset * image.width + offset) * 4;
            return bytes[i] + bytes[i + 1] + bytes[i + 2];
          }

          expect(
            brightness((5 * scale).floor()),
            greaterThan(brightness((8 * scale).round()) + 3),
            reason: '圆角弧线必须有连续边框，不能只裁剪背景而使用另一半径的内边框',
          );
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final out = Directory('verification/screenshots/2.1.0');
          await out.create(recursive: true);
          await File(
            '${out.path}/corners-${dark ? 'dark' : 'light'}-${scale.toString().replaceAll('.', '_')}x.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
        await t.pumpWidget(const SizedBox());
        store.dispose();
        updates.dispose();
        await t.runAsync(() => dir.delete(recursive: true));
      });
    }
  }
}
