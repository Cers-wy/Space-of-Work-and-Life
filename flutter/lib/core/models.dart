import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

String normalizedName(String name) => unorm.nfc(name.trim());

const builtins = ['todo', 'doing', 'done'];
const categories = {'work': '工作', 'personal': '个人', 'life': '生活'};
const priorities = {'high': '高', 'medium': '中', 'low': '低'};
String uid() => const Uuid().v4().toUpperCase();
String statusName(String v) =>
    const {'todo': '待办', 'doing': '进行中', 'done': '已完成'}[v] ??
    v.replaceFirst('custom:', '');
Never invalid(String message) => throw FormatException(message);
String timestamp([DateTime? now]) =>
    (now ?? DateTime.now()).toUtc().toIso8601String();
DateTime beijingDay([DateTime? now]) {
  final d = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
  return DateTime.utc(d.year, d.month, d.day);
}

String dayString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime? parseDay(String? s) {
  if (s == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;
  final d = DateTime.tryParse('${s}T00:00:00Z');
  return d != null && d.year >= 1 && dayString(d) == s ? d : null;
}

DateTime validTime(String s) {
  final pattern = RegExp(
    r'^\d{4}-\d{2}-\d{2}T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
  );
  final m = pattern.firstMatch(s);
  if (m == null ||
      parseDay(s.substring(0, 10)) == null ||
      int.parse(m[1]!) > 23 ||
      int.parse(m[2]!) > 59 ||
      int.parse(m[3]!) > 59) {
    invalid('时间戳无效');
  }
  if (!s.endsWith('Z')) {
    final offset = s.substring(s.length - 5);
    if (int.parse(offset.substring(0, 2)) > 23 ||
        int.parse(offset.substring(3)) > 59) {
      invalid('时间戳偏移无效');
    }
  }
  return DateTime.tryParse(s) ?? invalid('时间戳无效');
}

bool controls(String s) => RegExp(r'[\x00-\x1f\x7f]').hasMatch(s);

class Attachment {
  final String id, name, typeIdentifier;
  final Uint8List data;
  Attachment({
    required this.id,
    required this.name,
    required this.typeIdentifier,
    required this.data,
  });
  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
    id: j['id'] as String,
    name: j['name'] as String,
    typeIdentifier: j['typeIdentifier'] as String,
    data: base64Decode(j['data'] as String),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'typeIdentifier': typeIdentifier,
    'data': base64Encode(data),
  };
  void validate() {
    if (id.isEmpty ||
        utf8.encode(id).length > 200 ||
        name.trim().isEmpty ||
        name.length > 255 ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\') ||
        controls(name)) {
      invalid('附件名称或标识无效');
    }
    if (typeIdentifier.isEmpty ||
        utf8.encode(typeIdentifier).length > 200 ||
        data.length > 10 * 1024 * 1024) {
      invalid('附件超出10 MB或类型无效');
    }
  }
}

