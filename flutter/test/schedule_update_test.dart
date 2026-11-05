import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/core/sync.dart';
import 'package:space_flutter/main.dart';
import 'package:space_flutter/store.dart';
import 'package:space_flutter/ui/controls.dart';
import 'package:space_flutter/ui/dialogs.dart';
import 'package:space_flutter/ui/schedule.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late SpaceStore s;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('space210-');
    s = SpaceStore(SpaceRepository(dir));
    await s.initialize();
    await s.commit(demoState(count: 12), 'synthetic');
    s.notice = null;
  });
  tearDown(() async {
    s.dispose();
    await dir.delete(recursive: true);
  });
  Future<void> launch(
    WidgetTester t, {
    double height = 860,
    double width = 1380,
  }) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await t.pumpWidget(SpaceApp(store: s));
    await t.pumpAndSettle();
  }

  test('同条件多选OR，不同条件AND；默认筛选含排序重启恢复并清除失效引用', () async {
    s.query.categoryIDs.addAll(['work', 'life']);
    s.query.statusIDs.addAll(['todo', 'done']);
    s.query.priorityIDs.addAll(['high', 'low']);
    s.query.dueFilters.addAll(['today', 'overdue']);
    s.query.sort = 'created';
    s.refreshQuery();
    expect(
      s.visible.every(
        (t) =>
            ['work', 'life'].contains(t.category) &&
            ['todo', 'done'].contains(t.status) &&
            ['high', 'low'].contains(t.priority) &&
            (t.due == s.today || t.overdue(s.today)),
      ),
      true,
    );
    await s.saveDefaultFilters();
    await s.reload();
    expect(s.query.categoryIDs, {'work', 'life'});
    expect(s.query.statusIDs, {'todo', 'done'});
    expect(s.query.sort, 'created');
    s.query.projectIDs.add('deleted');
    s.refreshQuery();
    expect(s.query.projectIDs, isEmpty);
    s.query.clear();
    s.refreshQuery();
    expect(s.visible.length, 12);
    final saved = jsonDecode(s.state.settings['defaultFilters.${s.view}']!);
    expect(saved['statuses'], ['todo', 'done']);
  });
  test('内置分类改名、自定义分类引用、SQLite/便携备份持久化和重复名拒绝', () async {
    await s.saveCategory('办公', id: 'work');
    expect(s.state.taskCategories['work'], '办公');
    await s.saveCategory('学习');
    final id = s.state.taskCategories.entries
        .singleWhere((e) => e.value == '学习')
        .key;
    final task = s.state.tasks.first.patch({'category': id});
    await s.saveTask(task, initial: s.state.tasks.first);
    expect(s.error, isNull);
    await s.reload();
    expect(s.state.tasks.firstWhere((t) => t.id == task.id).category, id);
    final backup = SpaceState.fromJson(s.state.toJson(portable: true));
    expect(backup.taskCategories[id], '学习');
    expect(SyncCodec.fingerprint(backup), SyncCodec.fingerprint(s.state));
    final revision = s.state.revision;
    await s.saveCategory('办公');
    expect(s.error, isNotNull);
    expect(s.state.revision, revision);
    expect(() => s.state.copy(settings: {}).validate(), throwsFormatException);
  });
  testWidgets('甘特当前整月、日周月刻度、年月选择和跨年左右切换，无最小窗口溢出', (t) async {
    await t.runAsync(
      () => s.preferences({
        'viewMode': 'gantt',
        'navCollapsed': 'false',
        'overviewCollapsed': 'true',
      }),
    );
    await launch(t, width: 1020, height: 640);
    expect(find.text('甘特图'), findsNothing);
    final picker = t.widget<MonthField>(find.byType(MonthField));
    expect(picker.value.day, 1);
    expect(picker.value.month, beijingDay().month);
    expect(t.takeException(), isNull, reason: 'initial gantt header');
    picker.onChanged(DateTime.utc(2028, 2));
    await t.pumpAndSettle();
    expect(find.text('2/29'), findsOneWidget);
    for (final mode in ['week', 'month', 'day']) {
      await t.runAsync(() => s.preference('ganttMode', mode));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }
    t
        .widget<MonthField>(find.byType(MonthField))
        .onChanged(DateTime.utc(2026, 12));
    await t.pumpAndSettle();
    await t.tap(
      find.byWidgetPredicate((w) => w is IconButtonS && w.label == '下个月'),
    );
    await t.pumpAndSettle();
    expect(
      t.widget<MonthField>(find.byType(MonthField)).value,
      DateTime.utc(2027, 1),
    );
    await t.tap(find.byType(MonthField));
    await t.pumpAndSettle();
    expect(find.text('12月'), findsOneWidget);
    await t.tap(find.text('12月'));
    await t.pumpAndSettle();
    expect(
      t.widget<MonthField>(find.byType(MonthField)).value,
      DateTime.utc(2027, 12),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('甘特边缘横向滚动切换月份，普通纵向滚动不切换', (t) async {
    await t.runAsync(
      () => s.preferences({
        'viewMode': 'gantt',
        'ganttMode': 'month',
        'overviewCollapsed': 'true',
      }),
    );
    await launch(t);
    final before = t.widget<MonthField>(find.byType(MonthField)).value;
    final pos = t.getCenter(find.byKey(const ValueKey('gantt-timeline')));
    t.binding.handlePointerEvent(
      PointerScrollEvent(position: pos, scrollDelta: const Offset(100, 0)),
    );
    await t.pumpAndSettle();
    expect(
      t.widget<MonthField>(find.byType(MonthField)).value,
      DateTime.utc(before.year, before.month + 1),
    );
    t.binding.handlePointerEvent(
      PointerScrollEvent(position: pos, scrollDelta: const Offset(0, 120)),
    );
    await t.pumpAndSettle();
    expect(
      t.widget<MonthField>(find.byType(MonthField)).value,
      DateTime.utc(before.year, before.month + 1),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('月格高度自适应，无溢出才显示剩余数…，增高可超过3项', (t) async {
    final day = dayString(beijingDay());
    final tasks = [
      for (var i = 0; i < 10; i++)
        SpaceTask.create(due: day).patch({'title': '月格任务$i', 'startDate': day}),
    ];
    await t.runAsync(
      () => s.commit(
        s.state.copy(
          tasks: tasks,
          settings: {
            'viewMode': 'calendar',
            'overviewCollapsed': 'true',
            'calendarMode': 'month',
          },
        ),
        'synthetic',
      ),
    );
    await launch(t, height: 640);
    final compact = find.textContaining(RegExp(r'^\d+…$'));
    expect(compact, findsOneWidget);
    final hidden = int.parse(t.widget<Text>(compact).data!.replaceAll('…', ''));
    t.view.physicalSize = const Size(1380, 1600);
    await t.pumpAndSettle();
    final tall = int.parse(
      t
          .widget<Text>(find.textContaining(RegExp(r'^\d+…$')))
          .data!
          .replaceAll('…', ''),
    );
    expect(tall, lessThan(hidden));
    expect(10 - tall, greaterThan(3));
    expect(t.takeException(), isNull);
  });
  testWidgets('分类长名称在任务各视图中不会撑破布局', (t) async {
    await t.runAsync(() => s.saveCategory('二十字以内的自定义工作分类名称', id: 'work'));
    await t.runAsync(
      () =>
          s.preferences({'overviewCollapsed': 'true', 'navCollapsed': 'true'}),
    );
    await launch(t, width: 1020, height: 640);
    for (final view in ['board', 'list', 'gantt', 'calendar']) {
      await t.runAsync(() => s.preference('viewMode', view));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: view);
    }
  });
  testWidgets('筛选面板支持多选、默认保存，状态和分类同一设置界面', (t) async {
    await launch(t);
    final context = t.element(find.byType(Navigator).first);
    showFilters(context, s);
    await t.pumpAndSettle();
    final multi = find.byWidgetPredicate(
      (w) => w is SpaceMultiSelect && w.label == '任务状态',
    );
    await t.tap(multi);
    await t.pumpAndSettle();
    await t.tap(find.text('待办').last);
    await t.pumpAndSettle();
    await t.tap(find.text('已完成').last);
    await t.pumpAndSettle();
    expect(s.query.statusIDs, {'todo', 'done'});
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    showStatuses(context, s);
    await t.pumpAndSettle();
    await t.tap(find.text('任务分类'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, '学习');
    await t.runAsync(() async {
      await t.tap(find.text('新增分类'));
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (s.busy && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(s.busy, false);
    });
    await t.pumpAndSettle();
    expect(s.state.taskCategories.values, contains('学习'));
    expect(t.takeException(), isNull);
  });
}
