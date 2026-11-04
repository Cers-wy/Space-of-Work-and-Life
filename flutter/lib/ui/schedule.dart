import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/models.dart';
import '../store.dart';
import 'theme.dart';
import 'gantt_colors.dart';
import 'controls.dart';
import 'dialogs.dart';

String shortDay(DateTime d) => '${d.month}/${d.day}';
String weekday(DateTime d) =>
    ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][d.weekday - 1];
Widget legend(BuildContext c) {
  final p = Palette.of(c);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, status) in builtins.indexed) ...[
        if (i > 0) const SizedBox(width: 12),
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.status(status),
          ),
        ),
        const SizedBox(width: 4),
        Text(statusName(status), style: textStyle(p, size: 12, color: p.muted)),
      ],
    ],
  );
}

class GanttView extends StatefulWidget {
  final SpaceStore store;
  const GanttView({super.key, required this.store});
  @override
  State<GanttView> createState() => _GanttViewState();
}

class _GanttViewState extends State<GanttView> {
  DateTime anchor = beijingDay();
  final collapsed = <String>{};
  SpaceStore get s => widget.store;
  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    final groups = <({String id, String name, List<SpaceTask> tasks})>[];
    for (final project in s.state.projects) {
      final tasks = s.visible.where((t) => t.projectID == project.id).toList();
      if (tasks.isNotEmpty) {
        groups.add((id: project.id, name: project.name, tasks: tasks));
      }
    }
    final none = s.visible.where((t) => t.projectID == null).toList();
    if (none.isNotEmpty) groups.add((id: '', name: '未分配项目', tasks: none));
    return Glass(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SpaceIcon('gantt', size: 16, color: p.text),
                const SizedBox(width: 8),
                Text('甘特图', style: textStyle(p, size: 16, bold: true)),
                const SizedBox(width: 12),
                Text(
                  '${anchor.year}年${anchor.month}月${anchor.day}日 至 ${anchor.add(const Duration(days: 13)).month}月${anchor.add(const Duration(days: 13)).day}日',
                  style: textStyle(p, size: 12, color: p.secondary),
                ),
                const Spacer(),
                IconButtonS(
                  'expand-all',
                  '展开全部项目',
                  size: 40,
                  iconSize: 20,
                  onPressed:
                      groups.isEmpty ||
                          groups.every((g) => !collapsed.contains(g.id))
                      ? null
                      : () => setState(collapsed.clear),
                ),
                const SizedBox(width: 12),
                IconButtonS(
                  'collapse-all',
                  '收起全部项目',
                  size: 40,
                  iconSize: 20,
                  onPressed:
                      groups.isEmpty ||
                          groups.every((g) => collapsed.contains(g.id))
                      ? null
                      : () => setState(
                          () => collapsed.addAll(groups.map((g) => g.id)),
                        ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 176,
                  child: DateField(
                    label: '查看日期',
                    allowsClear: false,
                    value: dayString(anchor),
                    onChanged: (v) {
                      final d = parseDay(v);
                      if (d != null) setState(() => anchor = d);
                    },
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.border),
          Expanded(
            child: LayoutBuilder(
              builder: (c, b) {
                final dw = math.max(48.0, (b.maxWidth - 400) / 14),
                    total = 400 + 14 * math.max(48.0, (b.maxWidth - 400) / 14);
                final rows =
                    <
                      ({
                        String? group,
                        String name,
                        SpaceTask? task,
                        List<SpaceTask> tasks,
                      })
                    >[];
                for (final group in groups) {
                  rows.add((
                    group: group.id,
                    name: group.name,
                    task: null,
                    tasks: group.tasks,
                  ));
                  if (!collapsed.contains(group.id)) {
                    for (final t in group.tasks) {
                      rows.add((
                        group: null,
                        name: '',
                        task: t,
                        tasks: const [],
                      ));
                    }
                  }
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: total.toDouble(),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 64,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 400,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 184,
                                        child: Text(
                                          '项目 / 任务名称',
                                          style: textStyle(
                                            p,
                                            size: 12,
                                            color: p.secondary,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 64,
                                        child: Text(
                                          '状态',
                                          style: textStyle(
                                            p,
                                            size: 12,
                                            color: p.secondary,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '开始 / 截止日期',
                                        style: textStyle(
                                          p,
                                          size: 12,
                                          color: p.secondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              for (var i = 0; i < 14; i++)
                                Container(
                                  width: dw,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color:
                                        dayString(
                                              anchor.add(Duration(days: i)),
                                            ) ==
                                            s.today
                                        ? p.hover
                                        : null,
                                    border: Border.all(
                                      color: p.border,
                                      width: .5,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        shortDay(anchor.add(Duration(days: i))),
                                        style: textStyle(
                                          p,
                                          size: 12,
                                          bold: true,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        dayString(
                                                  anchor.add(Duration(days: i)),
                                                ) ==
                                                s.today
                                            ? '今天'
                                            : weekday(
                                                anchor.add(Duration(days: i)),
                                              ).replaceFirst('星期', '周'),
                                        style: textStyle(
                                          p,
                                          size: 12,
                                          color: p.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: rows.length + 1,
                            itemBuilder: (c, i) {
                              if (i == rows.length) {
                                return SpaceButton(
                                  onPressed: () => editTask(
                                    c,
                                    s,
                                    SpaceTask.create(
                                      projectID: s.query.projectID,
                                    ),
                                  ),
                                  child: const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text('＋ 添加任务'),
                                  ),
                                );
                              }
                              final row = rows[i];
                              if (row.task != null) {
                                return _GanttRow(
                                  task: row.task!,
                                  store: s,
                                  anchor: anchor,
                                  dayWidth: dw,
                                );
                              }
                              final schedules = row.tasks
                                  .map(
                                    (t) => TaskSchedule.forTask(
                                      t,
                                      parseDay(s.today)!,
                                    ),
                                  )
                                  .toList();
                              final start = schedules
                                      .map((x) => x.start)
                                      .reduce((a, b) => a.isBefore(b) ? a : b),
                                  end = schedules
                                      .map((x) => x.end)
                                      .reduce((a, b) => a.isAfter(b) ? a : b);
                              final range = _barBounds(
                                TaskSchedule(start, end),
                                anchor,
                                dw,
                              );
                              return Container(
                                height: 48,
                                color: p.hover.withValues(
                                  alpha: p.dark ? 0.112 : .056,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 400,
                                      child: SpaceButton(
                                        onPressed: () => setState(() {
                                          if (!collapsed.remove(row.group)) {
                                            collapsed.add(row.group!);
                                          }
                                        }),
                                        child: Row(
                                          children: [
                                            SpaceIcon(
                                              collapsed.contains(row.group)
                                                  ? 'right'
                                                  : 'down',
                                              size: 12,
                                            ),
                                            const SizedBox(width: 8),
                                            SpaceIcon(
                                              'folder',
                                              color: p.purple,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                row.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: textStyle(p, bold: true),
                                              ),
                                            ),
                                            Text(
                                              '${row.tasks.length}',
                                              style: textStyle(
                                                p,
                                                size: 12,
                                                color: p.muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: dw * 14,
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: CustomPaint(
                                              painter: _GridPainter(
                                                anchor,
                                                dw,
                                                p,
                                                s.today,
                                              ),
                                            ),
                                          ),
                                          if (range != null)
                                            Positioned(
                                              left: range.$1,
                                              top: 20,
                                              width: range.$2,
                                              height: 8,
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: GanttInk.forStatus(
                                                    p,
                                                    'doing',
                                                  ).fill.withValues(alpha: .7),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final status in s.state.displayStatuses.where(
                        (v) =>
                            builtins.contains(v) ||
                            s.visible.any((t) => t.status == v),
                      ))
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: GanttInk.forStatus(p, status).fill,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              statusName(status),
                              style: textStyle(p, size: 12, color: p.secondary),
                            ),
                          ],
                        ),
                      Text(
                        '拖动排期条平移 · 拖动两端调整时长 · 虚线为默认排期',
                        style: textStyle(p, size: 12, color: p.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

(double, double)? _barBounds(
  TaskSchedule schedule,
  DateTime anchor,
  double dw,
) {
  final start = schedule.start.difference(anchor).inDays,
      end = schedule.end.difference(anchor).inDays;
  if (end < 0 || start > 13) return null;
  final a = math.max(0, start), b = math.min(13, end);
  return (a * dw + 6, math.max(12, (b - a + 1) * dw - 12));
}

class _GridPainter extends CustomPainter {
  final DateTime anchor;
  final double width;
  final Palette p;
  final String today;
  _GridPainter(this.anchor, this.width, this.p, this.today);
  @override
  void paint(Canvas c, Size size) {
    for (var i = 0; i < 14; i++) {
      final d = anchor.add(Duration(days: i)),
          now = dayString(anchor.add(Duration(days: i))) == today;
      final x = i * width;
      if (now || d.weekday >= 6) {
        c.drawRect(
          Rect.fromLTWH(x, 0, width, size.height),
          Paint()
            ..color = p.hover.withValues(
              alpha: now ? (p.dark ? 0.16 : .08) : .025,
            ),
        );
      }
      c.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = now ? p.accent.withValues(alpha: .65) : p.border
          ..strokeWidth = now ? 1 : .5,
      );
    }
    c.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = p.border
        ..strokeWidth = .5,
    );
  }

  @override
  bool shouldRepaint(_GridPainter o) =>
      o.anchor != anchor ||
      o.width != width ||
      o.p.dark != p.dark ||
      o.today != today;
}

class _GanttRow extends StatefulWidget {
  final SpaceTask task;
  final SpaceStore store;
  final DateTime anchor;
  final double dayWidth;
  const _GanttRow({
    required this.task,
    required this.store,
    required this.anchor,
    required this.dayWidth,
  });
  @override
  State<_GanttRow> createState() => _GanttRowState();
}

class _GanttRowState extends State<_GanttRow> {
  String kind = 'move';
  double distance = 0;
  TaskSchedule? preview;
  TaskSchedule get original =>
      TaskSchedule.forTask(widget.task, parseDay(widget.store.today)!);
  Widget handle(String mode, Widget child) => MouseRegion(
    cursor: mode == 'move'
        ? SystemMouseCursors.grab
        : SystemMouseCursors.resizeLeftRight,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) {
        kind = mode;
        distance = 0;
      },
      onHorizontalDragUpdate: (e) {
        distance += e.delta.dx;
        setState(
          () => preview = original.adjusting(
            kind,
            (distance / widget.dayWidth).round(),
          ),
        );
      },
      onHorizontalDragCancel: () => setState(() => preview = null),
      onHorizontalDragEnd: (_) async {
        final result = preview;
        setState(() => preview = null);
        if (result != null && (distance / widget.dayWidth).round() != 0) {
          await widget.store.saveTask(
            result.apply(widget.task),
            initial: widget.task,
          );
        }
      },
      child: child,
    ),
  );
  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c), t = widget.task;
    final schedule = preview ?? original;
    final bounds = _barBounds(schedule, widget.anchor, widget.dayWidth);
    final color = p.status(t.status);
    final ink = GanttInk.forStatus(p, t.status);
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          SizedBox(
            width: 400,
            child: GestureDetector(
              onTap: () => editTask(c, widget.store, t, existing: true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 184,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 24, right: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textStyle(p, bold: true),
                            ),
                            const SizedBox(height: 4),
                            CategoryLabel(t.category),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text(
                        statusName(t.status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle(p, size: 12, color: color),
                      ),
                    ),
                    SizedBox(
                      width: 128,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${shortDay(schedule.start)} → ${shortDay(schedule.end)}',
                            style: textStyle(p, size: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            schedule.defaultDeadline
                                ? '默认排期'
                                : '${schedule.end.difference(schedule.start).inDays + 1} 天',
                            style: textStyle(p, size: 12, color: p.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: widget.dayWidth * 14,
            height: 64,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GridPainter(
                      widget.anchor,
                      widget.dayWidth,
                      p,
                      widget.store.today,
                    ),
                  ),
                ),
                if (bounds != null)
                  Positioned(
                    left: bounds.$1,
                    top: 16,
                    width: bounds.$2,
                    height: 32,
                    child: GestureDetector(
                      onTap: () => editTask(c, widget.store, t, existing: true),
                      child: CustomPaint(
                        foregroundPainter: _DashedOutline(
                          ink.detail.withValues(
                            alpha: schedule.defaultDeadline ? .7 : .25,
                          ),
                          preview == null ? 1 : 2,
                          schedule.defaultDeadline,
                        ),
                        child: Container(
                          key: ValueKey('gantt-bar-${t.id}'),
                          decoration: BoxDecoration(
                            color: ink.fill,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              if (!schedule.start.isBefore(widget.anchor))
                                handle(
                                  'start',
                                  SizedBox(
                                    width: 12,
                                    height: 32,
                                    child: Center(
                                      child: Container(
                                        width: 3,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: ink.detail,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: handle(
                                  'move',
                                  SizedBox(
                                    height: 32,
                                    child: Center(
                                      child: Text(
                                        t.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textStyle(
                                          p,
                                          size: 12,
                                          color: ink.foreground,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (!schedule.end.isAfter(
                                widget.anchor.add(const Duration(days: 13)),
                              ))
                                handle(
                                  'end',
                                  SizedBox(
                                    width: 12,
                                    height: 32,
                                    child: Center(
                                      child: Container(
                                        width: 3,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: ink.detail,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CalendarView extends StatefulWidget {
  final SpaceStore store;
  const CalendarView({super.key, required this.store});
  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  DateTime anchor = beijingDay(), selected = beijingDay();
  SpaceStore get s => widget.store;
  List<SpaceTask>? _cachedTasks;
  String? _cachedDay;
  Map<String, TaskSchedule> _schedules = {};
  TaskSchedule scheduleFor(SpaceTask task) {
    if (!identical(_cachedTasks, s.visible) || _cachedDay != s.today) {
      _cachedTasks = s.visible;
      _cachedDay = s.today;
      final today = parseDay(s.today)!;
      _schedules = {
        for (final t in s.visible) t.id: TaskSchedule.forTask(t, today),
      };
    }
    return _schedules[task.id]!;
  }

  List<SpaceTask> items(DateTime day) =>
      s.visible.where((t) => scheduleFor(t).contains(day)).toList();
  void move(int delta) => setState(() {
    if (s.calendarMode == 'month') {
      anchor = DateTime.utc(anchor.year, anchor.month + delta);
    } else {
      anchor = anchor.add(
        Duration(days: delta * (s.calendarMode == 'week' ? 7 : 1)),
      );
    }
    selected = anchor;
  });
  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    return Glass(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 176,
                  child: DateField(
                    value: dayString(selected),
                    label: '查看日期',
                    allowsClear: false,
                    onChanged: (v) {
                      final d = parseDay(v);
                      if (d != null) {
                        setState(() {
                          selected = anchor = d;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.calendarMode == 'month'
                        ? '${anchor.year}年${anchor.month}月'
                        : s.calendarMode == 'day'
                        ? '${selected.month}月${selected.day}日 ${weekday(selected)}'
                        : '${shortDay(anchor.subtract(Duration(days: anchor.weekday - 1)))} 至 ${shortDay(anchor.add(Duration(days: 7 - anchor.weekday)))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(p, size: 16, bold: true),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: p.hover,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      for (final e in {
                        'day': '日',
                        'week': '周',
                        'month': '月',
                      }.entries) ...[
                        if (e.key != 'day') const SizedBox(width: 2),
                        SizedBox(
                          width: 40,
                          child: SpaceButton(
                            height: 32,
                            padding: EdgeInsets.zero,
                            primary: s.calendarMode == e.key,
                            onPressed: () {
                              setState(() => anchor = selected);
                              s.preference('calendarMode', e.key);
                            },
                            child: Text(
                              e.value,
                              style: textStyle(
                                p,
                                bold: true,
                                color: s.calendarMode == e.key
                                    ? Colors.white
                                    : p.secondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.border),
          Expanded(
            child: s.calendarMode == 'day'
                ? agenda(selected, wide: true)
                : s.calendarMode == 'week'
                ? week()
                : month(),
          ),
        ],
      ),
    );
  }

  Widget agenda(DateTime d, {bool wide = false}) {
    final p = Palette.of(context), tasks = items(d);
    return Padding(
      padding: EdgeInsets.all(wide ? 24 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${d.month}月${d.day}日 ${weekday(d)}',
            style: textStyle(p, size: 16, bold: true),
          ),
          const SizedBox(height: 12),
          Text(
            '${tasks.length} 个事项 · 按排期展示',
            style: textStyle(p, size: 12, color: p.muted),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: tasks.length + 1,
              separatorBuilder: (_, i) => const SizedBox(height: 8),
              itemBuilder: (c, i) => i < tasks.length
                  ? scheduleCard(tasks[i])
                  : Column(
                      children: [
                        if (tasks.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Column(
                              children: [
                                SpaceIcon('calendar', size: 24, color: p.muted),
                                const SizedBox(height: 8),
                                Text(
                                  '当天暂无事项',
                                  style: textStyle(p, color: p.muted),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '可添加事项，或选择其他日期。',
                                  style: textStyle(p, size: 12, color: p.muted),
                                ),
                              ],
                            ),
                          ),
                        SpaceButton(
                          onPressed: () => editTask(
                            c,
                            s,
                            SpaceTask.create(
                              due: dayString(d),
                              projectID: s.query.projectID,
                            ),
                          ),
                          child: const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('＋ 添加事项'),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          legend(context),
        ],
      ),
    );
  }

  Widget scheduleCard(SpaceTask t) {
    final p = Palette.of(context);
    final schedule = TaskSchedule.forTask(t, parseDay(s.today)!);
    return Glass(
      blur: false,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButtonS(
                t.status == 'done' ? 'done' : 'circle',
                t.status == 'done' ? '重新开启：${t.title}' : '完成：${t.title}',
                size: 20,
                iconSize: 16,
                onPressed: () =>
                    s.moveTask(t.id, t.status == 'done' ? 'todo' : 'done'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => editTask(context, s, t, existing: true),
                  child: Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(p, bold: true),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              CategoryLabel(t.category),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  statusName(t.status),
                  style: textStyle(p, size: 12, color: p.status(t.status)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${schedule.defaultDeadline ? '默认截止' : '截止'} ${shortDay(schedule.end)}',
            style: textStyle(p, size: 12, color: p.muted),
          ),
          if (s.state.projectName(t.projectID) != null) ...[
            const SizedBox(height: 8),
            Text(
              s.state.projectName(t.projectID)!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle(p, size: 12, color: p.purple),
            ),
          ],
        ],
      ),
    );
  }

  Widget month() => LayoutBuilder(
    builder: (c, b) {
      final p = Palette.of(c);
      final first = DateTime.utc(anchor.year, anchor.month);
      final start = first.subtract(Duration(days: first.weekday - 1));
      final last = DateTime.utc(anchor.year, anchor.month + 1, 0);
      final count = ((last.difference(start).inDays + 7) ~/ 7) * 7;
      final rows = count ~/ 7;
      final side = b.maxWidth >= 1100 ? 280.0 : 232.0;
      final height = math.max(88.0, (b.maxHeight - 32) / rows);
      final limit = math.max(1, math.min(3, ((height - 70) / 24).floor()));
      return Row(
        children: [
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      for (final d in ['一', '二', '三', '四', '五', '六', '日'])
                        Expanded(
                          child: Center(
                            child: Text(
                              '周$d',
                              style: textStyle(p, size: 12, color: p.secondary),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var row = 0; row < rows; row++)
                          SizedBox(
                            height: height,
                            child: Row(
                              children: [
                                for (var col = 0; col < 7; col++)
                                  Expanded(
                                    child: monthCell(
                                      start.add(Duration(days: row * 7 + col)),
                                      height,
                                      limit,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: p.border),
          SizedBox(width: side, child: agenda(selected)),
        ],
      );
    },
  );
  Widget monthCell(DateTime d, double height, int limit) {
    final p = Palette.of(context);
    final tasks = items(d);
    final isSelected = dayString(d) == dayString(selected);
    final today = dayString(d) == s.today;
    return GestureDetector(
      onTap: () => setState(() => selected = d),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? p.hover : Colors.transparent,
        ),
        foregroundDecoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? p.accent : p.border,
            width: isSelected ? 1.5 : .5,
          ),
        ),
        child: ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: today ? p.primary : Colors.transparent,
                ),
                child: Text(
                  '${d.day}',
                  style: textStyle(
                    p,
                    size: 12,
                    bold: true,
                    color: today
                        ? Colors.white
                        : d.month == anchor.month
                        ? p.text
                        : p.muted,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              for (final t in tasks.take(limit))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => selected = d);
                      editTask(context, s, t, existing: true);
                    },
                    child: Container(
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: p.status(t.status).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: p.status(t.status),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              t.title,
                              style: textStyle(p, size: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (tasks.length > limit)
                GestureDetector(
                  onTap: () => setState(() => selected = d),
                  child: SizedBox(
                    height: 18,
                    child: Text(
                      '还有 ${tasks.length - limit} 项',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle(p, size: 12, color: p.muted),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget week() => LayoutBuilder(
    builder: (c, b) {
      final p = Palette.of(c);
      final start = anchor.subtract(Duration(days: anchor.weekday - 1));
      final width = math.max(148.0, b.maxWidth / 7);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < 7; i++)
              SizedBox(
                width: width,
                height: b.maxHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: p.border, width: .5),
                  ),
                  child: Column(
                    children: [
                      SpaceButton(
                        height: 64,
                        onPressed: () => setState(
                          () => selected = start.add(Duration(days: i)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${start.add(Duration(days: i)).day}',
                              style: textStyle(p, size: 16, bold: true),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              weekday(start.add(Duration(days: i))),
                              style: textStyle(p, size: 12, color: p.secondary),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: p.border),
                      Expanded(
                        child: Builder(
                          builder: (c) {
                            final d = start.add(Duration(days: i)),
                                tasks = items(d);
                            return ListView.separated(
                              padding: const EdgeInsets.all(8),
                              itemCount: tasks.length + 1,
                              separatorBuilder: (_, i) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (c, i) => i == tasks.length
                                  ? SpaceButton(
                                      onPressed: () => editTask(
                                        c,
                                        s,
                                        SpaceTask.create(due: dayString(d)),
                                      ),
                                      child: const Text('＋ 添加事项'),
                                    )
                                  : scheduleCard(tasks[i]),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _DashedOutline extends CustomPainter {
  final Color color;
  final double width;
  final bool dashed;
  _DashedOutline(this.color, this.width, this.dashed);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(width / 2),
          const Radius.circular(8),
        ),
      );
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += 8) {
        canvas.drawPath(
          metric.extractPath(offset, math.min(offset + 5, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) =>
      old.color != color || old.width != width || old.dashed != dashed;
}