class SpaceTask {
  final String id,
      title,
      description,
      category,
      status,
      priority,
      due,
      createdAt,
      updatedAt;
  final String? completedAt, projectID, startDate, richDescription;
  final List<Attachment> attachments;
  SpaceTask({
    required this.id,
    required this.title,
    this.description = '',
    this.category = 'work',
    this.status = 'todo',
    this.priority = 'medium',
    this.due = '',
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.projectID,
    this.startDate,
    this.richDescription,
    this.attachments = const [],
  });
  factory SpaceTask.create({
    String status = 'todo',
    String due = '',
    String? projectID,
  }) {
    final now = timestamp();
    return SpaceTask(
      id: uid(),
      title: '',
      status: status,
      due: due,
      projectID: projectID,
      createdAt: now,
      updatedAt: now,
      completedAt: status == 'done' ? now : null,
    );
  }
  factory SpaceTask.fromJson(Map<String, dynamic> j) => SpaceTask(
    id: j['id'] as String,
    title: j['title'] as String,
    description: j['description'] as String,
    category: j['category'] as String,
    status: j['status'] as String,
    priority: j['priority'] as String,
    due: j['due'] as String,
    createdAt: j['createdAt'] as String,
    updatedAt: j['updatedAt'] as String,
    completedAt: j['completedAt'] as String?,
    projectID: j['projectID'] as String?,
    startDate: j['startDate'] as String?,
    richDescription: j['richDescription'] as String?,
    attachments: (j['attachments'] as List? ?? [])
        .map((x) => Attachment.fromJson(Map<String, dynamic>.from(x)))
        .toList(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'category': category,
    'status': status,
    'priority': priority,
    'due': due,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'completedAt': completedAt,
    if (projectID != null) 'projectID': projectID,
    if (startDate != null) 'startDate': startDate,
    if (richDescription != null) 'richDescription': richDescription,
    if (attachments.isNotEmpty)
      'attachments': attachments.map((x) => x.toJson()).toList(),
  };
  SpaceTask patch(Map<String, dynamic> changes) =>
      SpaceTask.fromJson({...toJson(), ...changes});
  SpaceTask moving(String target, [DateTime? now]) {
    if (target == status) return this;
    final t = timestamp(now);
    return patch({
      'status': target,
      'updatedAt': t,
      'completedAt': target == 'done' ? t : null,
    });
  }

  bool overdue(String today) =>
      status != 'done' && due.isNotEmpty && due.compareTo(today) < 0;
  void validate() {
    if (id.isEmpty ||
        id.length >= 200 ||
        title.length > 100 ||
        title.trim().isEmpty ||
        description.length > 5000) {
      invalid('任务标题或说明长度无效');
    }
    if ((!categories.containsKey(category) &&
            !RegExp(r'^category:[A-Z0-9-]{36}$').hasMatch(category)) ||
        !priorities.containsKey(priority)) {
      invalid('任务分类或优先级无效');
    }
    if (due.isNotEmpty && parseDay(due) == null ||
        startDate != null && parseDay(startDate) == null) {
      invalid('日期必须是有效的 YYYY-MM-DD');
    }
    if (startDate != null && due.isNotEmpty && startDate!.compareTo(due) > 0) {
      invalid('开始日期不能晚于截止日期');
    }
    validTime(createdAt);
    validTime(updatedAt);
    if ((status == 'done') != (completedAt != null)) invalid('完成状态与完成时间不一致');
    if (completedAt != null) validTime(completedAt!);
    if (richDescription != null &&
        base64Decode(richDescription!).length > 24 * 1024 * 1024) {
      invalid('富文本超出24 MB');
    }
    if (attachments.length > 20 ||
        attachments.fold<int>(0, (n, a) => n + a.data.length) >
            20 * 1024 * 1024) {
      invalid('每项任务最多20个附件、合计20 MB');
    }
    final ids = <String>{};
    for (final a in attachments) {
      a.validate();
      if (!ids.add(a.id)) invalid('附件ID重复');
    }
  }
}

class Project {
  final String id, name;
  final bool disabled;
  Project(this.id, this.name, {this.disabled = false});
  factory Project.fromJson(Map<String, dynamic> j) => Project(
    j['id'] as String,
    normalizedName(j['name'] as String),
    disabled: j['disabled'] as bool? ?? false,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (disabled) 'disabled': true,
  };
}

class SpaceState {
  final List<SpaceTask> tasks;
  final List<String> statuses, disabledStatuses;
  final List<Project> projects;
  final Map<String, String> settings;
  final String? workspaceID, revision;
  SpaceState({
    this.tasks = const [],
    this.statuses = const ['todo', 'doing', 'done'],
    this.disabledStatuses = const [],
    this.projects = const [],
    this.settings = const {},
    this.workspaceID,
    this.revision,
  });
  SpaceState copy({
    List<SpaceTask>? tasks,
    List<String>? statuses,
    List<String>? disabledStatuses,
    List<Project>? projects,
    Map<String, String>? settings,
    String? workspaceID,
    String? revision,
  }) => SpaceState(
    tasks: tasks ?? this.tasks,
    statuses: statuses ?? this.statuses,
    disabledStatuses: disabledStatuses ?? this.disabledStatuses,
    projects: projects ?? this.projects,
    settings: settings ?? this.settings,
    workspaceID: workspaceID ?? this.workspaceID,
    revision: revision ?? this.revision,
  );
  Map<String, String> get taskCategories =>
      settings.containsKey('taskCategories')
      ? Map<String, String>.from(jsonDecode(settings['taskCategories']!))
      : {...categories};
  List<String> get displayStatuses => statuses
      .where(
        (s) => !disabledStatuses.contains(s) || tasks.any((t) => t.status == s),
      )
      .toList();
  String? projectName(String? id) {
    for (final p in projects) {
      if (p.id == id) return p.name;
    }
    return null;
  }

