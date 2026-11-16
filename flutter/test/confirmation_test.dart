import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/ui/confirmation.dart';
import 'package:space_flutter/ui/dialogs.dart';
import 'package:space_flutter/ui/invoice_details.dart';
import 'package:space_flutter/ui/theme.dart';

void main() {
  testWidgets(
    'themed confirmations keep cancel/confirm semantics and scroll long text',
    (t) async {
      t.view.physicalSize = const Size(500, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        bool? result;
        await t.pumpWidget(
          MaterialApp(
            theme: spaceTheme(dark),
            home: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () async {
                    result = await confirm(
                      c,
                      '删除条目？',
                      '测试说明。' * 160,
                      '删除',
                      destructive: true,
                    );
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('打开'));
        await t.pumpAndSettle();
        expect(find.byType(ConfirmationSurface), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(result, isFalse);
      }
    },
  );
  testWidgets(
    'invoice close preserves three distinct choices under both themes',
    (t) async {
      for (final dark in [false, true]) {
        String? result;
        await t.pumpWidget(
          MaterialApp(
            theme: spaceTheme(dark),
            home: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () async {
                    result = await confirmInvoiceClose(c);
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        );
        for (final choice in [
          ('取消', null),
          ('不保存', 'discard'),
          ('保存', 'save'),
        ]) {
          await t.tap(find.text('打开'));
          await t.pumpAndSettle();
          await t.tap(find.text(choice.$1));
          await t.pumpAndSettle();
          expect(result, choice.$2);
          expect(t.takeException(), isNull);
        }
      }
    },
  );
}
