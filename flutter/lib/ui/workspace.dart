import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../store.dart';
import 'theme.dart';
import 'controls.dart';
import 'dialogs.dart';
import 'invoice_workspace.dart';
import 'schedule.dart';

final dragActive = ValueNotifier(false);

class Workspace extends StatefulWidget {
  final SpaceStore store;
  const Workspace({super.key, required this.store});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  final search = TextEditingController(), searchFocus = FocusNode();
  final invoiceFilterAnchor = GlobalKey();
  final filterAnchor = GlobalKey();
  final viewSwitchKey = GlobalKey();
  final taskTableScroll = ScrollController();
  final previewWidths = <String, double>{};
  late final InvoiceSession invoices;
  SpaceStore get s => widget.store;
  late bool previousNavCollapsed;
  bool navMoving = false;
  int navigationEpoch = 0;
  @override
  void initState() {
    super.initState();
    invoices = InvoiceSession(s.repository);
    s.searchRequested.addListener(requestSearch);
    previousNavCollapsed = s.navCollapsed;
    s.addListener(trackNavigation);
  }

  void trackNavigation() {
    if (!mounted) return;
    if (search.text != s.query.text) {
      search.value = TextEditingValue(
        text: s.query.text,
        selection: TextSelection.collapsed(offset: s.query.text.length),
      );
    }
    if (s.navCollapsed == previousNavCollapsed) return;
    previousNavCollapsed = s.navCollapsed;
    navigationEpoch++;
    setState(() => navMoving = !MediaQuery.disableAnimationsOf(context));
  }