  bool get hasExtras =>
      projects.isNotEmpty ||
      disabledStatuses.isNotEmpty ||
      settings.isNotEmpty ||
      workspaceID != null;
  int get version {
    if (tasks.any((t) => t.richDescription != null)) return 6;
    if (tasks.any((t) => t.startDate != null)) return 5;
    if (tasks.any((t) => t.attachments.isNotEmpty)) return 4;
    if (projects.isNotEmpty ||
        disabledStatuses.isNotEmpty ||
        settings.isNotEmpty ||
        workspaceID != null) {
      return 3;
    }
    if (jsonEncode(statuses) != jsonEncode(builtins)) return 2;
    return 1;
  }

  Map<String, dynamic> toJson({bool portable = false, DateTime? now}) {
    if (portable) {
      return SpaceState(
        tasks: [...tasks]..sort((a, b) => a.id.compareTo(b.id)),
        statuses: statuses,
        disabledStatuses: [...disabledStatuses]..sort(),
        projects: projects,
        settings: {
          if (settings.containsKey('taskCategories'))
            'taskCategories': settings['taskCategories']!,
        },
      ).toJson(now: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    }
    return {
      'app': version == 1 ? 'ORBIT' : 'Space',
      'version': version,
      'exportedAt': timestamp(now),
      'tasks': tasks.map((t) => t.toJson()).toList(),
      if (jsonEncode(statuses) != jsonEncode(builtins) || hasExtras)
        'statuses': statuses,
      if (hasExtras) 'projects': projects.map((p) => p.toJson()).toList(),
      if (hasExtras) 'disabledStatuses': disabledStatuses,
      if (hasExtras) 'settings': settings,
      if (workspaceID != null) 'workspaceID': workspaceID,
      if (revision != null) 'revision': revision,
    };
  }

  factory SpaceState.fromJson(Map<String, dynamic> j) {
    final version = j['version'];
    if (version is! int || version < 1 || version > 6) invalid('不支持此备份版本');
    final s = SpaceState(
      tasks: (j['tasks'] as List)
          .map((x) => SpaceTask.fromJson(Map<String, dynamic>.from(x)))
          .toList(),
      statuses: List<String>.from(j['statuses'] ?? builtins),
      disabledStatuses: List<String>.from(j['disabledStatuses'] ?? []),
      projects: (j['projects'] as List? ?? [])
          .map((x) => Project.fromJson(Map<String, dynamic>.from(x)))
          .toList(),
      settings: Map<String, String>.from(j['settings'] ?? {}),
      workspaceID: j['workspaceID'] as String?,
      revision: j['revision'] as String?,
    );
    s.validate();
    if (version == 1 && j['statuses'] != null) invalid('V1不能包含状态定义');
    if (s.version > version) invalid('备份版本与内容不一致');
    return s;
  }
  void validate() {
    if (tasks.length > 10000 ||
        projects.length > 10000 ||
        statuses.length > 100 ||
        statuses.length < 3 ||
        settings.length > 256) {
      invalid('数据数量超过限制');
    }
    if (statuses.toSet().length != statuses.length ||
        !builtins.every(statuses.contains)) {
      invalid('状态定义缺失或重复');
    }
    final names = <String>{};
    for (final s in statuses) {
      final n = statusName(s);
      if (!builtins.contains(s) &&
          (!s.startsWith('custom:') ||
              n.trim() != n ||
              n.isEmpty ||
              n.length > 20 ||
              controls(n))) {
        invalid('自定义状态名称无效');
      }
      if (!names.add(unorm.nfc(n).toLowerCase())) invalid('状态名称重复');
    }
    if (disabledStatuses.toSet().length != disabledStatuses.length ||
        disabledStatuses.any(
          (s) => !statuses.contains(s) || builtins.contains(s),
        )) {
      invalid('停用状态无效');
    }
    final pids = <String>{}, pnames = <String>{};
    for (final p in projects) {
      if (p.id.isEmpty ||
          p.id.length >= 200 ||
          p.name.trim() != p.name ||
          p.name.isEmpty ||
          p.name.length > 60 ||
          controls(p.name) ||
          !pids.add(p.id) ||
          !pnames.add(unorm.nfc(p.name).toLowerCase())) {
        invalid('项目定义无效或重复');
      }
    }
    final definitions = taskCategories;
    final categoryNames = <String>{};
    if (definitions.isEmpty ||
        definitions.length > 100 ||
        !categories.keys.every(definitions.containsKey)) {
      invalid('分类定义无效');
    }
    for (final e in definitions.entries) {
      if ((!categories.containsKey(e.key) &&
              !RegExp(r'^category:[A-Z0-9-]{36}$').hasMatch(e.key)) ||
          e.value != normalizedName(e.value) ||
          e.value.isEmpty ||
          e.value.length > 20 ||
          controls(e.value) ||
          !categoryNames.add(unorm.nfc(e.value).toLowerCase())) {
        invalid('分类名称须为1至20字且不能重复');
      }
    }
    final tids = <String>{};
    for (final t in tasks) {
      t.validate();
      if (!tids.add(t.id) ||
          !statuses.contains(t.status) ||
          !definitions.containsKey(t.category) ||
          t.projectID != null && !pids.contains(t.projectID)) {
        invalid('任务ID重复或引用缺失');
      }
    }
    for (final e in settings.entries) {
      if (utf8.encode(e.key).length > 100 ||
          utf8.encode(e.value).length > 8192) {
        invalid('设置长度无效');
      }
    }
  }
}

class TaskQuery {
  String text = '', dueFilter = 'all', sort = 'due';
  final categoryIDs = <String>{},
      statusIDs = <String>{},
      priorityIDs = <String>{},
      projectIDs = <String>{},
      dueFilters = <String>{};
  String? get category => categoryIDs.length == 1 ? categoryIDs.first : null;
  set category(String? v) {
    categoryIDs.clear();
    if (v != null) categoryIDs.add(v);
  }

