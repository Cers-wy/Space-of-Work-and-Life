import 'package:flutter_test/flutter_test.dart';

/// pumpAndSettle advances fake time, not the real file reads used by a preview.
/// Wait for its loading state to finish before closing/removing its fixture.
Future<void> settleFilePreview(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (find.text('正在加载图片…').evaluate().isEmpty) return;
  }
  fail('File preview did not finish its real I/O');
}
