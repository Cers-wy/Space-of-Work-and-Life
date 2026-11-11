import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/invoice_export.dart';
import '../core/invoice_pdf.dart';
import '../core/invoices.dart';
import '../host.dart';
import '../store.dart';
import 'controls.dart';
import 'dialogs.dart';
import 'invoice_workspace.dart';
import 'theme.dart';

Future<T?> invoiceModal<T>(SpaceStore store, Future<T?> Function() open) async {
  if (store.modal) return null;
  store.modal = true;
  store.refreshQuery();
  try {
    return await open();
  } finally {
    store.modal = false;
    store.refreshQuery();
  }
}

Future<void> showInvoiceDetails(
  BuildContext context,
  SpaceStore store,
  InvoiceSession session,
  String id,
) => invoiceModal(
  store,
  () => showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '发票详情',
    barrierColor: Colors.black.withValues(alpha: .18),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 210),
    transitionBuilder: (context, animation, secondary, child) =>
        SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: spaceCurve)).animate(animation),
          child: child,
        ),
    pageBuilder: (context, a, b) => LayoutBuilder(
      builder: (c, box) {
        final wide = box.maxWidth >= 960;
        final width = wide
            ? math.min(1040.0, box.maxWidth - 32)
            : math.min(548.0, box.maxWidth - 16);
        return Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: width,
              height: double.infinity,
              child: Material(
                type: MaterialType.transparency,
                child: _InvoiceDetails(store: store, session: session, id: id),
              ),
            ),
          ),
        );
      },
    ),
  ),
);

class _InvoiceDetails extends StatefulWidget {
  final SpaceStore store;
  final InvoiceSession session;
  final String id;
  const _InvoiceDetails({
    required this.store,
    required this.session,
    required this.id,
  });

  @override
  State<_InvoiceDetails> createState() => _InvoiceDetailsState();
}

class _InvoiceDetailsState extends State<_InvoiceDetails> {
  late InvoiceEntry entry = session.ledger!.entries.firstWhere(
    (e) => e.id == widget.id,
  );
  late final inputs = {
    '票号': TextEditingController(text: entry.info.number),
    '开票日期': TextEditingController(text: entry.info.issued),
    '销售方': TextEditingController(text: entry.info.seller),
    '销售方税号': TextEditingController(text: entry.info.sellerTax),
    '购买方': TextEditingController(text: entry.info.buyer),
    '购买方税号': TextEditingController(text: entry.info.buyerTax),
    '金额': TextEditingController(text: entry.info.amount),
    '税额': TextEditingController(text: entry.info.tax),
    '未税金额': TextEditingController(text: entry.info.net),
    '消费时间': TextEditingController(text: entry.info.spent),
    '用途': TextEditingController(text: entry.info.purpose),
    '报销月份': TextEditingController(text: entry.info.month),
  };
  late String project = entry.info.project;
  late bool reimbursed = entry.info.reimbursed;
  late bool monthAuto =
      entry.info.month.isEmpty ||
      (entry.info.spent.length >= 7 &&
          entry.info.month == entry.info.spent.substring(0, 7));
  bool busy = false, dirty = false, attachments = false;
  String? error, notice;
  String? attachmentId;
  InvoiceSession get session => widget.session;
  int get attachmentIndex {
    final index = entry.attachments.indexWhere((f) => f.id == attachmentId);
    return index < 0 ? 0 : index;
  }