  void requestSearch() {
    if (s.modal) return;
    if (s.area == SpaceArea.invoices) {
      invoiceFilters();
      return;
    }
    if (s.area != SpaceArea.tasks) return;
    if (s.overviewCollapsed) {
      filters();
    } else {
      searchFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    s.searchRequested.removeListener(requestSearch);
    s.removeListener(trackNavigation);
    search.dispose();
    searchFocus.dispose();
    taskTableScroll.dispose();
    invoices.dispose();
    super.dispose();
  }

  void newTask({String status = 'todo', String due = ''}) => editTask(
    context,
    s,
    SpaceTask.create(status: status, due: due, projectID: s.query.projectID),
  );
  void filters() => showFilters(filterAnchor.currentContext ?? context, s);
  void invoiceFilters() {
    if (invoiceFilterAnchor.currentContext case final anchor?) {
      showInvoiceFilters(anchor, s, invoices);
    }
  }

  KeyEventResult key(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent || s.modal) return KeyEventResult.ignored;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final editable =
        focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null ||
        focusContext?.findAncestorStateOfType<EditableTextState>() != null;
    final cmd =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final k = e.logicalKey;
    if (s.area != SpaceArea.tasks) {
      if (cmd && k == LogicalKeyboardKey.keyF && s.area == SpaceArea.invoices) {
        invoiceFilters();
        return KeyEventResult.handled;
      }
      if (cmd && k == LogicalKeyboardKey.comma) {
        showSettings(context, s);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (editable) {
      if (cmd && k == LogicalKeyboardKey.keyF) {
        searchFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if ((cmd || !HardwareKeyboard.instance.isAltPressed) &&
        k == LogicalKeyboardKey.keyN) {
      newTask();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.slash || cmd && k == LogicalKeyboardKey.keyF) {
      if (s.overviewCollapsed) {
        filters();
      } else {
        searchFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (cmd && k == LogicalKeyboardKey.keyZ) {
      s.undo();
      return KeyEventResult.handled;
    }
    if (cmd && k == LogicalKeyboardKey.comma) {
      showSettings(context, s);
      return KeyEventResult.handled;
    }
    final views = {
      LogicalKeyboardKey.digit1: 'board',
      LogicalKeyboardKey.digit2: 'list',
      LogicalKeyboardKey.digit3: 'gantt',
      LogicalKeyboardKey.digit4: 'calendar',
    };
    if (views.containsKey(k)) {
      s.preference('viewMode', views[k]!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (search.text != s.query.text) {
      search.value = TextEditingValue(
        text: s.query.text,
        selection: TextSelection.collapsed(offset: s.query.text.length),
      );
    }
    return Focus(
      autofocus: true,
      onKeyEvent: key,
      child: LayoutBuilder(
        builder: (context, box) {
          final nav = s.navCollapsed
              ? 64.0
              : box.maxWidth >= 1600
              ? 240.0
              : 224.0;
          final workspaceContent = TweenAnimationBuilder<double>(
            key: ValueKey(s.area),
            tween: Tween(begin: 0, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: spaceCurve,
            builder: (context, opacity, child) =>
                Opacity(opacity: opacity, child: child),
            child: switch (s.area) {
              SpaceArea.tasks => taskWorkspace(box, p),
              SpaceArea.tools => InvoiceWorkspace(
                key: const ValueKey('tools-area'),
                store: s,
                session: invoices,
                showTools: true,
                filterAnchor: invoiceFilterAnchor,
              ),
              SpaceArea.invoices => InvoiceWorkspace(
                key: const ValueKey('invoice-area'),
                store: s,
                session: invoices,
                showTools: false,
                filterAnchor: invoiceFilterAnchor,
              ),
            },
          );
          // One persistent sidebar: the parent supplies its animated width.
          // Never cross-fade two complete glass surfaces or duplicate controls.
          final expandedNav = box.maxWidth >= 1600 ? 240.0 : 224.0;
          final navigation = sidebar(expandedNav, s.navCollapsed);
          final ambient = Ambient();
          return WorkspaceMotion(
            active: navMoving,
            child: TweenAnimationBuilder<double>(
              onEnd: () {
                // Keep the final layout frame in resize mode too. Otherwise
                // column tweens restart just as the navigation finishes.
                final completedEpoch = navigationEpoch;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted &&
                      navMoving &&
                      completedEpoch == navigationEpoch) {
                    setState(() => navMoving = false);
                  }
                });
              },
              tween: Tween(end: nav),
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : spaceDuration,
              curve: spaceCurve,
              builder: (context, animatedNav, _) => Stack(
                children: [
                  Positioned.fill(child: ambient),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: animatedNav + 8,
                          top: 0,
                          right: 0,
                          bottom: 0,
                          child: workspaceContent,
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: animatedNav,
                          child: navigation,
                        ),
                      ],
                    ),
                  ),
                  if (s.notice != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 24,
                      child: Center(
                        child: Glass(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(s.notice!, style: textStyle(p, size: 12)),
                              if (s.canUndo) ...[
                                const SizedBox(width: 12),
                                SpaceButton(
                                  height: 32,
                                  onPressed: s.undo,
                                  child: Text(
                                    '撤销',
                                    style: textStyle(
                                      p,
                                      size: 12,
                                      color: p.accent,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget unavailable() {
    final p = Palette.of(context);
    return Glass(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('无法读取本地任务', style: textStyle(p, size: 20, bold: true)),
            const SizedBox(height: 16),
            Text(
              '原文件保持不变。请重新载入，或在设置中导入有效备份。',
              style: textStyle(p, color: p.secondary),
            ),
            const SizedBox(height: 16),
            SpaceButton(
              onPressed: () => showSettings(context, s),
              child: const Text('数据与设置'),
            ),
          ],
        ),
      ),
    );
  }

  Widget taskWorkspace(BoxConstraints box, Palette p) => Column(
    key: const ValueKey('tasks-area'),
    children: [
      overview(box),
      if (s.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Glass(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.error!,
                    style: textStyle(p, size: 12, color: p.red),
                  ),
                ),
                SpaceButton(
                  height: 32,
                  onPressed: s.reload,
                  child: const Text('重新载入'),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      Expanded(
        child: !s.loaded
            ? unavailable()
            : AnimatedSwitcher(
                duration: MediaQuery.of(context).disableAnimations
                    ? Duration.zero
                    : spaceDuration,
                switchInCurve: spaceCurve,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: .985, end: 1).animate(a),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(s.view),
                  child: BackdropGroup(
                    child: RepaintBoundary(
                      child: s.view == 'board'
                          ? board()
                          : s.view == 'list'
                          ? taskList()
                          : s.view == 'gantt'
                          ? GanttView(store: s)
                          : CalendarView(store: s),
                    ),
                  ),
                ),
              ),
      ),
    ],
  );

  Widget sidebar(double expandedWidth, bool collapsed) {
    final p = Palette.of(context);
    const mark = RepaintBoundary(child: Mark(key: ValueKey('navigation-mark')));
    final taskIcon = RepaintBoundary(
      child: Container(
        key: const ValueKey('navigation-task-icon'),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: s.area == SpaceArea.tasks ? p.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: SpaceIcon(
          'grid',
          size: 16,
          color: s.area == SpaceArea.tasks ? Colors.white : p.secondary,
        ),
      ),
    );
    final settings = RepaintBoundary(
      child: IconButtonS(
        'gear',
        '数据与设置（⌘,）',
        key: const ValueKey('navigation-settings'),
        onPressed: () => showSettings(context, s),
      ),
    );
    final brand = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Space', style: textStyle(p, size: 24, bold: true)),
        Text('个人工作台', style: textStyle(p, size: 12, color: p.secondary)),
      ],
    );
    final heading = Text('工作空间', style: textStyle(p, size: 12, color: p.muted));
    final taskLabel = Row(
      children: [
        const Text('任务'),
        const Spacer(),
        Text(
          '${s.state.tasks.length}',
          style: textStyle(p, size: 12, color: p.muted),
        ),
      ],
    );
    return Glass(
      key: const ValueKey('navigation-sidebar'),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final progress = ((bounds.maxWidth - 64) / (expandedWidth - 64))
              .clamp(0.0, 1.0);
          Widget label(Widget child) => ExcludeSemantics(
            excluding: collapsed,
            child: Opacity(opacity: progress, child: child),
          );
          Widget areaEntry(
            SpaceArea area,
            String icon,
            String title,
            double top,
          ) {
            final selected = s.area == area;
            final isTasks = area == SpaceArea.tasks;
            return Positioned(
              left: 8 + 8 * progress,
              width: bounds.maxWidth - 16 - 16 * progress,
              top: top - 40 * (1 - progress),
              child: SpaceButton(
                key: ValueKey('navigation-${isTasks ? 'task' : area.name}'),
                tooltip: isTasks ? '任务，${s.state.tasks.length}项任务' : title,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                selected: selected,
                showSelectedBackground: false,
                showHoverBackground: !selected,
                onPressed: () {
                  if (isTasks && selected) {
                    s.resetQuery();
                  } else {
                    s.openArea(area);
                  }
                },
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: expandedWidth - 48,
                    maxWidth: expandedWidth - 48,
                    child: Row(
                      children: [
                        if (isTasks)
                          taskIcon
                        else
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? p.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SpaceIcon(
                              icon,
                              size: 16,
                              color: selected ? Colors.white : p.secondary,
                            ),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: label(
                            isTasks
                                ? taskLabel
                                : Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          // Labels keep a fixed layout width while the clickable area follows the sidebar.
          return OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: expandedWidth,
            maxWidth: expandedWidth,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 16,
                  top: 16,
                  child: Transform.translate(
                    offset: Offset(0, 8 * progress),
                    child: mark,
                  ),
                ),
                Positioned(left: 56, top: 16, child: label(brand)),
                Positioned(left: 24, top: 80, child: label(heading)),
                areaEntry(SpaceArea.tasks, 'grid', '任务', 104),
                if (Platform.isMacOS || Platform.isWindows) ...[
                  areaEntry(SpaceArea.tools, 'tools', '工具', 148),
                  areaEntry(SpaceArea.invoices, 'invoice', '发票', 192),
                ],
                Positioned(left: 16, bottom: 16, child: settings),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget overview(BoxConstraints box) {
    final content = s.overviewCollapsed
        ? const SizedBox.shrink()
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * .5),
            child: SingleChildScrollView(
              child: overviewContent(
                box.maxWidth,
                compact: box.maxHeight < 720,
              ),
            ),
          );
    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          taskTitleBar(),
          if (MediaQuery.disableAnimationsOf(context))
            content
          else
            AnimatedSize(
              duration: spaceDuration,
              curve: spaceCurve,
              alignment: Alignment.topCenter,
              clipBehavior: Clip.hardEdge,
              child: content,
            ),
        ],
      ),
    );
  }

  Widget taskTitleBar() {
    final p = Palette.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final separateViews = box.maxWidth < 840;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpaceTitleBar(
              key: const ValueKey('workspace-titlebar'),
              children: [
                IconButtonS.toolbar(
                  s.navCollapsed ? 'sidebar-open' : 'sidebar-close',
                  s.navCollapsed ? '展开导航' : '收起导航',
                  key: const ValueKey('navigation-toggle'),
                  iconSize: 18,
                  onPressed: () =>
                      s.preference('navCollapsed', '${!s.navCollapsed}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (c, b) => Row(
                      children: [
                        if (b.maxWidth >= 240) ...[
                          Text(
                            '我的空间',
                            style: textStyle(p, size: 12, color: p.muted),
                          ),
                          const SizedBox(width: 12),
                          SpaceIcon('right', size: 10, color: p.muted),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Text(
                            s.overviewCollapsed
                                ? '任务 · ${s.visible.length} 个任务'
                                : '任务管理',
                            style: textStyle(p, size: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (b.maxWidth > 460) ...[
                          const SizedBox(width: 12),
                          categoryCounts(),
                        ],
                      ],
                    ),
                  ),
                ),
                if (s.overviewCollapsed) ...[
                  const SizedBox(
                    width: 16,
                    key: ValueKey('category-filter-gap'),
                  ),
                  IconButtonS.toolbar(
                    'filter',
                    '筛选与排序',
                    key: filterAnchor,
                    onPressed: filters,
                  ),
                  const SizedBox(width: 8),
                  IconButtonS.toolbar(
                    'plus',
                    '新建任务（⌘N / N）',
                    onPressed: s.loaded ? newTask : null,
                  ),
                  const SizedBox(width: 16),
                ],
                if (!separateViews) ...[
                  viewSwitch(),
                  const SizedBox(width: 16),
                ],
                ThemeToggle(dark: s.dark, onToggle: s.toggleTheme),
                const SizedBox(width: 8),
                IconButtonS.toolbar(
                  'project',
                  '项目管理',
                  onPressed: () => showProjects(context, s),
                ),
                const SizedBox(width: 8),
                IconButtonS.toolbar(
                  'status',
                  '状态与分类管理',
                  onPressed: () => showStatuses(context, s),
                ),
                if (s.canUndo) ...[
                  const SizedBox(width: 8),
                  IconButtonS.toolbar(
                    'undo',
                    '撤销最近一次更改（⌘Z）',
                    onPressed: s.undo,
                  ),
                ],
                const SizedBox(width: 8),
                IconButtonS.toolbar(
                  'help',
                  '使用帮助',
                  onPressed: () => showHelp(context, s),
                ),
                const SizedBox(width: 8),
                IconButtonS.toolbar(
                  s.overviewCollapsed ? 'down' : 'up',
                  s.overviewCollapsed ? '展开概览' : '收起概览',
                  onPressed: () => s.preference(
                    'overviewCollapsed',
                    '${!s.overviewCollapsed}',
                  ),
                ),
              ],
            ),
            if (separateViews) SpaceTitleBar(children: [viewSwitch()]),
          ],
        );
      },
    );
  }

  Widget overviewContent(double windowWidth, {required bool compact}) {
    final p = Palette.of(context);
    final add = IconButtonS(
      'plus',
      '新建任务（⌘N / N）',
      primary: true,
      onPressed: s.loaded ? newTask : null,
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact)
            Row(
              children: [
                Expanded(child: statistics()),
                const SizedBox(width: 16),
                add,
              ],
            )
          else if (windowWidth <= 1180) ...[
            Row(
              children: [
                Expanded(child: heading()),
                add,
              ],
            ),
            const SizedBox(height: 24),
            statistics(),
          ] else
            LayoutBuilder(
              builder: (c, b) => Row(
                children: [
                  Expanded(child: heading()),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: math.max(320, (b.maxWidth - 64) * .60),
                    child: statistics(),
                  ),
                  const SizedBox(width: 24),
                  add,
                ],
              ),
            ),
          SizedBox(height: compact ? 12 : 24),
          Glass(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('任务', style: textStyle(p, bold: true)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: p.hover,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${s.visible.length} 个任务',
                        style: textStyle(p, size: 12, color: p.muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (c, b) {
                    final controls = filterControls(p);
                    final field = SpaceInput(
                      fontSize: 12,
                      controller: search,
                      focusNode: searchFocus,
                      hint: '搜索任务标题与说明',
                      icon: 'search',
                      label: '搜索任务',
                      onChanged: (v) {
                        s.query.text = v;
                        s.refreshQuery();
                      },
                    );
                    if (b.maxWidth < 740) {
                      return Column(
                        children: [field, const SizedBox(height: 12), controls],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: field),
                        const SizedBox(width: 12),
                        controls,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget heading() {
    final p = Palette.of(context);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: p.hover,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: SpaceIcon('board', size: 18, color: p.accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('任务', style: textStyle(p, size: 24, bold: true)),
              const SizedBox(height: 4),
              Text(
                '安排好每一步，留一点空间给生活。',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle(p, size: 12, color: p.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget statistics() {
    final p = Palette.of(context);
    final entries = [
      ('全部任务', s.state.tasks.length, p.blue),
      ('进行中', s.state.tasks.where((t) => t.status == 'doing').length, p.purple),
      ('已逾期', s.state.tasks.where((t) => t.overdue(s.today)).length, p.amber),
      ('已完成', s.state.tasks.where((t) => t.status == 'done').length, p.green),
    ];
    return Row(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: entries[i].$3.withValues(alpha: p.dark ? 0.12 : .08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: p.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entries[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(p, size: 12, color: p.secondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entries[i].$2.toString().padLeft(2, '0'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(
                      p,
                      size: 24,
                      bold: true,
                      color: entries[i].$3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 标题栏分类标签只用来快速筛选，始终保持常态外观，不显示选中态。
  Widget categoryCounts() => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 280),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final k in s.state.taskCategories.keys)
            SpaceButton(
              key: ValueKey('category-quick-$k'),
              height: 24,
              padding: const EdgeInsets.all(4),
              tooltip:
                  '快速筛选${s.state.taskCategories[k]}'
                  '${s.query.categoryIDs.contains(k) ? '（已筛选）' : ''}',
              onPressed: () {
                if (!s.query.categoryIDs.remove(k)) s.query.categoryIDs.add(k);
                s.refreshQuery();
              },
              child: CategoryLabel(
                k,
                name: s.state.taskCategories[k],
                count: s.state.tasks.where((t) => t.category == k).length,
              ),
            ),
        ],
      ),
    ),
  );
  Widget viewSwitch() => Row(
    key: viewSwitchKey,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, (mode, label)) in const [
        ('board', '看板视图'),
        ('list', '列表视图'),
        ('gantt', '甘特图视图'),
        ('calendar', '日历视图'),
      ].indexed) ...[
        if (i > 0) const SizedBox(width: 4),
        IconButtonS.toolbar(
          mode,
          label,
          selected: s.view == mode,
          soft: true,
          onPressed: () => s.preference('viewMode', mode),
        ),
      ],
    ],
  );

  Widget filterControls(Palette p) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SpaceMultiSelect(
        values: s.query.statusIDs,
        options: {for (final v in s.state.statuses) v: statusName(v)},
        label: '状态',
        width: 120,
        onChanged: s.refreshQuery,
      ),
      SpaceMultiSelect(
        values: s.query.priorityIDs,
        options: priorities,
        label: '优先级',
        width: 136,
        onChanged: s.refreshQuery,
      ),
      SizedBox(
        key: filterAnchor,
        width: 40,
        height: 40,
        child: SpaceButton(
          tooltip: '筛选与排序',
          padding: EdgeInsets.zero,
          onPressed: filters,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SpaceIcon('filter', color: p.secondary),
              const SizedBox(width: 4),
              SpaceIcon('down', size: 9, color: p.secondary),
            ],
          ),
        ),
      ),
      SpaceSelect(
        value: s.query.sort,
        options: const {
          'due': '截止日期优先',
          'priority': '优先级由高到低',
          'created': '最近创建优先',
        },
        label: '任务排序',
        width: 160,
        onChanged: (v) {
          s.query.sort = v;
          s.refreshQuery();
        },
      ),
      if (s.query.hasFilters)
        SpaceButton(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          onPressed: () {
            s.query.clear();
            s.refreshQuery();
          },
          child: const Text('清除'),
        ),
    ],
  );
  Widget board() {
    final statuses = s.boardStatuses;
    return LayoutBuilder(
      builder: (c, b) {
        final width = math.max(
          280.0,
          (b.maxWidth - 12 * (statuses.length - 1)) / statuses.length,
        );
        final columns = {
          for (final status in statuses)
            status: column(status, baseWidth: width),
        };
        final widths = {
          for (final status in statuses)
            status:
                width * (previewWidths[status] ?? s.boardWidthRatio(status)),
        };
        final total =
            widths.values.fold(0.0, (a, b) => a + b) +
            12 * (statuses.length - 1);
        return Align(
          alignment: Alignment.topLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < statuses.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  TweenAnimationBuilder<double>(
                    key: ValueKey(statuses[i]),
                    tween: Tween(end: widths[statuses[i]]!),
                    duration:
                        MediaQuery.of(context).disableAnimations ||
                            navMoving ||
                            dragActive.value
                        ? Duration.zero
                        : spaceDuration,
                    curve: spaceCurve,
                    builder: (context, animatedWidth, content) => SizedBox(
                      key: ValueKey('board-column-${statuses[i]}'),
                      width: animatedWidth,
                      height: b.maxHeight - (total > b.maxWidth ? 16 : 0),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(child: content!),
                          Positioned(
                            right: 0,
                            top: 0,
                            height: 44,
                            width: 8,
                            child: BoardResizeHandle(
                              key: ValueKey('board-resize-${statuses[i]}'),
                              ratio:
                                  previewWidths[statuses[i]] ??
                                  s.boardWidthRatio(statuses[i]),
                              onStart: () => dragActive.value = true,
                              onUpdate: (delta) => setState(() {
                                final current =
                                    previewWidths[statuses[i]] ??
                                    s.boardWidthRatio(statuses[i]);
                                previewWidths[statuses[i]] =
                                    (current + delta / width).clamp(.5, 1.0);
                              }),
                              onEnd: () async {
                                dragActive.value = false;
                                final ratio = clampBoardRatio(
                                  previewWidths[statuses[i]] ??
                                      s.boardWidthRatio(statuses[i]),
                                );
                                setState(
                                  () => previewWidths[statuses[i]] = ratio,
                                );
                                await s.preference(
                                  'boardWidth.${statuses[i]}',
                                  ratio.toStringAsFixed(4),
                                );
                                if (mounted) {
                                  setState(
                                    () => previewWidths.remove(statuses[i]),
                                  );
                                }
                              },
                              onReset: () async {
                                await s.preference(
                                  'boardWidth.${statuses[i]}',
                                  '1.0',
                                );
                                if (mounted) {
                                  setState(
                                    () => previewWidths.remove(statuses[i]),
                                  );
                                }
                              },
                              onCancel: () {
                                dragActive.value = false;
                                setState(
                                  () => previewWidths.remove(statuses[i]),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    child: columns[statuses[i]],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// 列宽的键盘等效操作：Option + 左右方向键每次 8 像素，按住 Shift 为 32。
  Future<void> nudgeWidth(
    String status,
    double baseWidth,
    int direction,
    bool coarse,
  ) async {
    final ratio = clampBoardRatio(
      s.boardWidthRatio(status) + direction * (coarse ? 32 : 8) / baseWidth,
    );
    await s.preference('boardWidth.$status', ratio.toStringAsFixed(4));
    if (mounted) setState(() => previewWidths.remove(status));
  }

  Widget column(String status, {double baseWidth = 320}) {
    final p = Palette.of(context);
    final tasks = s.grouped[status] ?? [];
    final disabled = s.state.disabledStatuses.contains(status);
    return DragTarget<_TaskDrag>(
      onWillAcceptWithDetails: (d) => !disabled && d.data.task.status != status,
      onAcceptWithDetails: (d) => s.moveTask(d.data.task.id, status),
      builder: (c, accepted, rejected) => DecoratedBox(
        decoration: BoxDecoration(
          border: accepted.isNotEmpty
              ? Border.all(color: p.accent, width: 2)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Glass(
          child: Column(
            children: [
              DragTarget<_StatusDrag>(
                onAcceptWithDetails: (d) =>
                    s.reorderStatus(d.data.status, status),
                builder: (c, candidates, rejected) => CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.arrowLeft,
                      alt: true,
                    ): () => nudgeWidth(
                      status,
                      baseWidth,
                      -1,
                      HardwareKeyboard.instance.isShiftPressed,
                    ),
                    const SingleActivator(
                      LogicalKeyboardKey.arrowRight,
                      alt: true,
                    ): () => nudgeWidth(
                      status,
                      baseWidth,
                      1,
                      HardwareKeyboard.instance.isShiftPressed,
                    ),
                  },
                  child: Focus(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      color: candidates.isNotEmpty
                          ? p.hover
                          : p
                                .status(status)
                                .withValues(alpha: p.dark ? 0.07 : .05),
                      child: Row(
                        children: [
                          Draggable<_StatusDrag>(
                            data: _StatusDrag(status),
                            feedback: Material(
                              color: Colors.transparent,
                              child: Glass(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  statusName(status),
                                  style: textStyle(p, bold: true),
                                ),
                              ),
                            ),
                            child: Tooltip(
                              message: '拖动排序：${statusName(status)}',
                              child: const SizedBox(
                                width: 24,
                                height: 28,
                                child: Center(
                                  child: SpaceIcon('menu', size: 12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: p.status(status),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Tooltip(
                              message:
                                  '${statusName(status)}${disabled ? ' · 已停用' : ''}',
                              child: Text(
                                '${statusName(status)}${disabled ? ' · 已停用' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textStyle(
                                  p,
                                  size: 12,
                                  bold: true,
                                  color: disabled ? p.amber : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${tasks.length}',
                            style: textStyle(p, size: 12, color: p.muted),
                          ),
                          IconButtonS(
                            'plus',
                            '在${statusName(status)}中新建任务',
                            size: 28,
                            onPressed: disabled
                                ? null
                                : () => newTask(status: status),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: p.border),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: tasks.length + 1,
                  separatorBuilder: (_, i) => const SizedBox(height: 12),
                  itemBuilder: (c, i) {
                    if (i == tasks.length) {
                      return Column(
                        children: [
                          SpaceButton(
                            onPressed: disabled
                                ? null
                                : () => newTask(status: status),
                            child: Row(
                              children: [
                                SpaceIcon('plus', size: 12, color: p.muted),
                                const SizedBox(width: 8),
                                Text(
                                  '添加任务',
                                  style: textStyle(p, size: 12, color: p.muted),
                                ),
                                const Spacer(),
                              ],
                            ),
                          ),
                          if (tasks.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: Column(
                                children: [
                                  SpaceIcon('tray', size: 24, color: p.muted),
                                  const SizedBox(height: 8),
                                  Text(
                                    '暂无${statusName(status)}任务',
                                    style: textStyle(
                                      p,
                                      size: 12,
                                      color: p.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '拖动任务到这里，或点击加号新建。',
                                    textAlign: TextAlign.center,
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
                      );
                    }
                    final task = tasks[i];
                    final card = TaskCard(
                      task: task,
                      store: s,
                      onEdit: () => editTask(context, s, task, existing: true),
                    );
                    return Builder(
                      builder: (cardContext) => Draggable<_TaskDrag>(
                        data: _TaskDrag(task),
                        dragAnchorStrategy: pointerDragAnchorStrategy,
                        onDragStarted: () => dragActive.value = true,
                        onDragEnd: (_) => dragActive.value = false,
                        onDraggableCanceled: (_, pt) =>
                            dragActive.value = false,
                        feedback: Material(
                          type: MaterialType.transparency,
                          child: Builder(
                            builder: (_) => SizedBox(
                              width:
                                  (cardContext.findRenderObject()! as RenderBox)
                                      .size
                                      .width,
                              child: TaskCard(
                                task: task,
                                store: s,
                                onEdit: () {},
                                preview: true,
                              ),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(opacity: .45, child: card),
                        child: card,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget taskList() {
    if (s.visible.isEmpty) return empty();
    return Glass(
      child: LayoutBuilder(
        builder: (context, box) {
          const minTableWidth = 656.0;
          if (box.maxWidth >= minTableWidth) return taskTable();
          return SingleChildScrollView(
            controller: taskTableScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: minTableWidth,
              height: box.maxHeight,
              child: taskTable(),
            ),
          );
        },
      ),
    );
  }

  Widget taskTable() {
    final p = Palette.of(context);
    return Column(
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 48),
          color: p.hover,
          padding: const EdgeInsets.fromLTRB(56, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '任务名称',
                  style: textStyle(p, size: 12, bold: true, color: p.secondary),
                ),
              ),
              for (final e in [
                ('分类', 72.0),
                ('状态', 96.0),
                ('优先级', 56.0),
                ('截止日期', 144.0),
                ('', 32.0),
              ]) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: e.$2,
                  child: Text(
                    e.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(
                      p,
                      size: 12,
                      bold: true,
                      color: p.secondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: ListView.builder(
            itemCount: s.visible.length,
            itemBuilder: (c, i) {
              final t = s.visible[i];
              final project = s.state.projectName(t.projectID);
              return Container(
                constraints: BoxConstraints(
                  minHeight: t.description.isEmpty && project == null ? 48 : 56,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: p.card.withValues(alpha: p.dark ? 0.297 : .324),
                  border: Border(bottom: BorderSide(color: p.border)),
                ),
                child: Row(
                  children: [
                    IconButtonS(
                      t.status == 'done' ? 'done' : 'circle',
                      t.status == 'done' ? '重新开启：${t.title}' : '完成：${t.title}',
                      iconSize: 20,
                      onPressed: () => s.moveTask(
                        t.id,
                        t.status == 'done' ? 'todo' : 'done',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SpaceButton(
                        height: null,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        onPressed: () =>
                            editTask(context, s, t, existing: true),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              t.title,
                              style: textStyle(p, bold: true),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (t.description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                t.description,
                                style: textStyle(
                                  p,
                                  size: 12,
                                  color: p.secondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (project != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                project,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textStyle(p, size: 12, color: p.purple),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 72,
                      child: CategoryLabel(
                        t.category,
                        name: s.state.taskCategories[t.category],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SpaceSelect(
                      width: 96,
                      value: t.status,
                      label: '任务状态',
                      options: {
                        for (final status in s.state.statuses)
                          if (!s.state.disabledStatuses.contains(status) ||
                              status == t.status)
                            status: statusName(status),
                      },
                      onChanged: (v) => s.moveTask(t.id, v),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 56,
                      child: Text(
                        priorities[t.priority]!,
                        style: textStyle(
                          p,
                          size: 12,
                          color: p.priority(t.priority),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(width: 144, child: dueLabel(context, t, s.today)),
                    const SizedBox(width: 16),
                    taskMenu(context, s, t, table: true),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget empty() {
    final p = Palette.of(context);
    return Glass(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpaceIcon(
              s.state.tasks.isEmpty ? 'tray' : 'search',
              size: 36,
              color: p.accent,
            ),
            const SizedBox(height: 16),
            Text(
              s.state.tasks.isEmpty ? '让第一个行动，进入轨道。' : '没有符合条件的任务',
              style: textStyle(p, size: 20, bold: true),
            ),
            const SizedBox(height: 16),
            Text(
              s.state.tasks.isEmpty
                  ? '从一项工作、一个想法，或一件生活小事开始。'
                  : '调整筛选条件，或点击顶部分类。',
              style: textStyle(p, color: p.secondary),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SpaceButton(
                  onPressed: newTask,
                  primary: true,
                  child: Text(s.state.tasks.isEmpty ? '创建第一个任务' : '新建任务'),
                ),
                const SizedBox(width: 12),
                SpaceButton(
                  onPressed: s.state.tasks.isEmpty
                      ? () => importBackup(context, s)
                      : s.resetQuery,
                  child: Text(s.state.tasks.isEmpty ? '导入已有备份' : '显示所有任务'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskDrag {
  final SpaceTask task;
  _TaskDrag(this.task);
}

class _StatusDrag {
  final String status;
  _StatusDrag(this.status);
}

Widget dueLabel(BuildContext c, SpaceTask t, String today) {
  final p = Palette.of(c);
  final due = parseDay(t.due);
  final label = due == null
      ? '未设置'
      : t.due == today
      ? '今天截止'
      : '${due.month}月${due.day}日';
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SpaceIcon(
        'calendar',
        size: 12,
        color: t.overdue(today) ? p.red : p.muted,
      ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          '${t.overdue(today) ? '已逾期 · ' : ''}$label',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle(
            p,
            size: 12,
            color: t.overdue(today)
                ? p.red
                : t.due == today
                ? p.blue
                : p.muted,
          ),
        ),
      ),
    ],
  );
}

Widget taskMenu(
  BuildContext context,
  SpaceStore s,
  SpaceTask t, {
  bool table = false,
}) => Builder(
  builder: (buttonContext) {
    return SizedBox(
      width: table ? 32 : 24,
      height: table ? 32 : 20,
      child: IconButtonS(
        'dots',
        '任务操作',
        size: table ? 32 : 20,
        onPressed: () async {
          final p = Palette.of(buttonContext);
          final action = await anchoredPopup<String>(
            buttonContext,
            PopupSurface(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SpaceButton(
                    onPressed: () => Navigator.pop(buttonContext, 'edit'),
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('编辑任务'),
                    ),
                  ),
                  for (final status in s.state.statuses)
                    if (!s.state.disabledStatuses.contains(status) ||
                        status == t.status)
                      SpaceButton(
                        onPressed: () => Navigator.pop(buttonContext, status),
                        selected: status == t.status,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '移至${statusName(status)}',
                            style: textStyle(
                              p,
                              size: 12,
                              color: status == t.status
                                  ? p.selectedButtonForeground(p.text)
                                  : p.text,
                            ),
                          ),
                        ),
                      ),
                  SpaceButton(
                    danger: true,
                    onPressed: () => Navigator.pop(buttonContext, 'delete'),
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('删除任务'),
                    ),
                  ),
                ],
              ),
            ),
            width: 220,
            height: (s.state.statuses.length + 2) * 40.0 + 16,
          );
          if (!buttonContext.mounted) return;
          if (action == 'edit') {
            editTask(buttonContext, s, t, existing: true);
          } else if (action == 'delete') {
            if (await confirm(
              buttonContext,
              '删除任务',
              '确定删除“${t.title}”？删除后可撤销。',
              '删除任务',
            )) {
              s.deleteTask(t.id);
            }
          } else if (action != null) {
            s.moveTask(t.id, action);
          }
        },
      ),
    );
  },
);

class TaskCard extends StatefulWidget {
  final SpaceTask task;
  final SpaceStore store;
  final VoidCallback onEdit;
  final bool preview;
  const TaskCard({
    super.key,
    required this.task,
    required this.store,
    required this.onEdit,
    this.preview = false,
  });
  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> with WidgetsBindingObserver {
  bool hovered = false, active = true;
  Timer? timer;
  final phase = ValueNotifier(0.0);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    dragActive.addListener(updateClock);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    updateClock();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    updateClock();
  }

  void updateClock() {
    final enabled =
        active &&
        TickerMode.valuesOf(context).enabled &&
        !widget.preview &&
        !WorkspaceMotion.activeOf(context) &&
        !dragActive.value &&
        !MediaQuery.of(context).disableAnimations;
    if (enabled && timer == null) {
      timer = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => phase.value += .05,
      );
    } else if (!enabled) {
      timer?.cancel();
      timer = null;
      // Keep the current glow when animation is paused.
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    phase.dispose();
    dragActive.removeListener(updateClock);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c), t = widget.task, s = widget.store;
    final project = s.state.projectName(t.projectID);
    final scale = MediaQuery.textScalerOf(c).scale(14) / 14;
    final content = SizedBox(
      height: 184 + math.max(0, scale - 1) * 96,
      child: Glass(
        card: true,
        blur: false,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 20 * scale,
              child: Row(
                children: [
                  if (project != null) ...[
                    SpaceIcon('folder', size: 12, color: p.purple),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      project ?? '',
                      style: textStyle(p, size: 12, color: p.purple),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  taskMenu(c, s, t),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Semantics(
                button: true,
                label: '编辑任务：${t.title}',
                child: GestureDetector(
                  onTap: widget.onEdit,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          style: textStyle(p, bold: true),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.description
                              .replaceAll(RegExp(r'\s+'), ' ')
                              .replaceAll('\uFFFC', '图片'),
                          style: textStyle(p, size: 12, color: p.secondary),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (c, box) {
                final narrow = box.maxWidth < 240;
                final category = ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(120, box.maxWidth * .35),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: p.category(t.category).withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CategoryLabel(
                      t.category,
                      name: widget.store.state.taskCategories[t.category],
                    ),
                  ),
                );
                final priority = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SpaceIcon('flag', size: 12, color: p.priority(t.priority)),
                    const SizedBox(width: 4),
                    Text(
                      priorities[t.priority]!,
                      style: textStyle(
                        p,
                        size: 12,
                        color: p.priority(t.priority),
                      ),
                    ),
                  ],
                );
                final complete = IconButtonS(
                  t.status == 'done' ? 'done' : 'circle',
                  t.status == 'done' ? '重新开启：${t.title}' : '完成：${t.title}',
                  size: 28,
                  iconSize: 22,
                  onPressed: () =>
                      s.moveTask(t.id, t.status == 'done' ? 'todo' : 'done'),
                );
                return SizedBox(
                  height: 52,
                  child: narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                category,
                                const SizedBox(width: 8),
                                priority,
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(child: dueLabel(c, t, s.today)),
                                complete,
                              ],
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            category,
                            const SizedBox(width: 8),
                            priority,
                            const SizedBox(width: 8),
                            Expanded(child: dueLabel(c, t, s.today)),
                            const SizedBox(width: 4),
                            complete,
                          ],
                        ),
                );
              },
            ),
          ],
        ),
      ),
    );
    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) {
          setState(() => hovered = true);
          updateClock();
        },
        onExit: (_) {
          setState(() => hovered = false);
          updateClock();
        },
        child: ValueListenableBuilder(
          valueListenable: phase,
          child: RepaintBoundary(child: content),
          builder: (c, time, child) => CardFlow(
            emphasized: hovered || t.status == 'doing',
            time: time,
            child: child!,
          ),
        ),
      ),
    );
  }
}
