import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'core/models.dart';
import 'core/repository.dart';
import 'host.dart';

enum SpaceArea { tasks, tools, invoices }

class SpaceStore extends ChangeNotifier {
  final SpaceRepository repository;
  SpaceState state = SpaceState();
  final _viewQueries = <String, TaskQuery>{};
  TaskQuery get query => _viewQueries.putIfAbsent(view, () {
    try {
      return TaskQuery.fromJson(
        jsonDecode(state.settings['defaultFilters.$view'] ?? '{}'),
      )..prune(state);
    } catch (_) {
      return TaskQuery();
    }
  });
  set query(TaskQuery value) => _viewQueries[view] = value;
  SpaceState? _undo;
  List<SpaceTask> visible = const [];
  Map<String, List<SpaceTask>> grouped = {};
  bool busy = false, loaded = false, modal = false;
  String? error, notice;
  String today = dayString(beijingDay());
  Timer? _noticeTimer, _dayTimer;
  final searchRequested = ValueNotifier<int>(0);
  SpaceArea area = SpaceArea.tasks;
  SpaceStore(this.repository);

  void openArea(SpaceArea value) {
    if (area == value) return;
    area = value;
    notifyListeners();
  }

  bool? _systemDark, _temporaryDark;
  bool get systemDark =>
      _systemDark ??
      (WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark);
  bool? get temporaryDark => _temporaryDark;
  String get appearance =>
      ['system', 'light', 'dark'].contains(state.settings['appearance'])
      ? state.settings['appearance']!
      : state.settings.containsKey('dark')
      ? (state.settings['dark'] == 'true' ? 'dark' : 'light')
      : 'system';
  bool get dark => appearance == 'system'
      ? _temporaryDark ?? systemDark
      : appearance == 'dark';
  Future<void> updateSystemAppearance() async {
    final current = await DesktopHost.systemDark();
    if (_systemDark == current) return;
    _systemDark = current;
    if (appearance == 'system') _temporaryDark = null;
    notifyListeners();
    await updateNativeAppearance();
  }

  Future<void> toggleTheme() async {
    if (appearance != 'system') {
      await preference('appearance', dark ? 'light' : 'dark');
      return;
    }
    _temporaryDark = !dark;
    notifyListeners();
    await updateNativeAppearance();
  }

  Future<void> resumeSystemAppearance() async {
    _temporaryDark = null;
    notifyListeners();
    await updateNativeAppearance();
  }

  Future<void> updateNativeAppearance() => DesktopHost.appearance(
    dark,
    system: appearance == 'system' && _temporaryDark == null,
  );
  bool get navCollapsed => state.settings.containsKey('navCollapsed')
      ? state.settings['navCollapsed'] == 'true'
      : true;
  bool get hideScrollbars => state.settings['hideScrollbars'] == 'true';
  double boardWidthRatio(String status) {
    final value = double.tryParse(state.settings['boardWidth.$status'] ?? '');
    return value != null && value.isFinite ? snapBoardRatio(value) : 1.0;
  }