  String? get status => statusIDs.length == 1 ? statusIDs.first : null;
  set status(String? v) {
    statusIDs.clear();
    if (v != null) statusIDs.add(v);
  }

  String? get priority => priorityIDs.length == 1 ? priorityIDs.first : null;
  set priority(String? v) {
    priorityIDs.clear();
    if (v != null) priorityIDs.add(v);
  }

  String? get projectID => projectIDs.length == 1 ? projectIDs.first : null;
  set projectID(String? v) {
    projectIDs.clear();
    if (v != null) projectIDs.add(v);
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'sort': sort,
    'categories': categoryIDs.toList(),
    'statuses': statusIDs.toList(),
    'priorities': priorityIDs.toList(),
    'projects': projectIDs.toList(),
    'dates': dueFilters.toList(),
    'dueFilter': dueFilter,
  };
  TaskQuery();
  factory TaskQuery.fromJson(Map<String, dynamic> j) {
    final q = TaskQuery();
    q.text = j['text'] as String? ?? '';
    q.sort = ['due', 'priority', 'created'].contains(j['sort'])
        ? j['sort']
        : 'due';
    q.dueFilter = j['dueFilter'] as String? ?? 'all';
    for (final pair in [
      (q.categoryIDs, 'categories'),
      (q.statusIDs, 'statuses'),
      (q.priorityIDs, 'priorities'),
      (q.projectIDs, 'projects'),
      (q.dueFilters, 'dates'),
    ]) {
      pair.$1.addAll(List<String>.from(j[pair.$2] ?? []));
    }
    return q;
  }
  void prune(SpaceState s) {
    categoryIDs.removeWhere((v) => !s.taskCategories.containsKey(v));
    statusIDs.removeWhere((v) => !s.statuses.contains(v));
    priorityIDs.removeWhere((v) => !priorities.containsKey(v));
    projectIDs.removeWhere((v) => !s.projects.any((p) => p.id == v));
    dueFilters.removeWhere((v) => !['today', 'overdue', 'none'].contains(v));
  }

  bool get hasFilters =>
      text.isNotEmpty ||
      categoryIDs.isNotEmpty ||
      statusIDs.isNotEmpty ||
      priorityIDs.isNotEmpty ||
      projectIDs.isNotEmpty ||
      dueFilters.isNotEmpty ||
      dueFilter != 'all';
  void clear() {
    text = '';
    category = status = priority = projectID = null;
    dueFilter = 'all';
    dueFilters.clear();
  }

