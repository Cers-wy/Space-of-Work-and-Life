import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';

import '../core/invoices.dart';
import '../core/repository.dart';
import '../host.dart';
import '../store.dart';
import 'controls.dart';
import 'dialogs.dart' show field, showProjects;
import 'invoice_details.dart';
import 'invoice_merge.dart';
import 'theme.dart';

class InvoiceSession extends ChangeNotifier {
  final InvoiceRepository repo;
  InvoiceSession(SpaceRepository space) : repo = InvoiceRepository(space);

  InvoiceLedger? ledger;
  final selected = <String>{};
  String query = '', month = '', project = '', status = '';
  bool get hasFilters =>
      query.trim().isNotEmpty ||
      month.isNotEmpty ||
      project.isNotEmpty ||
      status.isNotEmpty;
  bool busy = false, _disposed = false;
  String? error, notice;

  Map<String, String> get projects => ledger?.projects ?? const {};

  List<InvoiceEntry> get filtered {
    final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
    return [
      for (final entry in ledger?.entries ?? const <InvoiceEntry>[])
        if (matches(entry, terms)) entry,
    ];
  }

  bool matches(InvoiceEntry e, List<String> terms) {
    final i = e.info;
    if (month.isNotEmpty && i.month != month ||
        project.isNotEmpty && i.project != project ||
        status.isNotEmpty && i.reimbursed != (status == 'yes')) {
      return false;
    }
    if (terms.length == 1 && terms.single.isEmpty) return true;
    final content = [
      e.original.name,
      i.number,
      i.seller,
      i.spent,
      i.issued,
      i.purpose,
      i.month,
      i.amount,
      projects[i.project],
      ...e.attachments.map((f) => f.name),
    ].join(' ').toLowerCase();
    return terms.every(content.contains);
  }

  void update(VoidCallback change) {
    change();
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    ledger = await repo.load();
    if (!projects.containsKey(project)) project = '';
    selected.retainAll(ledger!.entries.map((e) => e.id).toSet());
  }

  Future<void> run(
    Future<String?> Function() task, {
    bool reload = true,
  }) async {
    if (busy || _disposed) return;
    update(() {
      busy = true;
      error = notice = null;
    });
    try {
      final message = await task();
      if (reload) await refresh();
      notice = message;
    } catch (e) {
      error = invoiceError(e);
    } finally {
      update(() => busy = false);
    }
  }

  Future<void> load() => run(() async => null);