  bool get overviewCollapsed => state.settings['overviewCollapsed'] == 'true';
  String get view =>
      [
        'board',
        'list',
        'gantt',
        'calendar',
      ].contains(state.settings['viewMode'])
      ? state.settings['viewMode']!
      : 'board';
  String get calendarMode =>
      ['day', 'week', 'month'].contains(state.settings['calendarMode'])
      ? state.settings['calendarMode']!
      : 'month';
  bool get canUndo => _undo != null && !busy && loaded && !modal;
  Future<void> initialize() async {
    _systemDark = await DesktopHost.systemDark();
    await reload();
    _dayTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refreshDay(),
    );
  }

  Future<void> reload() async {
    if (busy) return;
    busy = true;
    try {
      state = await repository.load();
      loaded = true;
      // Migrate the former shared default only to the view active at upgrade.
      if (state.settings.containsKey('defaultFilters') &&
          state.settings['defaultFilters.migrated'] != 'true') {
        state = await repository.save(
          state.copy(
            settings: {
              ...state.settings,
              'defaultFilters.$view':
                  state.settings['defaultFilters.$view'] ??
                  state.settings['defaultFilters']!,
              'defaultFilters.migrated': 'true',
            },
          ),
          preferencesOnly: true,
        );
      }
      _viewQueries.clear();
      error = null;
      _undo = null;
    } catch (e) {
      error = '无法读取本地任务：${readable(e)}';
      loaded = false;
    }
    busy = false;
    refreshQuery();
    await updateNativeAppearance();
  }

  void refreshDay() {
    final current = dayString(beijingDay());
    if (current != today) {
      today = current;
      refreshQuery();
    }
  }

  void refreshQuery() {
    query.prune(state);
    visible = query.apply(state, today);
    grouped = {for (final s in state.displayStatuses) s: <SpaceTask>[]};
    for (final t in visible) {
      grouped[t.status]?.add(t);
    }
    notifyListeners();
  }

  void resetQuery() {
    query = TaskQuery();
    refreshQuery();
  }

  void message(String text) {
    notice = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 6), () {
      notice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  static String readable(Object e) => e is FormatException
      ? e.message
      : e is StateError
      ? e.message
      : '操作失败，请检查文件权限或连接后重试';
  Future<bool> commit(
    SpaceState candidate,
    String message, {
    bool undo = true,
  }) async {
    if (busy || !loaded) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final old = state;
      state = await repository.save(candidate);
      if (undo) _undo = old;
      busy = false;
      refreshQuery();
      this.message(message);
      return true;
    } catch (e) {
      error = readable(e);
      busy = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> preference(String key, String value) async {
    await preferences({
      key: value,
      if (key == 'dark') 'appearance': value == 'true' ? 'dark' : 'light',
    });
  }

  Future<bool> preferences(Map<String, String> values) async {
    if (busy || !loaded) return false;
    busy = true;
    var saved = false;
    try {
      state = await repository.save(
        state.copy(settings: {...state.settings, ...values}),
        preferencesOnly: true,
      );
      error = null;
      saved = true;
      if (values.containsKey('appearance') || values.containsKey('dark')) {
        _temporaryDark = null;
      }
    } catch (e) {
      error = '设置保存失败：${readable(e)}';
    }
    busy = false;
    if (values.containsKey('viewMode')) {
      refreshQuery();
    } else {
      notifyListeners();
    }
    if (values.containsKey('appearance') || values.containsKey('dark')) {
      await updateNativeAppearance();
    }
    return saved;
  }

  Future<void> undo() async {
    if (!canUndo) return;
    final previous = _undo!;
    if (await commit(
      previous.copy(settings: state.settings),
      '已撤销最近一次更改',
      undo: false,
    )) {
      _undo = null;
    }
    notifyListeners();
  }

  Future<bool> saveTask(
    SpaceTask draft, {
    SpaceTask? initial,
    String? projectName,
  }) async {
    if (busy || !loaded) return false;
    try {
      final now = timestamp();
      final projects = [...state.projects];
      var task = draft.patch({'title': draft.title.trim(), 'updatedAt': now});
      if (initial != null) {
        final current = state.tasks
            .where((x) => x.id == initial.id)
            .firstOrNull;
        if (current == null) invalid('任务已被删除，输入内容已保留');
        if (current.updatedAt != initial.updatedAt) invalid('任务已被修改，请重新打开后再保存');
        task = task.patch({
          'createdAt': current.createdAt,
          'completedAt': task.status == 'done'
              ? (current.status == 'done' ? current.completedAt : now)
              : null,
        });
      } else {
        if (state.disabledStatuses.contains(task.status)) {
          invalid('不能在停用状态中新建任务');
        }
        task = task.patch({
          'createdAt': now,
          'completedAt': task.status == 'done' ? now : null,
        });
      }
      if (state.disabledStatuses.contains(task.status) &&
          task.status != initial?.status) {
        invalid('不能移入停用状态');
      }
      if (projectName != null) {
        final name = normalizedName(projectName);
        if (name.isEmpty || name.length > 60 || controls(name)) {
          invalid('项目名称须为1至60字且无控制字符');
        }
        var project = projects
            .where((p) => p.name.toLowerCase() == name.toLowerCase())
            .firstOrNull;
        project ??= Project(uid(), name);
        if (!projects.any((p) => p.id == project!.id)) projects.add(project);
        if (project.disabled) invalid('同名项目已停用，请先在项目管理中启用');
        task = task.patch({'projectID': project.id});
      }
      final selectedProject = projects
          .where((p) => p.id == task.projectID)
          .firstOrNull;
      if (selectedProject?.disabled == true &&
          task.projectID != initial?.projectID) {
        invalid('不能将任务加入停用项目');
      }
      task.validate();
      final tasks = [...state.tasks];
      final index = tasks.indexWhere((x) => x.id == task.id);
      if (index < 0) {
        tasks.add(task);
      } else {
        tasks[index] = task;
      }
      return await commit(
        state.copy(tasks: tasks, projects: projects),
        initial == null ? '任务已创建' : '任务已保存',
      );
    } catch (e) {
      error = readable(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> moveTask(String id, String status) async {
    final task = state.tasks.where((t) => t.id == id).firstOrNull;
    if (task == null ||
        task.status == status ||
        state.disabledStatuses.contains(status)) {
      return;
    }
    await commit(
      state.copy(
        tasks: state.tasks
            .map((t) => t.id == id ? t.moving(status) : t)
            .toList(),
      ),
      '已移至${statusName(status)}',
    );
  }

  Future<bool> deleteTask(String id) => commit(
    state.copy(tasks: state.tasks.where((t) => t.id != id).toList()),
    '任务已删除，可撤销',
  );
  Future<bool> saveProject(String name, {String? id}) async {
    try {
      final n = normalizedName(name);
      if (n.isEmpty || n.length > 60 || controls(n)) {
        invalid('项目名称须为1至60字且无控制字符');
      }
      if (state.projects.any(
        (p) => p.id != id && p.name.toLowerCase() == n.toLowerCase(),
      )) {
        invalid('项目名称不能重复');
      }
      if (id != null && !state.projects.any((p) => p.id == id)) {
        invalid('项目已被删除');
      }
      final projects = id == null
          ? [...state.projects, Project(uid(), n)]
          : state.projects
                .map(
                  (p) => p.id == id ? Project(id, n, disabled: p.disabled) : p,
                )
                .toList();
      return await commit(
        state.copy(projects: projects),
        id == null ? '项目已新建' : '项目名称已更新',
      );
    } catch (e) {
      error = readable(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> toggleProject(String id) async {
    await commit(
      state.copy(
        projects: state.projects
            .map(
              (p) =>
                  p.id == id ? Project(p.id, p.name, disabled: !p.disabled) : p,
            )
            .toList(),
      ),
      '项目状态已更新',
    );
  }

  Future<void> deleteProject(String id) async {
    final ok = await commit(
      state.copy(
        projects: state.projects.where((p) => p.id != id).toList(),
        tasks: state.tasks
            .map(
              (t) => t.projectID == id
                  ? t.patch({'projectID': null, 'updatedAt': timestamp()})
                  : t,
            )
            .toList(),
      ),
      '项目已删除，任务已保留，可撤销',
    );
    if (ok && query.projectID == id) {
      query.projectID = null;
      refreshQuery();
    }
  }

  Future<void> saveDefaultFilters() async {
    if (await preferences({
      'defaultFilters.$view': jsonEncode(query.toJson()),
    })) {
      message('当前筛选已设为默认配置');
    }
  }

  Future<void> resetDefaultFilters() async {
    if (await preferences({'defaultFilters.$view': '{}'})) {
      message('当前视图默认筛选已重置');
    }
  }

  Future<void> saveCategory(String name, {String? id}) async {
    final definitions = state.taskCategories;
    definitions[id ?? 'category:${uid()}'] = normalizedName(name);
    await commit(
      state.copy(
        settings: {
          ...state.settings,
          'taskCategories': jsonEncode(definitions),
        },
      ),
      id == null ? '分类已添加' : '分类已更新',
    );
  }

  Future<void> addStatus(String name) async {
    final n = normalizedName(name);
    try {
      if (n.isEmpty ||
          n.length > 20 ||
          controls(n) ||
          state.statuses.any(
            (s) => statusName(s).toLowerCase() == n.toLowerCase(),
          )) {
        invalid('状态名称须为1至20字且不能重复');
      }
      final statuses = [...state.statuses]
        ..insert(state.statuses.indexOf('done'), 'custom:$n');
      await commit(state.copy(statuses: statuses), '状态已添加');
    } catch (e) {
      error = readable(e);
      notifyListeners();
    }
  }

  Future<void> toggleStatus(String status) async {
    if (builtins.contains(status)) return;
    final disabled = [...state.disabledStatuses];
    if (!disabled.remove(status)) disabled.add(status);
    await commit(
      state.copy(disabledStatuses: disabled),
      '状态已${disabled.contains(status) ? '停用' : '启用'}',
    );
  }

  Future<void> deleteStatus(String status, String target) async {
    if (builtins.contains(status) ||
        status == target ||
        state.disabledStatuses.contains(target)) {
      return;
    }
    final success = await commit(
      state.copy(
        tasks: state.tasks
            .map((t) => t.status == status ? t.moving(target) : t)
            .toList(),
        statuses: state.statuses.where((s) => s != status).toList(),
        disabledStatuses: state.disabledStatuses
            .where((s) => s != status)
            .toList(),
      ),
      '状态已删除，任务已迁移',
    );
    if (success && query.status == status) {
      query.status = null;
      refreshQuery();
    }
  }

  Future<void> reorderStatus(String source, String target) async {
    if (source == target) return;
    final order = [...state.statuses];
    final i = order.indexOf(target);
    if (i < 0 || !order.remove(source)) return;
    order.insert(i, source);
    await commit(state.copy(statuses: order), '状态顺序已保存');
  }

  Future<bool> applyBackup(SpaceState incoming) async {
    final settings = {
      ...incoming.settings,
      for (final e in state.settings.entries)
        if (e.key.startsWith('sync.') || e.key.startsWith('github.'))
          e.key: e.value,
    };
    final candidate = incoming.copy(
      settings: settings,
      workspaceID: state.workspaceID ?? uid(),
    );
    if (loaded) return commit(candidate, '备份已恢复');
    try {
      state = await repository.recover(candidate);
      loaded = true;
      error = null;
      refreshQuery();
      return true;
    } catch (e) {
      error = readable(e);
      notifyListeners();
      return false;
    }
  }

  Future<SpaceState> readBackup(String path) => repository.readExternal(path);
  @override
  void dispose() {
    _noticeTimer?.cancel();
    _dayTimer?.cancel();
    searchRequested.dispose();
    super.dispose();
  }
}

SpaceState demoState({int count = 9}) {
  final today = beijingDay();
  final now = timestamp();
  final titles = [
    '梳理本周工作安排',
    '完善项目需求说明',
    '整理接口与数据口径',
    '校对页面与交互细节',
    '提交本周工作总结',
    '预约年度健康检查',
    '整理书桌与阅读清单',
    '准备周末出行计划',
    '完成资料归档',
  ];
  final tasks = List.generate(count, (i) {
    final status = builtins[i % 3];
    return SpaceTask(
      id: 'demo-${i.toString().padLeft(6, '0')}',
      title:
          titles[i % titles.length] + (i >= titles.length ? ' ${i + 1}' : ''),
      description: '用于独立复刻验收的合成任务，不包含正式工作数据。',
      category: categories.keys.elementAt(i % 3),
      status: status,
      priority: priorities.keys.elementAt(i % 3),
      due: i % 4 == 0 ? '' : dayString(today.add(Duration(days: i % 7 - 2))),
      createdAt: now,
      updatedAt: now,
      completedAt: status == 'done' ? now : null,
      projectID: i % 2 == 0 ? 'demo-project' : null,
    );
  });
  return SpaceState(
    tasks: tasks,
    projects: [Project('demo-project', 'Space复刻验收')],
    workspaceID: uid(),
  );
}

const boardWidthRatios = [0.5, 2 / 3, 0.75, 1.0];
double snapBoardRatio(double value) => boardWidthRatios.reduce(
  (a, b) => (value - a).abs() <= (value - b).abs() ? a : b,
);
