import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/drive.dart';
import 'package:space_flutter/ui/file_drive.dart';
import 'package:space_flutter/ui/theme.dart';

void main() {
  testWidgets('首页进度卡片在浅深色和有限高度下可用，退出提示仅三个选择', (tester) async {
    final dir = Directory.systemTemp.createTempSync('space232-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = DriveService(dir)..activeBatch = 'batch';
    for (var i = 0; i < 7; i++) {
      service.tasks.add(
        UploadTask(
          id: '$i',
          source: 'sample',
          name: '项目文件$i.pdf',
          batch: 'batch',
          device: '测试设备',
          size: 100,
          modified: 0,
          created: DateTime(2026, 11, 12),
          status: i < 2 ? UploadStatus.complete : UploadStatus.uploading,
          progress: .5,
        ),
      );
    }
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: spaceTheme(dark),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                height: 208,
                child: DriveToolCard(
                  service: service,
                  uploads: () {},
                  files: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('2 / 7 已完成'), findsOneWidget);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: spaceTheme(false),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showUploadExit(context, 3),
              child: const Text('退出检查'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('退出检查'));
    await tester.pumpAndSettle();
    expect(find.text('继续上传'), findsOneWidget);
    expect(find.text('上传完成后退出'), findsOneWidget);
    expect(find.text('停止上传并退出'), findsOneWidget);
    expect(find.textContaining('Space'), findsNothing);
    await tester.tap(find.text('继续上传'));
    await tester.pumpAndSettle();
    expect(find.text('仍有文件未上传完成'), findsNothing);
  });
}
