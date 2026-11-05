import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/main.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/dialogs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late SpaceStore s;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('space211-');
    s = SpaceStore(SpaceRepository(dir));
    await s.initialize();
    await s.commit(demoState(count: 12), 'synthetic');
    s.notice = null;
  });
  tearDown(() async {
    s.dispose();
    await dir.delete(recursive: true);
  });
  Future<void> launch(WidgetTester t) async {
    t.view.physicalSize = const Size(1380, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await t.pumpWidget(SpaceApp(store: s));
    await t.pumpAndSettle();
  }

  test(
    'view defaults and temporary filters are independent, reset is scoped',
    () async {
      final options = {
        'board': 'work',
        'list': 'life',
        'gantt': 'personal',
        'calendar': 'work',
      };
      for (final e in options.entries) {
        await s.preference('viewMode', e.key);
        expect(s.query.hasFilters, false);
        s.query.categoryIDs.add(e.value);
        s.query.text = e.key;
        await s.saveDefaultFilters();
      }
      for (final e in options.entries) {
        await s.preference('viewMode', e.key);
        expect(s.query.text, e.key);
        expect(s.query.categoryIDs, {e.value});
      }
      await s.preference('viewMode', 'list');
      s.query.text = 'temporary';
      s.refreshQuery();
      await s.preference('viewMode', 'board');
      expect(s.query.text, 'board');
      await s.preference('viewMode', 'list');
      expect(s.query.text, 'temporary');
      await s.resetDefaultFilters();
      await s.reload();
      expect(s.query.hasFilters, false);
      await s.preference('viewMode', 'gantt');
      expect(s.query.text, 'gantt');
      expect(s.query.categoryIDs, {'personal'});
      s.query.text = '';
      s.refreshQuery();
      expect(s.visible.every((t) => t.category == 'personal'), true);
    },
  );
  test('legacy shared default migrates once to the active view', () async {
    final q = TaskQuery()
      ..text = 'old'
      ..category = 'work';
    await s.preferences({
      'viewMode': 'gantt',
      'defaultFilters': jsonEncode(q.toJson()),
    });
    await s.reload();
    expect(s.query.text, 'old');
    await s.preference('viewMode', 'calendar');
    expect(s.query.hasFilters, false);
    await s.reload();
    expect(s.query.hasFilters, false);
    await s.preference('viewMode', 'gantt');
    expect(s.query.text, 'old');
  });
  testWidgets('category panel starts below tabs without vertical centering', (
    t,
  ) async {
    await launch(t);
    showStatuses(t.element(find.byType(Navigator).first), s);
    await t.pumpAndSettle();
    await t.tap(find.text('任务分类'));
    await t.pumpAndSettle();
    final tabs = t.getRect(find.text('任务分类'));
    final note = t.getRect(find.text('分类可自定义或改名，已有任务会保留所属分类。'));
    expect(note.top - tabs.bottom, lessThan(64));
    expect(
      t.getRect(find.byType(TextField).last).top - note.bottom,
      lessThan(40),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('footer actions stay aligned, category gap and light backdrop', (
    t,
  ) async {
    await t.runAsync(
      () => s.preferences({'overviewCollapsed': 'true', 'appearance': 'light'}),
    );
    await launch(t);
    expect(
      t.getSize(find.byKey(const ValueKey('category-filter-gap'))).width,
      16,
    );
    await t.tap(
      find.byWidgetPredicate((w) => w is IconButtonS && w.label == '筛选与排序'),
    );
    await t.pumpAndSettle();
    final footer = find.byKey(const ValueKey('filter-footer'));
    for (final label in ['设为默认配置', '重置默认', '清除筛选']) {
      expect(
        find.descendant(of: footer, matching: find.text(label)),
        findsOneWidget,
      );
    }
    final rects = [
      for (final label in ['设为默认配置', '重置默认', '清除筛选'])
        t.getRect(find.text(label)),
    ];
    expect(rects[0].center.dy, closeTo(rects[2].center.dy, .1));
    expect(
      t
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .any((w) => (w.color?.a ?? 0) > .15),
      true,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('筛选与排序'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
