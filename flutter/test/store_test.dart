import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late SpaceStore s;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('space-store-');
    s = SpaceStore(SpaceRepository(dir));
    await s.initialize();
  });
  tearDown(() async {
    s.dispose();
    await dir.delete(recursive: true);
  });
  SpaceTask draft([String title = '测试任务']) =>
      SpaceTask.create().patch({'title': title});
  test('001/003 首次空库及默认偏好；重新载入无内存撤销', () async {
    expect(s.state.tasks, isEmpty);
    expect(s.state.statuses, builtins);
    expect(s.dark, isFalse);
    expect(s.navCollapsed, isTrue);
    expect(s.overviewCollapsed, isFalse);
    expect(s.view, 'board');
    expect(s.calendarMode, 'month');
    await s.saveTask(draft());
    expect(s.canUndo, isTrue);
    await s.reload();
    expect(s.canUndo, isFalse);
    expect(s.state.tasks.length, 1);
  });
  test('005/007 偏好独立持久化，偏好写入不替换业务恢复快照', () async {
    await s.saveTask(draft());
    await s.preference('navCollapsed', 'false');
    await s.preference('overviewCollapsed', 'true');
    await s.preference('viewMode', 'calendar');
    await s.preference('calendarMode', 'week');
    await s.reload();
    expect(s.navCollapsed, isFalse);
    expect(s.overviewCollapsed, isTrue);
    expect(s.view, 'calendar');
    expect(s.calendarMode, 'week');
    expect(s.repository.readFile(s.repository.previous).tasks, isEmpty);
  });
  test('030/031/032 UTF16标题边界、trim与原子拒绝', () async {
    expect(await s.saveTask(draft('  ')), isFalse);
    expect(await s.saveTask(draft('😀' * 50)), isTrue);
    expect(await s.saveTask(draft('😀' * 50 + '字')), isFalse);
    expect(s.state.tasks.length, 1);
    expect(await s.saveTask(draft('  保留标题  ')), isTrue);
    expect(s.state.tasks.last.title, '保留标题');
  });
  test('033/039 说明长度与日期矛盾不覆盖原任务', () async {
    await s.saveTask(draft().patch({'description': '字' * 5000}));
    final original = s.state.tasks.single;
    expect(
      await s.saveTask(
        original.patch({'description': '字' * 5001}),
        initial: original,
      ),
      isFalse,
    );
    expect(
      await s.saveTask(
        original.patch({'startDate': '2026-11-03', 'due': '2026-11-02'}),
        initial: original,
      ),
      isFalse,
    );
    expect(s.state.tasks.single.toJson(), original.toJson());
  });
  test('041/042 旧草稿与已删除任务不能覆盖或复活', () async {
    await s.saveTask(draft());
    final original = s.state.tasks.single;
    await s.commit(
      s.state.copy(
        tasks: [
          original.patch({
            'updatedAt': '2030-01-01T00:00:00Z',
            'title': '后台更新',
          }),
        ],
      ),
      '并发合成更新',
    );
    expect(
      await s.saveTask(original.patch({'title': '过时草稿'}), initial: original),
      isFalse,
    );
    expect(s.state.tasks.single.title, '后台更新');
    final latest = s.state.tasks.single;
    await s.deleteTask(latest.id);
    expect(await s.saveTask(latest, initial: latest), isFalse);
    expect(s.state.tasks, isEmpty);
  });
  test('047/048/050 完成、重开与同状态无重复修订', () async {
    await s.saveTask(draft());
    final id = s.state.tasks.single.id;
    await s.moveTask(id, 'doing');
    final revision = s.state.revision;
    await s.moveTask(id, 'doing');
    expect(s.state.revision, revision);
    await s.moveTask(id, 'done');
    expect(s.state.tasks.single.completedAt, isNotNull);
    await s.moveTask(id, 'todo');
    expect(s.state.tasks.single.completedAt, isNull);
    await s.undo();
    expect(s.state.tasks.single.status, 'done');
    expect(s.canUndo, isFalse);
  });
  test('055/057/060/063/064 停用保留历史与原状态编辑，禁新移入', () async {
    await s.addStatus('等待反馈');
    await s.addStatus(' 等待反馈 ');
    expect(s.state.statuses.where((x) => x.startsWith('custom:')).length, 1);
    await s.saveTask(draft().patch({'status': 'custom:等待反馈'}));
    final old = s.state.tasks.single;
    await s.toggleStatus(old.status);
    expect(s.state.displayStatuses, contains(old.status));
    expect(
      await s.saveTask(old.patch({'description': '保留停用状态编辑'}), initial: old),
      isTrue,
    );
    expect(await s.saveTask(draft().patch({'status': old.status})), isFalse);
    await s.moveTask(old.id, 'todo');
    await s.moveTask(old.id, old.status);
    expect(s.state.tasks.single.status, 'todo');
    expect(s.state.displayStatuses, isNot(contains(old.status)));
    await s.toggleStatus(old.status);
    await s.moveTask(old.id, old.status);
    expect(s.state.tasks.single.status, old.status);
  });
  test('059/066/068 内置保护；迁移到完成；列序重开', () async {
    await s.toggleStatus('todo');
    await s.deleteStatus('todo', 'done');
    expect(s.state.disabledStatuses, isEmpty);
    expect(s.state.statuses, builtins);
    await s.addStatus('审核');
    await s.saveTask(draft().patch({'status': 'custom:审核'}));
    await s.deleteStatus('custom:审核', 'done');
    expect(s.state.tasks.single.completedAt, isNotNull);
    expect(s.state.statuses, builtins);
    await s.reorderStatus('done', 'todo');
    await s.reload();
    expect(s.state.statuses.first, 'done');
    expect(s.state.tasks.single.status, 'done');
  });
  test('069/070/071/072 项目同事务创建、等价复用和失败无孤立项目', () async {
    expect(await s.saveTask(draft(' '), projectName: '孤立项目'), isFalse);
    expect(s.state.projects, isEmpty);
    await s.saveTask(draft('一'), projectName: ' Alpha ');
    await s.saveTask(draft('二'), projectName: 'alpha');
    expect(s.state.projects.length, 1);
    expect(s.state.tasks.map((x) => x.projectID).toSet().length, 1);
    expect(await s.saveTask(draft('三'), projectName: '字' * 61), isFalse);
    expect(s.state.tasks.length, 2);
    expect(s.state.projects.length, 1);
  });
  test('项目改名、停用持久化与导出，禁止新加入；删除保留任务可撤销', () async {
    await s.saveTask(draft(), projectName: '项目甲');
    final id = s.state.projects.single.id;
    final original = s.state.tasks.single;
    expect(await s.saveProject('项目乙', id: id), isTrue);
    await s.toggleProject(id);
    await s.reload();
    expect(s.state.projects.single.disabled, isTrue);
    expect(s.state.projects.single.name, '项目乙');
    expect(
      SpaceState.fromJson(
        s.state.toJson(portable: true),
      ).projects.single.disabled,
      isTrue,
    );
    expect(await s.saveTask(draft('禁止').patch({'projectID': id})), isFalse);
    expect(
      await s.saveTask(
        draft('禁止同名').patch({'projectID': id}),
        projectName: '项目乙',
      ),
      isFalse,
    );
    expect(
      await s.saveTask(original.patch({'title': '历史编辑'}), initial: original),
      isTrue,
    );
    s.query.projectID = id;
    await s.deleteProject(id);
    expect(s.state.tasks.single.title, '历史编辑');
    expect(s.state.tasks.single.projectID, isNull);
    expect(s.query.projectID, isNull);
    await s.undo();
    expect(s.state.tasks.single.projectID, id);
    expect(s.state.projects.single.disabled, isTrue);
    await s.toggleProject(id);
    expect(await s.saveTask(draft('允许').patch({'projectID': id})), isTrue);
  });
  test('011–027 查询AND、项目搜索、真实逾期和默认日期独立', () async {
    final tasks = [
      draft('Alpha').patch({
        'description': 'only-description',
        'due': '2026-11-01',
        'projectID': 'p',
      }),
      draft('已完成').moving('done').patch({'due': '2026-11-02'}),
      draft('无截止'),
    ];
    final state = SpaceState(tasks: tasks, projects: [Project('p', 'Project')]);
    final q = TaskQuery()
      ..text = '  PROJECT  '
      ..category = 'work'
      ..priority = 'medium'
      ..status = 'todo'
      ..projectID = 'p';
    expect(q.apply(state, '2026-11-02').single.title, 'Alpha');
    q.clear();
    q.dueFilter = 'overdue';
    expect(q.apply(state, '2026-11-02').single.title, 'Alpha');
    q.dueFilter = 'today';
    expect(q.apply(state, '2026-11-02').single.status, 'done');
    q.dueFilter = 'none';
    expect(q.apply(state, '2026-11-02').single.title, '无截止');
    q.clear();
    q.text = 'only-description';
    expect(q.apply(state, '2026-11-02').single.title, 'Alpha');
  });
  test('082/083/088 附件路径与10MiB/20个/20MiB边界', () {
    Attachment attachment(String name, int bytes) => Attachment(
      id: uid(),
      name: name,
      typeIdentifier: 'public.data',
      data: Uint8List(bytes),
    );
    attachment('合法.bin', 10 * 1024 * 1024).validate();
    expect(() => attachment('../bad', 1).validate(), throwsFormatException);
    expect(() => attachment(r'a\b', 1).validate(), throwsFormatException);
    expect(
      () => attachment('x', 10 * 1024 * 1024 + 1).validate(),
      throwsFormatException,
    );
    draft().patch({
      'attachments': List.generate(20, (_) => attachment('a', 1).toJson()),
    }).validate();
    expect(
      () => draft().patch({
        'attachments': List.generate(21, (_) => attachment('a', 1).toJson()),
      }).validate(),
      throwsFormatException,
    );
    expect(
      () => draft().patch({
        'attachments': [
          attachment('a', 10 * 1024 * 1024).toJson(),
          attachment('b', 10 * 1024 * 1024).toJson(),
          attachment('c', 1).toJson(),
        ],
      }).validate(),
      throwsFormatException,
    );
  });
  test('快照导出拒绝活动库与别名，恢复保持业务且可撤销', () async {
    await s.saveTask(draft('原记录'));
    final original = s.state;
    await s.saveTask(draft('新记录'));
    await s.applyBackup(original);
    expect(s.state.tasks.length, 1);
    await s.undo();
    expect(s.state.tasks.length, 2);
    await expectLater(
      s.repository.exportSQLite(s.repository.path),
      throwsFormatException,
    );
    await expectLater(
      s.repository.exportSQLite(s.repository.previous),
      throwsFormatException,
    );
    if (!Platform.isWindows) {
      final alias = Link('${dir.path}/alias.sqlite')
        ..createSync(s.repository.path);
      await expectLater(
        s.repository.exportSQLite(alias.path),
        throwsFormatException,
      );
    }
    final file = '${dir.path}/export.sqlite';
    await s.repository.exportSQLite(file);
    expect((await s.readBackup(file)).tasks.length, 2);
  });
  test('甘特左右端不能倒置；移动按完整原始区间计算；完成无due按完成日', () {
    final range = TaskSchedule(
      DateTime.utc(2026, 10, 1),
      DateTime.utc(2026, 11, 4),
    );
    expect(dayString(range.adjusting('start', 100).start), '2026-11-04');
    expect(dayString(range.adjusting('end', -100).end), '2026-10-01');
    expect(dayString(range.adjusting('move', 1).start), '2026-10-02');
    final done = draft().moving('done', DateTime.parse('2026-11-01T18:00:00Z'));
    expect(
      dayString(TaskSchedule.forTask(done, DateTime.utc(2026, 11, 8)).end),
      '2026-11-02',
    );
  });
}