  @override
  void dispose() {
    for (final input in inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  Future<void> close() async {
    if (busy) return;
    if (!dirty ||
        await confirm(
          context,
          '放弃修改？',
          '还有尚未保存的发票信息。',
          '放弃修改',
          destructive: true,
        )) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> act(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = notice = null;
    });
    try {
      await work();
    } catch (e) {
      error = invoiceError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reload() async {
    await session.refresh();
    session.update(() {});
    entry = session.ledger!.entries.firstWhere((e) => e.id == widget.id);
  }

  String value(String key) => inputs[key]!.text.trim();

  String date(String key, {bool month = false}) {
    final v = value(key);
    if (v.isEmpty) return v;
    final format = month
        ? RegExp(r'^\d{4}-\d{2}$')
        : RegExp(r'^\d{4}-\d{2}-\d{2}$');
    final full = month ? '$v-01' : v;
    final parsed = DateTime.tryParse(full);
    if (!format.hasMatch(v) ||
        parsed == null ||
        !parsed.toIso8601String().startsWith(full)) {
      throw StateError('$key 请输入${month ? ' YYYY-MM' : ' YYYY-MM-DD'}');
    }
    return v;
  }

  int? amountCents(String key) {
    final text = value(key);
    if (text.isEmpty) return null;
    final amount = double.tryParse(text);
    if (!RegExp(r'^-?\d{1,12}(\.\d{1,2})?$').hasMatch(text) ||
        amount == null) {
      throw StateError('请输入有效$key，最多保留两位小数');
    }
    return (amount * 100).round();
  }

  Future<void> save() => act(() async {
    await session.repo.save(
      widget.id,
      InvoiceInfo(
        number: value('票号'),
        issued: date('开票日期'),
        seller: value('销售方'),
        sellerTax: value('销售方税号'),
        buyer: value('购买方'),
        buyerTax: value('购买方税号'),
        cents: amountCents('金额'),
        taxCents: amountCents('税额'),
        netCents: amountCents('未税金额'),
        spent: date('消费时间'),
        purpose: value('用途'),
        month: date('报销月份', month: true),
        project: project,
        reimbursed: reimbursed,
      ),
    );
    await reload();
    dirty = false;
    notice = '发票信息已保存';
  });

  Future<void> remove() async {
    if (!await confirm(
      context,
      '删除发票？',
      '将移除台账记录、原件和关联附件。',
      '删除发票',
      destructive: true,
    )) {
      return;
    }
    if (!mounted) return;
    await act(() async {
      await session.repo.delete(widget.id);
      await session.refresh();
      session.update(() => session.notice = '已删除发票');
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> addAttachments() => act(() async {
    final paths = await DesktopHost.openFiles(
      title: '添加行程单或附件',
      extensions: invoiceFileExtensions.toList(),
    );
    if (paths.isEmpty) return;
    final result = await session.repo.importFiles(
      paths,
      attachmentTo: widget.id,
    );
    await reload();
    notice = '已添加 ${result.count} 个附件';
    if (result.errors.isNotEmpty) error = result.errors.join('\n');
  });

  Future<void> removeAttachment(InvoiceFile f) async {
    if (!await confirm(context, '删除附件？', f.name, '删除附件', destructive: true) ||
        !mounted) {
      return;
    }
    await act(() async {
      final index = attachmentIndex;
      await session.repo.removeAttachment(widget.id, f.id);
      await reload();
      final files = entry.attachments;
      attachmentId = files.isEmpty
          ? null
          : files[index.clamp(0, files.length - 1)].id;
      notice = '已删除附件';
    });
  }

  void showAttachment(String id) => setState(() => attachmentId = id);

  Future<void> download(InvoiceFile f) => act(() async {
    final target = await DesktopHost.saveFile(
      f.name,
      title: '下载${f.id == entry.original.id ? '发票' : '附件'}',
    );
    if (target == null) return;
    await session.repo.saveCopy(f, target);
    notice = '文件已保存';
  });

  void wheelAttachments(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !attachments) return;
    final files = entry.attachments;
    if (files.length < 2) return;
    final index = attachmentIndex;
    final next = event.scrollDelta.dy > 0 ? index + 1 : index - 1;
    if (next >= 0 && next < files.length) showAttachment(files[next].id);
  }

  Widget _countBadge(Palette p, int count) => Container(
    constraints: const BoxConstraints(minWidth: 16),
    height: 16,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: p.accent,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: p.panel, width: 1.5),
    ),
    child: Text(
      '$count',
      style: textStyle(
        p,
        size: 10,
        color: Colors.white,
      ),
    ),
  );

  Widget _previewPane(
    Palette p,
    List<InvoiceFile> files,
    int index,
    InvoiceFile? displayed, {
    required bool scroll,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButtonS(
              'invoice',
              '发票原件',
              selected: !attachments,
              soft: true,
              onPressed: busy ? null : () => setState(() => attachments = false),
            ),
            const SizedBox(width: 4),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButtonS(
                  'clip',
                  '关联附件（${files.length}）',
                  selected: attachments,
                  soft: true,
                  onPressed: busy ? null : () => setState(() => attachments = true),
                ),
                if (files.isNotEmpty)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: IgnorePointer(child: _countBadge(p, files.length)),
                  ),
              ],
            ),
            const Spacer(),
            if (attachments)
              IconButtonS(
                'plus',
                '添加附件',
                onPressed: busy ? null : addAttachments,
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (displayed == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                SpaceIcon('clip', size: 22, color: p.muted),
                const SizedBox(height: 8),
                Text(
                  '可添加关联行程单或报销凭证',
                  style: textStyle(p, size: 12, color: p.muted),
                ),
                const SizedBox(height: 8),
                SpaceTextButton(
                  '添加附件',
                  icon: 'plus',
                  onPressed: busy ? null : addAttachments,
                ),
              ],
            ),
          )
        else ...[
          Listener(
            onPointerSignal: wheelAttachments,
            child: _FilePreview(key: ValueKey(displayed.id), file: displayed),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButtonS(
                'preview',
                Platform.isWindows ? '在系统应用中打开' : '在速览中打开',
                onPressed: busy
                    ? null
                    : () => act(() => DesktopHost.preview(displayed.path)),
              ),
              const SizedBox(width: 8),
              IconButtonS(
                'save',
                attachments ? '下载附件' : '下载原件',
                onPressed: busy ? null : () => download(displayed),
              ),
              const Spacer(),
              if (attachments)
                IconButtonS(
                  'trash',
                  '删除附件',
                  danger: true,
                  onPressed: busy ? null : () => removeAttachment(displayed),
                ),
            ],
          ),
          if (attachments && files.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: files.length,
                      separatorBuilder: (_, i) => const SizedBox(width: 6),
                      itemBuilder: (c, i) {
                        final current = i == index;
                        return Tooltip(
                          message: files[i].name,
                          child: GestureDetector(
                            onTap: busy
                                ? null
                                : () => showAttachment(files[i].id),
                            child: AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 120),
                              width: 44,
                              decoration: BoxDecoration(
                                color: current
                                    ? p.accent.withValues(alpha: .12)
                                    : p.card.withValues(alpha: .5),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: current ? p.accent : p.border,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '${i + 1}',
                                  style: textStyle(
                                    p,
                                    size: 12,
                                    color: current ? p.accent : p.secondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${index + 1} / ${files.length}',
                  style: textStyle(p, size: 11, color: p.muted),
                ),
              ],
            ),
          ],
        ],
      ],
    );
    if (!scroll) return content;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: content,
    );
  }

  Widget _label(Palette p, String text) => Text(
    text,
    maxLines: 2,
    style: textStyle(p, size: 11.5, color: p.muted),
  );

  Widget _row(Palette p, String label, Widget value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 112, child: _label(p, label)),
        Expanded(child: value),
      ],
    ),
  );

  Widget _heading(Palette p, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: textStyle(p, size: 11, bold: true, color: p.muted),
    ),
  );

  Widget _amountCell(Palette p, String label, String value, {bool strong = false}) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: textStyle(p, size: 11, color: p.muted)),
        const SizedBox(height: 2),
        Text(
          value.isEmpty ? '—' : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle(
            p,
            size: strong ? 15 : 13,
            bold: strong,
            color: value.isEmpty ? p.muted : (strong ? p.text : p.secondary),
          ),
        ),
      ],
    ),
  );

  Widget _amounts(Palette p) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
    decoration: BoxDecoration(
      color: p.card.withValues(alpha: p.dark ? .30 : .42),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: p.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('金额', style: textStyle(p, size: 11, color: p.muted)),
        const SizedBox(height: 6),
        Row(
          children: [
            _amountCell(p, '总金额', value('金额'), strong: true),
            const SizedBox(width: 12),
            _amountCell(p, '税额', value('税额')),
            const SizedBox(width: 12),
            _amountCell(p, '未税金额', value('未税金额')),
          ],
        ),
      ],
    ),
  );

  Widget _formPane(Palette p, {required bool scroll}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(p, '票面信息'),
        _row(p, '发票号码', input('票号')),
        _row(p, '开票日期', input('开票日期')),
        _row(p, '销售方', input('销售方')),
        _row(p, '销售方社会信用代码', input('销售方税号')),
        _row(p, '购买方', input('购买方')),
        _row(p, '购买方社会信用代码', input('购买方税号')),
        const SizedBox(height: 8),
        _amounts(p),
        const SizedBox(height: 14),
        _heading(p, '报销信息'),
        _row(
          p,
          '报销项目',
          Row(
            children: [
              Expanded(
                child: SpaceSelect(
                  value: project,
                  label: '选择报销项目',
                  options: projectChoices(
                    widget.store.state,
                    selected: project,
                  ),
                  onChanged: (v) => setState(() {
                    project = v;
                    dirty = true;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              IconButtonS(
                'project',
                '管理共用项目',
                size: spaceFormControlHeight,
                onPressed: busy
                    ? null
                    : () => act(() async {
                        await openProjectEditor(context, widget.store);
                        if (!mounted) return;
                        await reload();
                        if (!session.projects.containsKey(project)) {
                          project = '';
                        }
                      }),
              ),
            ],
          ),
        ),
        _row(
          p,
          '报销月份',
          Row(
            children: [
              Expanded(child: input('报销月份')),
              if (monthAuto) ...[
                const SizedBox(width: 8),
                Text(
                  '随消费日期',
                  style: textStyle(p, size: 10, color: p.muted),
                ),
              ],
            ],
          ),
        ),
        _row(p, '消费时间', input('消费时间')),
        _row(
          p,
          '是否报销',
          Align(
            alignment: Alignment.centerLeft,
            child: SpaceCheckbox(
              label: '已报销',
              value: reimbursed,
              onPressed: busy
                  ? null
                  : () => setState(() {
                      reimbursed = !reimbursed;
                      dirty = true;
                    }),
            ),
          ),
        ),
        _row(p, '用途', input('用途')),
      ],
    );
    if (!scroll) return content;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final files = entry.attachments;
    final index = attachmentIndex;
    final displayed = attachments
        ? (files.isEmpty ? null : files[index])
        : entry.original;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          close();
          return KeyEventResult.handled;
        }
        if (attachments &&
            files.length > 1 &&
            (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowRight)) {
          final next =
              index +
              (event.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : -1);
          if (next >= 0 && next < files.length) {
            showAttachment(files[next].id);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (c, box) {
          final wide = box.maxWidth >= 960;
          return sheetFrame(
            context,
            title: '发票详情',
            close: close,
            body: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 11,
                        child: _previewPane(
                          p,
                          files,
                          index,
                          displayed,
                          scroll: true,
                        ),
                      ),
                      VerticalDivider(width: 1, color: p.border),
                      Expanded(
                        flex: 10,
                        child: _formPane(p, scroll: true),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _previewPane(p, files, index, displayed, scroll: false),
                      const SizedBox(height: 16),
                      _formPane(p, scroll: false),
                    ],
                  ),
            footer: [
              IconButtonS(
                'trash',
                '删除发票',
                danger: true,
                onPressed: busy ? null : remove,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: error ?? notice ?? '',
                  child: Text(
                    busy ? '正在处理…' : error ?? notice ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(
                      p,
                      size: 12,
                      color: error == null ? p.muted : p.red,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SpaceTextButton('取消', onPressed: busy ? null : close),
              const SizedBox(width: 8),
              SpaceTextButton(
                '保存更改',
                primary: true,
                onPressed: busy || !dirty ? null : save,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget input(String key) => SpaceInput(
    controller: inputs[key]!,
    label: key,
    height: 32,
    fontSize: 12,
    hint: key.endsWith('日期') || key.endsWith('时间')
        ? 'YYYY-MM-DD'
        : key.endsWith('月份')
        ? 'YYYY-MM'
        : '',
    onChanged: (v) {
      if (key == '消费时间' && monthAuto && v.length >= 7) {
        inputs['报销月份']!.text = v.substring(0, 7);
      }
      if (key == '报销月份') monthAuto = false;
      if (!dirty) setState(() => dirty = true);
    },
  );
}

class _FilePreview extends StatefulWidget {
  final InvoiceFile file;
  const _FilePreview({super.key, required this.file});

  @override
  State<_FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<_FilePreview> {
  int page = 1;
  // Decode from memory so Windows can delete or replace the previewed file.
  late final imageBytes = File(widget.file.path).readAsBytes();
  late Future<InvoicePreview> preview = InvoicePdf.preview(
    widget.file.path,
    page,
  );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (!widget.file.isPdf) {
      return SizedBox(
        height: 220,
        child: FutureBuilder(
          future: imageBytes,
          builder: (context, state) {
            if (state.connectionState != ConnectionState.done) {
              return const Center(child: Text('正在加载图片…'));
            }
            if (!state.hasData) return const Center(child: Text('无法打开图片'));
            return Image.memory(
              state.data!,
              cacheWidth: 900,
              fit: BoxFit.contain,
              errorBuilder: (_, error, stack) =>
                  const Center(child: Text('无法打开图片')),
            );
          },
        ),
      );
    }
    return FutureBuilder<InvoicePreview>(
      future: preview,
      builder: (context, state) {
        final result = state.data;
        return Column(
          children: [
            SizedBox(
              height: 220,
              child: state.connectionState != ConnectionState.done
                  ? const Center(child: CircularProgressIndicator())
                  : result == null
                  ? Center(
                      child: Text(
                        invoiceError(state.error ?? StateError('无法预览文件')),
                      ),
                    )
                  : Image.memory(result.bytes, fit: BoxFit.contain),
            ),
            if (result != null && result.pages > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButtonS(
                    'left',
                    '上一页',
                    size: 28,
                    onPressed: page > 1 ? () => turn(-1) : null,
                  ),
                  Text(
                    '$page / ${result.pages}',
                    style: textStyle(p, size: 12),
                  ),
                  IconButtonS(
                    'right',
                    '下一页',
                    size: 28,
                    onPressed: page < result.pages ? () => turn(1) : null,
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  void turn(int delta) => setState(() {
    page += delta;
    preview = InvoicePdf.preview(widget.file.path, page);
  });
}

Future<void> showInvoiceExport(
  BuildContext context,
  SpaceStore store,
  InvoiceSession session,
  List<InvoiceEntry> filtered,
  List<InvoiceEntry> selected,
) async {
  final plan = await invoiceModal(
    store,
    () => sheet<({List<InvoiceColumn> columns, bool selected})>(
      context,
      _ExportOptions(filtered.length, selected.length),
      width: 450,
      height: 396,
    ),
  );
  if (plan == null || !context.mounted) return;
  await session.run(() async {
    final path = await DesktopHost.saveFile('发票台账.xlsx', title: '导出发票台账');
    if (path == null) return null;
    final rows = plan.selected ? selected : filtered;
    await exportInvoiceSheet(
      session.repo,
      path,
      rows,
      session.projects,
      plan.columns,
    );
    return '已导出 ${rows.length} 张发票';
  }, reload: false);
}

class _ExportOptions extends StatefulWidget {
  final int filteredCount, selectedCount;
  const _ExportOptions(this.filteredCount, this.selectedCount);
  @override
  State<_ExportOptions> createState() => _ExportOptionsState();
}

class _ExportOptionsState extends State<_ExportOptions> {
  final columns = InvoiceColumn.values.toSet();
  late bool selected = widget.selectedCount > 0;

  @override
  Widget build(BuildContext context) => sheetFrame(
    context,
    title: '按字段导出台账',
    close: () => Navigator.pop(context),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SpaceSelect(
          value: selected ? 'selected' : 'filtered',
          label: '导出范围',
          options: {
            'filtered': '当前筛选结果（${widget.filteredCount} 张）',
            if (widget.selectedCount > 0)
              'selected': '已勾选（${widget.selectedCount} 张）',
          },
          onChanged: (v) => setState(() => selected = v == 'selected'),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 8,
            children: [
              for (final c in InvoiceColumn.values)
                SizedBox(
                  width: box.maxWidth < 320
                      ? box.maxWidth
                      : (box.maxWidth - 8) / 2,
                  child: SpaceCheckbox(
                    label: c.title,
                    value: columns.contains(c),
                    onPressed: () => setState(() {
                      if (!columns.remove(c)) columns.add(c);
                    }),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
    footer: [
      const Spacer(),
      IconButtonS(
        'save',
        '导出 Excel',
        primary: true,
        onPressed: columns.isEmpty
            ? null
            : () => Navigator.pop(context, (
                columns: InvoiceColumn.values.where(columns.contains).toList(),
                selected: selected,
              )),
      ),
    ],
  );
}
