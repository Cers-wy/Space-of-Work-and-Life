import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show mapEquals, setEquals;
import 'package:flutter/material.dart';

import '../core/invoices.dart';
import '../core/drive.dart';
import '../core/invoice_recognition.dart';
import '../core/repository.dart';
import '../host.dart';
import '../store.dart';
import 'controls.dart';
import 'dialogs.dart' show confirm, field, showProjects, showSettings;
import 'invoice_details.dart';
import 'invoice_batch_update.dart';
import 'invoice_merge.dart';
import 'file_drive.dart';
import 'theme.dart';

class InvoiceRecognitionSaveError implements Exception {
  final InvoiceRecognition result;
  final String reason;
  const InvoiceRecognitionSaveError(this.result, this.reason);
  @override
  String toString() => '识别完成，保存失败，请重试：$reason';
}

class _RecognitionCancelled implements Exception {
  const _RecognitionCancelled();
  @override
  String toString() => '发票已删除，已跳过识别';
}

class InvoiceSession extends ChangeNotifier {
  final InvoiceRepository repo;
  InvoiceSession(SpaceRepository space) : repo = InvoiceRepository(space);

  /// 由工作台注入，保证自动识别实时读取设置中的「优先使用 OCR」开关。
  bool Function()? preferOcr;

  InvoiceLedger? ledger;
  final selected = <String>{};
  final recognitionFailures = <String, String>{};
  String query = '', month = '', project = '', status = '';
  bool get hasFilters =>
      query.trim().isNotEmpty ||
      month.isNotEmpty ||
      project.isNotEmpty ||
      status.isNotEmpty;
  bool busy = false, _disposed = false;
  String? error, notice;
  bool batchRecognizing = false;
  int batchProcessed = 0, batchTotal = 0, _refreshGeneration = 0;
  String? batchNotice, batchError;
  final _batchIds = <String>{}, _cancelledRecognition = <String>{};
  final _manualJobs = <String, Future<InvoiceRecognition>>{};
  String? _currentRecognition;

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
      i.title,
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
    final generation = ++_refreshGeneration;
    final loaded = await repo.load();
    if (_disposed || generation != _refreshGeneration) return;
    ledger = loaded;
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
      if (!_disposed && _recognitionQueue.isNotEmpty) {
        unawaited(_recognizePending());
      }
    }
  }

  bool recognizing = false;
  final _recognitionQueue = <String>{};
  Future<void> _recognitionTail = Future.value();
  Future<InvoiceRecognition> Function(InvoiceFile, {required bool preferOcr})
  recognizeFile = InvoiceRecognizer.recognize;

  /// 所有识别入口共用串行队列，防止 OCR 并发和自动识别覆盖主动识别。
  Future<InvoiceRecognition> recognizeEntry(
    String id, {
    bool automatic = false,
  }) {
    if (!automatic) {
      _recognitionQueue.remove(id);
      final existing = _manualJobs[id];
      if (existing != null) return existing;
    }
    final work = _recognitionTail.then((_) async {
      if (_disposed) throw StateError('发票会话已关闭');
      if (_cancelledRecognition.contains(id)) {
        throw const _RecognitionCancelled();
      }
      _currentRecognition = id;
      try {
        final current = (await repo.load()).entries
            .where((e) => e.id == id)
            .firstOrNull;
        if (current == null) throw const _RecognitionCancelled();
        final result = await recognizeFile(
          current.original,
          preferOcr: preferOcr?.call() ?? false,
        );
        if (_disposed) throw StateError('发票会话已关闭');
        if (_cancelledRecognition.contains(id)) {
          throw const _RecognitionCancelled();
        }
        try {
          await repo.applyRecognition(
            id,
            result.fields,
            result.message,
            structured: result.structured,
            replaceExisting: !automatic,
            expectedFields: automatic ? null : current.info.ticketFields,
          );
        } catch (e) {
          if (_cancelledRecognition.contains(id)) {
            throw const _RecognitionCancelled();
          }
          throw InvoiceRecognitionSaveError(result, invoiceError(e));
        }
        if (result.fields.isNotEmpty) recognitionFailures.remove(id);
        return result;
      } finally {
        _currentRecognition = null;
      }
    });
    _recognitionTail = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    if (!automatic) {
      _manualJobs[id] = work;
      void cleanup() {
        if (!_batchIds.contains(id) && identical(_manualJobs[id], work)) {
          _manualJobs.remove(id);
          _cancelledRecognition.remove(id);
        }
      }

      unawaited(
        work.then<void>(
          (_) => cleanup(),
          onError: (Object _, StackTrace _) => cleanup(),
        ),
      );
    }
    return work;
  }

  /// 后台批次有独立进度，绝不占用前台 busy；筛选、勾选、编辑、导入及切页继续可用。
  Future<void> recognizeSelected(List<String> ids) async {
    if (batchRecognizing || _disposed || ids.isEmpty) return;
    final batch = ids.toSet().toList();
    final selectionAtStart = Set<String>.of(selected);
    _batchIds.addAll(batch);
    _recognitionQueue.removeAll(batch);
    update(() {
      batchRecognizing = true;
      batchProcessed = 0;
      batchTotal = batch.length;
      batchNotice = '后台识别 0 / $batchTotal 张';
      batchError = null;
    });
    var saved = 0, skipped = 0;
    final retryIDs = <String>{};
    try {
      for (final id in batch) {
        if (_disposed) return;
        recognitionFailures.remove(id);
        try {
          final result = await recognizeEntry(id);
          if (result.fields.isEmpty) {
            retryIDs.add(id);
            recognitionFailures[id] = '未识别到可用字段';
          } else {
            saved++;
          }
        } on _RecognitionCancelled {
          skipped++;
        } catch (e) {
          if (_disposed) return;
          retryIDs.add(id);
          recognitionFailures[id] = invoiceError(e);
        }
        if (_disposed) return;
        await refresh();
        update(() => batchNotice = '后台识别 ${++batchProcessed} / $batchTotal 张');
      }
      retryIDs.retainAll(ledger?.entries.map((e) => e.id) ?? const <String>[]);
      if (retryIDs.isNotEmpty) {
        batchError =
            '有 ${retryIDs.length} 张未完成：${retryIDs.map((id) => recognitionFailures[id]).toSet().join('；')}';
      }
      // 用户若在处理过程中调整了勾选，保持其当前选择。
      if (setEquals(selected, selectionAtStart)) {
        selected.removeAll(batch);
        selected.addAll(retryIDs);
      }
      batchNotice =
          '识别完成：$saved 张已保存，${retryIDs.length} 张未完成${skipped > 0 ? '，$skipped 张已跳过' : ''}';
    } finally {
      for (final id in batch) {
        _manualJobs.remove(id);
        _cancelledRecognition.remove(id);
      }
      _batchIds.removeAll(batch);
      update(() => batchRecognizing = false);
    }
  }

  Future<void> deleteEntry(String id) async {
    _recognitionQueue.remove(id);
    if (_batchIds.contains(id) ||
        _manualJobs.containsKey(id) ||
        _currentRecognition == id) {
      _cancelledRecognition.add(id);
    }
    try {
      await repo.delete(id);
      selected.remove(id);
      recognitionFailures.remove(id);
    } catch (_) {
      _cancelledRecognition.remove(id);
      rethrow;
    }
  }

  Future<void> deleteSelected(List<String> ids) => run(() async {
    var deleted = 0;
    final failures = <String>[];
    for (final id in ids) {
      try {
        await deleteEntry(id);
        deleted++;
      } catch (e) {
        failures.add(invoiceError(e));
      }
    }
    if (failures.isNotEmpty) {
      error = '${failures.length} 张删除失败：${failures.toSet().join('；')}';
    }
    return '已删除 $deleted 张发票';
  });

  Future<bool> updateReimbursement(
    List<String> ids,
    InvoiceReimbursementPatch patch,
  ) async {
    if (ids.isEmpty || patch.values.isEmpty) return false;
    var saved = false;
    await run(() async {
      final count = await repo.updateReimbursement(ids, patch);
      saved = true;
      return count > 0 ? '已更新 $count 张发票' : '所选发票已被移除，未更新';
    });
    return saved;
  }

  Future<void> load() async {
    await run(() async => null);
    for (final entry in ledger?.entries ?? <InvoiceEntry>[]) {
      if (entry.info.recognition.isEmpty) _recognitionQueue.add(entry.id);
    }
    unawaited(_recognizePending());
  }

  Future<void> _recognizePending() async {
    if (recognizing || _disposed) return;
    recognizing = true;
    try {
      while (_recognitionQueue.isNotEmpty && !_disposed && !busy) {
        final id = _recognitionQueue.first;
        _recognitionQueue.remove(id);
        final entry = ledger?.entries.where((e) => e.id == id).firstOrNull;
        if (entry == null ||
            _batchIds.contains(id) ||
            _manualJobs.containsKey(id)) {
          continue;
        }
        try {
          await recognizeEntry(id, automatic: true);
        } on _RecognitionCancelled {
          continue;
        } catch (e) {
          // 会话已释放时不再触碰数据库，避免退出后回写识别错误状态。
          if (_disposed) return;
          await repo.recognitionError(id, invoiceError(e));
        }
        if (!_disposed) {
          await refresh();
          update(() {});
        }
      }
    } finally {
      recognizing = false;
      if (!_disposed) update(() {});
    }
  }

  Future<void> import(List<String> paths) async {
    if (paths.isEmpty) return;
    await run(() async {
      final result = await repo.importFiles(paths);
      if (result.errors.isNotEmpty) error = result.errors.join('\n');
      return '已导入 ${result.count} 张发票，正在自动识别';
    });
    for (final entry in ledger?.entries ?? <InvoiceEntry>[]) {
      if (entry.info.recognition.isEmpty) _recognitionQueue.add(entry.id);
    }
    unawaited(_recognizePending());
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
      child: showTools
          ? _ToolsWorkspace(store: store, session: session)
          : store.loaded
          ? _Ledger(store: store, session: session, filterAnchor: filterAnchor)
          : Column(
              children: [
                _InvoiceTitleBar(store: store),
                Expanded(
                  child: Center(
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
  final VoidCallback? backToTools;
  final List<Widget> actions;
  final String subTitle;

  const _InvoiceTitleBar({
    required this.store,
    this.showTools = false,
    this.backToTools,
    this.actions = const [],
    this.subTitle = '发票合并',
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final title = Text(
      backToTools != null
          ? subTitle
          : showTools
          ? '工具'
          : '发票',
      style: textStyle(p, bold: true),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, box) => SpaceTitleBar(
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
              if (backToTools != null) ...[
                SpaceButton(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: backToTools,
                  child: const Text('工具'),
                ),
                SpaceIcon('right', size: 12, color: p.muted),
                const SizedBox(width: 8),
              ],
              if (box.maxWidth >= 540 || actions.isEmpty)
                Expanded(child: title)
              else
                SizedBox(width: 64, child: title),
              if (box.maxWidth < 540 && actions.isNotEmpty)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                  ),
                )
              else
                ...actions,
              ThemeToggle(dark: store.dark, onToggle: store.toggleTheme),
            ],
          ),
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
    barrierColor: Colors.transparent,
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
                hint: '搜索发票名称、销售方、票号或备注',
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
                Text('发票帮助', style: textStyle(p, size: 16, bold: true)),
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

class _ToolsWorkspace extends StatefulWidget {
  final SpaceStore store;
  final InvoiceSession session;
  const _ToolsWorkspace({required this.store, required this.session});

  @override
  State<_ToolsWorkspace> createState() => _ToolsWorkspaceState();
}

class _ToolsWorkspaceState extends State<_ToolsWorkspace> {
  int page = 0;
  DriveService get drive => driveFor(widget.store);

  @override
  Widget build(BuildContext context) {
    if (page >= 2) {
      return DrivePage(
        store: widget.store,
        service: drive,
        initialUploads: page == 2,
        titleBuilder: (actions) => _InvoiceTitleBar(
          store: widget.store,
          showTools: true,
          backToTools: () => setState(() => page = 0),
          subTitle: '文件管理',
          actions: actions,
        ),
      );
    }
    return Column(
      children: [
        _InvoiceTitleBar(
          store: widget.store,
          showTools: true,
          backToTools: page == 1 ? () => setState(() => page = 0) : null,
          subTitle: '发票合并',
        ),
        Expanded(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(page),
            tween: Tween(begin: 0, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: spaceCurve,
            builder: (context, opacity, child) =>
                Opacity(opacity: opacity, child: child),
            child: page == 1
                ? InvoiceMergeEditor(repo: widget.session.repo)
                : _Tools(
                    store: widget.store,
                    onOpenMerge: () => setState(() => page = 1),
                    drive: drive,
                    onUploads: () => setState(() => page = 2),
                    onFiles: () => setState(() => page = 3),
                  ),
          ),
        ),
      ],
    );
  }
}

class _Tools extends StatelessWidget {
  final SpaceStore store;
  final VoidCallback onOpenMerge;
  final DriveService drive;
  final VoidCallback onUploads, onFiles;
  const _Tools({
    required this.store,
    required this.onOpenMerge,
    required this.drive,
    required this.onUploads,
    required this.onFiles,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
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
                              onPressed: onOpenMerge,
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
        SizedBox(
          height: 208,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: DriveToolCard(
                  service: drive,
                  uploads: onUploads,
                  files: onFiles,
                  onUpload: () => chooseDriveFiles(
                    context,
                    drive,
                    () =>
                        showSettings(context, store, initialCategory: 'drive'),
                  ),
                  onDrop: (paths) => addDriveFiles(
                    context,
                    drive,
                    paths,
                    () =>
                        showSettings(context, store, initialCategory: 'drive'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: _FutureTool('数据处理', 'grid')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final row in [
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
                      'scan',
                      '识别所选发票',
                      onPressed:
                          selected.isEmpty ||
                              session.busy ||
                              session.batchRecognizing
                          ? null
                          : () => unawaited(
                              session.recognizeSelected(
                                selected.map((e) => e.id).toList(),
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    IconButtonS.toolbar(
                      'edit',
                      '批量更新发票',
                      onPressed: selected.isEmpty || session.busy
                          ? null
                          : () => showInvoiceBatchUpdate(
                              context,
                              widget.store,
                              session,
                              selected.map((e) => e.id).toList(),
                            ),
                    ),
                    const SizedBox(width: 8),
                    IconButtonS.toolbar(
                      'trash',
                      '批量删除发票',
                      danger: true,
                      onPressed: selected.isEmpty || session.busy
                          ? null
                          : () async {
                              final ids = selected.map((e) => e.id).toList();
                              final approved = await invoiceModal(
                                widget.store,
                                () => confirm(
                                  context,
                                  '删除选中的 ${ids.length} 张发票？',
                                  '将移除台账记录、原件和关联附件。',
                                  '删除',
                                  destructive: true,
                                ),
                              );
                              if (approved == true) {
                                await session.deleteSelected(ids);
                              }
                            },
                    ),
                    const SizedBox(width: 8),
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
                      onPressed: canImport ? choose : null,
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (anchor) => IconButtonS.toolbar(
                        'help',
                        '发票帮助',
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
                        for (final error in [
                          session.error,
                          session.batchError,
                        ].whereType<String>())
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
                                '${session.batchNotice == null ? '' : ' · ${session.batchNotice}'}'
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
          thumbVisibility: box.maxWidth < 1140,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(box.maxWidth, 1140),
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
                            _textCell('发票名称', header: true),
                            _textCell('销售方名称', header: true),
                            _textCell('开票日期', header: true),
                            _textCell('项目', header: true),
                            _textCell(
                              '金额',
                              header: true,
                              align: TextAlign.right,
                            ),
                            _textCell('消费日期', header: true),
                            _textCell('是否报销', header: true),
                            _textCell('报销月份', header: true),
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
                        return _LedgerRowTint(
                          key: ValueKey(entry.id),
                          selected: checked,
                          base: rowColor,
                          motion: motion,
                          child: Padding(
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
                                    showHoverBackground: false,
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
                                      Tooltip(
                                        message:
                                            session.recognitionFailures[entry
                                                .id] ??
                                            '',
                                        child: _textCell(
                                          session.recognitionFailures
                                                  .containsKey(entry.id)
                                              ? '识别未完成 · ${info.title.isEmpty ? entry.original.name : info.title}'
                                              : info.title.isEmpty
                                              ? (info.recognition.isEmpty
                                                    ? '待识别'
                                                    : '待核对')
                                              : info.title,
                                        ),
                                      ),
                                      _textCell(info.seller),
                                      _textCell(info.issued),
                                      _textCell(
                                        session.projects[info.project] ?? '',
                                      ),
                                      _textCell(
                                        info.amount.isEmpty ? '—' : info.amount,
                                        align: TextAlign.right,
                                      ),
                                      _textCell(info.spent),
                                      _textCell(
                                        info.reimbursed ? '已报销' : '未报销',
                                        color: info.reimbursed
                                            ? p.green
                                            : p.secondary,
                                      ),
                                      _textCell(info.month),
                                    ]),
                                  ),
                                ),
                              ],
                            ),
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
    const widths = [3, 3, 2, 2, 1, 2, 1, 1];
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

/// 发票台账整行底色：选中与悬停都由整行容器铺满，内部内容不再单独着色。
class _LedgerRowTint extends StatefulWidget {
  final bool selected;
  final Color base;
  final Duration motion;
  final Widget child;
  const _LedgerRowTint({
    super.key,
    required this.selected,
    required this.base,
    required this.motion,
    required this.child,
  });

  @override
  State<_LedgerRowTint> createState() => _LedgerRowTintState();
}

class _LedgerRowTintState extends State<_LedgerRowTint> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fill = widget.selected
        ? Color.alphaBlend(
            p.accent.withValues(alpha: p.dark ? .22 : .13),
            widget.base,
          )
        : hover
        ? Color.alphaBlend(p.hover, widget.base)
        : widget.base;
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: AnimatedContainer(
        duration: widget.motion,
        curve: spaceCurve,
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          color: fill,
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: widget.child,
      ),
    );
  }
}