  Future<void> import(List<String> paths) async {
    if (paths.isEmpty) return;
    await run(() async {
      final result = await repo.importFiles(paths);
      if (result.errors.isNotEmpty) error = result.errors.join('\n');
      return '已导入 ${result.count} 张发票';
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class InvoiceWorkspace extends StatelessWidget {
  final SpaceStore store;
  final InvoiceSession session;
  final bool showTools;
  final GlobalKey filterAnchor;
  const InvoiceWorkspace({
    super.key,
    required this.store,
    required this.session,
    required this.showTools,
    required this.filterAnchor,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Glass(
      child: !showTools && store.loaded
          ? _Ledger(store: store, session: session, filterAnchor: filterAnchor)
          : Column(
              children: [
                _InvoiceTitleBar(store: store, showTools: showTools),
                Expanded(
                  child: showTools
                      ? _Tools(store: store, session: session)
                      : Center(
                          child: Text('请先载入 Space 数据库', style: textStyle(p)),
                        ),
                ),
              ],
            ),
    );
  }
}

class _InvoiceTitleBar extends StatelessWidget {
  final SpaceStore store;
  final bool showTools;
  final List<Widget> actions;

  const _InvoiceTitleBar({
    required this.store,
    this.showTools = false,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      children: [
        SpaceTitleBar(
          key: ValueKey(showTools ? 'tools-titlebar' : 'invoices-titlebar'),
          children: [
            IconButtonS.toolbar(
              store.navCollapsed ? 'sidebar-open' : 'sidebar-close',
              store.navCollapsed ? '展开导航' : '收起导航',
              iconSize: 18,
              onPressed: () =>
                  store.preference('navCollapsed', '${!store.navCollapsed}'),
            ),
            const SizedBox(width: 8),
            SpaceIcon(
              showTools ? 'tools' : 'invoice',
              size: 16,
              color: p.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                showTools ? '工具' : '发票管理',
                style: textStyle(p, bold: true),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...actions,
            ThemeToggle(dark: store.dark, onToggle: store.toggleTheme),
          ],
        ),
        Divider(height: 1, color: p.border),
      ],
    );
  }
}

Future<void> showInvoiceFilters(
  BuildContext anchor,
  SpaceStore store,
  InvoiceSession session,
) => invoiceModal(
  store,
  () => anchoredPopup<void>(
    anchor,
    _InvoiceFilters(session: session),
    width: 384,
    height: 416,
    barrierColor: store.dark
        ? Colors.transparent
        : Colors.black.withValues(alpha: .18),
  ),
);

class _InvoiceFilters extends StatefulWidget {
  final InvoiceSession session;
  const _InvoiceFilters({required this.session});

  @override
  State<_InvoiceFilters> createState() => _InvoiceFiltersState();
}

class _InvoiceFiltersState extends State<_InvoiceFilters> {
  InvoiceSession get session => widget.session;
  late final search = TextEditingController(text: session.query);

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final p = Palette.of(context);
      final months =
          (session.ledger?.entries ?? const <InvoiceEntry>[])
              .map((entry) => entry.info.month)
              .where((month) => month.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => b.compareTo(a));
      return Glass(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('筛选发票', style: textStyle(p, size: 16, bold: true)),
            const SizedBox(height: 16),
            field(
              context,
              '关键词',
              SpaceInput(
                controller: search,
                icon: 'search',
                autofocus: true,
                hint: '搜索票号、销方、用途或文件名',
                label: '搜索发票',
                onChanged: (value) =>
                    session.update(() => session.query = value),
              ),
            ),
            const SizedBox(height: 16),
            field(
              context,
              '报销月份',
              SpaceSelect(
                value: session.month,
                label: '报销月份',
                options: {'': '全部月份', for (final month in months) month: month},
                onChanged: (value) =>
                    session.update(() => session.month = value),
              ),
            ),
            const SizedBox(height: 16),
            field(
              context,
              '报销项目',
              SpaceSelect(
                value: session.project,
                label: '筛选报销项目',
                options: {'': '全部项目', ...session.projects},
                onChanged: (value) =>
                    session.update(() => session.project = value),
              ),
            ),
            const SizedBox(height: 16),
            field(
              context,
              '报销状态',
              SpaceSelect(
                value: session.status,
                label: '报销状态',
                options: const {'': '全部状态', 'yes': '已报销', 'no': '未报销'},
                onChanged: (value) =>
                    session.update(() => session.status = value),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${session.filtered.length} 张匹配发票',
                    style: textStyle(p, size: 12, color: p.muted),
                  ),
                ),
                IconButtonS(
                  'x',
                  '清除筛选',
                  onPressed: !session.hasFilters
                      ? null
                      : () {
                          search.clear();
                          session.update(() {
                            session.query = session.month = session.project =
                                session.status = '';
                          });
                        },
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

void _showInvoiceHelp(BuildContext anchor, SpaceStore store) {
  invoiceModal(
    store,
    () => anchoredPopup<void>(
      anchor,
      Builder(
        builder: (context) {
          final p = Palette.of(context);
          return Glass(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('发票管理帮助', style: textStyle(p, size: 16, bold: true)),
                const SizedBox(height: 12),
                Text(
                  '将 PDF、JPG 或 PNG 拖入页面，或使用顶栏的导入图标选择文件。',
                  style: textStyle(p, size: 13, color: p.secondary),
                ),
                const SizedBox(height: 8),
                Text(
                  '点击发票名称可查看详情。勾选发票后可合并打印。',
                  style: textStyle(p, size: 13, color: p.secondary),
                ),
              ],
            ),
          );
        },
      ),
      width: 320,
      height: 168,
    ),
  );
}

class _Tools extends StatelessWidget {
  final SpaceStore store;
  final InvoiceSession session;
  const _Tools({required this.store, required this.session});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('工具', style: textStyle(p, size: 27, bold: true)),
        const SizedBox(height: 6),
        Text('集中处理工作中的常用文件', style: textStyle(p, color: p.muted)),
        const SizedBox(height: 20),
        SizedBox(
          height: 312,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 7,
                child: Glass(
                  card: true,
                  blur: false,
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SpaceIcon('invoice', size: 25, color: p.accent),
                            const SizedBox(height: 14),
                            Text(
                              '发票处理',
                              style: textStyle(p, size: 12, color: p.muted),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '发票合并',
                              style: textStyle(p, size: 22, bold: true),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '自动裁去票面留白，将多张电子发票排到同一张 A4 纸上。',
                              style: textStyle(p, color: p.secondary),
                            ),
                            const Spacer(),
                            IconButtonS(
                              'right',
                              '打开发票合并',
                              primary: true,
                              onPressed: () => openInvoiceMerge(
                                context,
                                store,
                                session.repo,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: _PaperIllustration()),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _FutureTool('文档处理', 'list')),
                    const SizedBox(height: 12),
                    Expanded(child: _FutureTool('图片处理', 'file')),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final row in [
          [('文件管理', 'folder'), ('数据处理', 'grid')],
          [('文本处理', 'list'), ('其他工具', 'tools')],
        ]) ...[
          Row(
            children: [
              for (var i = 0; i < row.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: _FutureTool(row[i].$1, row[i].$2)),
              ],
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _PaperIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ExcludeSemantics(
      child: Center(
        child: FittedBox(
          child: Container(
            width: 136,
            height: 192,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: p.popup,
              border: Border.all(color: p.popupBorder),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: [
                for (var i = 0; i < 2; i++) ...[
                  if (i != 0) Divider(color: p.popupBorder, height: 18),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: p.hover,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SpaceIcon('invoice', size: 17, color: p.accent),
                            const Spacer(),
                            for (final w in [72.0, 53.0, 65.0])
                              Container(
                                width: w,
                                height: 2,
                                color: p.accent.withValues(alpha: .26),
                                margin: const EdgeInsets.only(bottom: 5),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InvoiceHint extends StatelessWidget {
  final String icon, title;
  final String? detail;
  final bool compact;
  const InvoiceHint(
    this.icon,
    this.title, {
    super.key,
    this.detail,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpaceIcon(icon, size: compact ? 24 : 36, color: p.accent),
            SizedBox(height: compact ? 8 : 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textStyle(p, size: compact ? 14 : 20, bold: true),
            ),
            if (detail != null) ...[
              const SizedBox(height: 12),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: textStyle(p, color: p.secondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FutureTool extends StatelessWidget {
  final String title, icon;
  const _FutureTool(this.title, this.icon);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Glass(
      card: true,
      blur: false,
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SpaceIcon(icon, size: 22, color: p.muted),
          const SizedBox(height: 8),
          Text(title, style: textStyle(p, bold: true)),
          const SizedBox(height: 4),
          Text(
            '更多功能，敬请期待',
            textAlign: TextAlign.center,
            style: textStyle(p, size: 12, color: p.muted),
          ),
        ],
      ),
    );
  }
}

class _Ledger extends StatefulWidget {
  final SpaceStore store;
  final InvoiceSession session;
  final GlobalKey filterAnchor;
  const _Ledger({
    required this.store,
    required this.session,
    required this.filterAnchor,
  });
  @override
  State<_Ledger> createState() => _LedgerState();
}

class _LedgerState extends State<_Ledger> {
  final horizontal = ScrollController();
  final vertical = ScrollController();
  bool dragging = false, choosing = false;
  InvoiceSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shared = {
        for (final p in widget.store.state.projects) p.id: p.name,
      };
      if (session.ledger == null || !mapEquals(shared, session.projects)) {
        session.load();
      }
    });
  }

  @override
  void dispose() {
    horizontal.dispose();
    vertical.dispose();
    super.dispose();
  }

  bool get canImport =>
      !session.busy &&
      !choosing &&
      !widget.store.modal &&
      widget.store.area == SpaceArea.invoices;

  Future<void> choose() async {
    if (!canImport) return;
    setState(() => choosing = true);
    try {
      await session.import(
        await DesktopHost.openFiles(
          title: '导入发票',
          extensions: invoiceFileExtensions.toList(),
        ),
      );
    } catch (e) {
      session.update(() => session.error = invoiceError(e));
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final p = Palette.of(context);
      final items = session.filtered;
      final selected = items
          .where((e) => session.selected.contains(e.id))
          .toList();
      return DropTarget(
        onDragEntered: (_) {
          if (canImport) setState(() => dragging = true);
        },
        onDragExited: (_) {
          if (dragging) setState(() => dragging = false);
        },
        onDragDone: (detail) {
          if (dragging) setState(() => dragging = false);
          if (canImport) {
            unawaited(session.import(detail.files.map((f) => f.path).toList()));
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                _InvoiceTitleBar(
                  store: widget.store,
                  actions: [
                    IconButtonS.toolbar(
                      'filter',
                      '筛选发票（⌘F）',
                      key: widget.filterAnchor,
                      selected: session.hasFilters,
                      onPressed: () => showInvoiceFilters(
                        widget.filterAnchor.currentContext!,
                        widget.store,
                        session,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButtonS.toolbar(
                      'project',
                      '管理共用项目',
                      onPressed: session.busy
                          ? null
                          : () async {
                              await showProjects(context, widget.store);
                              await session.load();
                            },
                    ),
                    const SizedBox(width: 8),
                    IconButtonS.toolbar(
                      'save',
                      '按字段导出',
                      onPressed: items.isEmpty || session.busy
                          ? null
                          : () => showInvoiceExport(
                              context,
                              widget.store,
                              session,
                              items,
                              selected,
                            ),
                    ),
                    const SizedBox(width: 8),
                    IconButtonS.toolbar(
                      'upload',
                      '导入发票',
                      primary: true,
                      onPressed: canImport ? choose : null,
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (anchor) => IconButtonS.toolbar(
                        'help',
                        '发票管理帮助',
                        onPressed: () => _showInvoiceHelp(anchor, widget.store),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 2,
                          child: session.busy
                              ? const LinearProgressIndicator()
                              : null,
                        ),
                        if (session.error case final error?)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Tooltip(
                                    message: error,
                                    child: Text(
                                      error,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: textStyle(p, color: p.red),
                                    ),
                                  ),
                                ),
                                if (session.ledger == null && !session.busy)
                                  IconButtonS(
                                    'refresh',
                                    '重新读取台账',
                                    onPressed: session.load,
                                  ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: items.isEmpty
                              ? _emptyLedger()
                              : _table(items, selected.length),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${items.length} 张发票 · 已选 ${selected.length} 张'
                                '${session.notice == null ? '' : ' · ${session.notice}'}',
                                style: textStyle(p, size: 12, color: p.muted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButtonS(
                              'printer',
                              '合并打印',
                              primary: true,
                              onPressed: selected.isEmpty || session.busy
                                  ? null
                                  : () => openInvoiceMerge(
                                      context,
                                      widget.store,
                                      session.repo,
                                      entries: selected,
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            IgnorePointer(
              child: ExcludeSemantics(
                excluding: !dragging,
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 140),
                  switchInCurve: spaceCurve,
                  switchOutCurve: spaceCurve,
                  child: dragging
                      ? Container(
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: p.accent, width: 2),
                            borderRadius: BorderRadius.circular(8),
                            color: p.popup.withValues(alpha: .94),
                          ),
                          child: const InvoiceHint('upload', '松开以导入发票'),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _emptyLedger() {
    if (session.busy) return const InvoiceHint('invoice', '正在处理发票…');
    final ledger = session.ledger;
    if (ledger == null) {
      return const InvoiceHint('invoice', '台账尚未载入');
    }
    if (ledger.entries.isEmpty) {
      return const InvoiceHint(
        'tray',
        '拖入发票，开始建立台账',
        detail: '支持 PDF、JPG 和 PNG，也可以使用顶栏的导入图标。',
      );
    }
    return const InvoiceHint('search', '没有符合条件的发票', detail: '可在顶栏调整筛选条件。');
  }

  Widget _table(List<InvoiceEntry> items, int selectedCount) {
    final p = Palette.of(context);
    final all = selectedCount == items.length;
    final rowColor = p.card.withValues(alpha: p.dark ? .297 : .324);
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140);
    return Glass(
      child: LayoutBuilder(
        builder: (context, box) => Scrollbar(
          controller: horizontal,
          thumbVisibility: box.maxWidth < 860,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(box.maxWidth, 860),
              height: box.maxHeight,
              child: Column(
                children: [
                  Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    color: p.hover,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        SpaceCheckbox(
                          label: '全选当前结果',
                          value: selectedCount > 0 && !all ? null : all,
                          showLabel: false,
                          onPressed: session.busy
                              ? null
                              : () => session.update(() {
                                  final ids = items.map((e) => e.id);
                                  if (all) {
                                    session.selected.removeAll(ids);
                                  } else {
                                    session.selected.addAll(ids);
                                  }
                                }),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _columns([
                            _textCell('发票 / 票号', header: true),
                            _textCell('消费时间', header: true),
                            _textCell('用途', header: true),
                            _textCell(
                              '金额',
                              header: true,
                              align: TextAlign.right,
                            ),
                            _textCell('报销月份', header: true),
                            _textCell('报销项目', header: true),
                            _textCell('状态', header: true),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: p.border),
                  Expanded(
                    child: ListView.builder(
                      controller: vertical,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final entry = items[index], info = entry.info;
                        final checked = session.selected.contains(entry.id);
                        return AnimatedContainer(
                          key: ValueKey(entry.id),
                          duration: motion,
                          curve: spaceCurve,
                          constraints: const BoxConstraints(minHeight: 56),
                          decoration: BoxDecoration(
                            color: checked
                                ? Color.alphaBlend(p.hover, rowColor)
                                : rowColor,
                            border: Border(bottom: BorderSide(color: p.border)),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              SpaceCheckbox(
                                label: '选择 ${entry.original.name}',
                                value: checked,
                                showLabel: false,
                                onPressed: session.busy
                                    ? null
                                    : () => session.update(() {
                                        if (checked) {
                                          session.selected.remove(entry.id);
                                        } else {
                                          session.selected.add(entry.id);
                                        }
                                      }),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: SpaceButton(
                                  tooltip: '查看发票详情',
                                  height: null,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  onPressed: session.busy
                                      ? null
                                      : () => showInvoiceDetails(
                                          context,
                                          widget.store,
                                          session,
                                          entry.id,
                                        ),
                                  child: _columns([
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.original.name,
                                          maxLines: info.number.isEmpty ? 2 : 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: textStyle(p, bold: true),
                                        ),
                                        if (info.number.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          _textCell(info.number),
                                        ],
                                      ],
                                    ),
                                    _textCell(info.spent),
                                    _textCell(info.purpose),
                                    _textCell(
                                      info.amount,
                                      align: TextAlign.right,
                                    ),
                                    _textCell(info.month),
                                    _textCell(
                                      session.projects[info.project] ?? '',
                                      color: p.purple,
                                    ),
                                    _textCell(
                                      info.reimbursed ? '已报销' : '未报销',
                                      color: info.reimbursed
                                          ? p.green
                                          : p.secondary,
                                    ),
                                  ]),
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
          ),
        ),
      ),
    );
  }

  Widget _columns(List<Widget> cells) {
    const widths = [3, 1, 2, 1, 1, 1, 1];
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(flex: widths[i], child: cells[i]),
        ],
      ],
    );
  }

  Widget _textCell(
    String value, {
    bool header = false,
    Color? color,
    TextAlign? align,
  }) {
    final p = Palette.of(context);
    return Text(
      value.isEmpty ? '—' : value,
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textStyle(
        p,
        size: 12,
        bold: header,
        color: value.isEmpty ? p.muted : color ?? p.secondary,
      ),
    );
  }
}
