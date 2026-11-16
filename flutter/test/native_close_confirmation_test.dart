import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/host.dart';
import 'package:space_flutter/main.dart';
import 'package:space_flutter/store.dart';

void main() {
  late Directory dir;
  late SpaceStore store;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('space-close-');
    store = SpaceStore(SpaceRepository(dir));
    await store.initialize();
  });
  tearDown(() async {
    store.dispose();
    DesktopHost.hasUnsavedEdits = false;
    await dir.delete(recursive: true);
  });
  testWidgets(
    'native close request preserves edits on cancel and finishes only after discard',
    (t) async {
      var finished = 0;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DesktopHost.channel,
        (call) async {
          if (call.method == 'finishClose') finished++;
          if (call.method == 'accessibility') return <String, bool>{};
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          DesktopHost.channel,
          null,
        ),
      );
      await t.pumpWidget(SpaceApp(store: store));
      await t.pumpAndSettle();
      Future<void> request() async {
        final done = Completer<void>();
        t.binding.defaultBinaryMessenger.handlePlatformMessage(
          DesktopHost.channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('requestClose', {'dirty': true}),
          ),
          (_) => done.complete(),
        );
        await t.pumpAndSettle();
      }

      await request();
      expect(find.text('放弃未保存的更改？'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(finished, 0);
      await request();
      await t.tap(find.text('放弃更改并退出'));
      await t.pumpAndSettle();
      expect(finished, 1);
      await t.pumpWidget(const SizedBox());
    },
  );
}