  List<SpaceTask> apply(SpaceState state, String today) {
    final term = text.trim().toLowerCase();
    final projectNames = {for (final p in state.projects) p.id: p.name};
    final result = state.tasks
        .where(
          (t) =>
              (term.isEmpty ||
                  '${t.title} ${t.description} ${projectNames[t.projectID] ?? ''}'
                      .toLowerCase()
                      .contains(term)) &&
              (categoryIDs.isEmpty || categoryIDs.contains(t.category)) &&
              (statusIDs.isEmpty || statusIDs.contains(t.status)) &&
              (priorityIDs.isEmpty || priorityIDs.contains(t.priority)) &&
              (projectIDs.isEmpty || projectIDs.contains(t.projectID)) &&
              (dueFilters.isNotEmpty
                  ? (dueFilters.contains('none') && t.due.isEmpty ||
                        dueFilters.contains('today') && t.due == today ||
                        dueFilters.contains('overdue') && t.overdue(today))
                  : (dueFilter == 'all' ||
                        dueFilter == 'none' && t.due.isEmpty ||
                        dueFilter == 'today' && t.due == today ||
                        dueFilter == 'overdue' && t.overdue(today))),
        )
        .toList();
    final createdTimes = {for (final t in result) t.id: validTime(t.createdAt)};
    const ranks = {'high': 0, 'medium': 1, 'low': 2};
    int created(SpaceTask a, SpaceTask b) =>
        createdTimes[b.id]!.compareTo(createdTimes[a.id]!);
    int due(SpaceTask a, SpaceTask b) => (a.due.isEmpty ? '9999-12-31' : a.due)
        .compareTo(b.due.isEmpty ? '9999-12-31' : b.due);
    result.sort((a, b) {
      int c = 0;
      if (sort == 'created') c = created(a, b);
      if (sort == 'priority') {
        c = ranks[a.priority]!.compareTo(ranks[b.priority]!);
      }
      if (c == 0) c = due(a, b);
      if (c == 0) c = created(a, b);
      return c == 0 ? a.id.compareTo(b.id) : c;
    });
    return result;
  }
}

class TaskSchedule {
  final DateTime start, end;
  final bool defaultDeadline;
  TaskSchedule(this.start, this.end, {this.defaultDeadline = false});
  factory TaskSchedule.forTask(SpaceTask t, DateTime today) {
    final defaultEnd = t.due.isEmpty && t.status != 'done';
    final end =
        parseDay(t.due) ??
        (t.status == 'done'
            ? beijingDay(validTime(t.completedAt!))
            : (parseDay(t.startDate) ?? today).add(const Duration(days: 5)));
    final start =
        parseDay(t.startDate) ??
        (defaultEnd ? today : beijingDay(validTime(t.createdAt)));
    return TaskSchedule(
      start.isAfter(end) ? end : start,
      end,
      defaultDeadline: defaultEnd,
    );
  }
  bool contains(DateTime d) => !d.isBefore(start) && !d.isAfter(end);
  TaskSchedule adjusting(String kind, int days) {
    final delta = Duration(days: days);
    if (kind == 'move') return TaskSchedule(start.add(delta), end.add(delta));
    if (kind == 'start') {
      final s = start.add(delta);
      return TaskSchedule(s.isAfter(end) ? end : s, end);
    }
    final e = end.add(delta);
    return TaskSchedule(start, e.isBefore(start) ? start : e);
  }

  SpaceTask apply(SpaceTask t) => t.patch({
    'startDate': dayString(start),
    'due': dayString(end),
    'updatedAt': timestamp(),
  });
}

dynamic sortedObject(dynamic v) {
  if (v is Map) {
    final keys = v.keys.cast<String>().toList()..sort();
    return {for (final k in keys) k: sortedObject(v[k])};
  }
  if (v is List) return v.map(sortedObject).toList();
  return v;
}

// Match Foundation JSONEncoder prettyPrinted including empty-container layout.
String swiftJson(dynamic object) {
  String render(dynamic v, int level) {
    final indent = '  ' * level, next = '  ' * (level + 1);
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      final body = keys
          .map((k) => '$next${jsonEncode(k)} : ${render(v[k], level + 1)}')
          .join(',\n');
      return '{\n$body\n$indent}';
    }
    if (v is List) {
      final body = v.map((x) => '$next${render(x, level + 1)}').join(',\n');
      return '[\n$body\n$indent]';
    }
    return jsonEncode(v);
  }

  return render(object, 0);
}
