import 'dart:io';

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
    pageBuilder: (context, a, b) => Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 548,
          height: double.infinity,
          child: Material(
            type: MaterialType.transparency,
            child: _InvoiceDetails(store: store, session: session, id: id),
          ),
        ),
      ),
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
    '金额': TextEditingController(text: entry.info.amount),
    '消费时间': TextEditingController(text: entry.info.spent),
    '用途': TextEditingController(text: entry.info.purpose),
    '报销月份': TextEditingController(text: entry.info.month),
  };
  late String project = entry.info.project;
  late bool reimbursed = entry.info.reimbursed;
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

  Future<void> save() => act(() async {
    final text = value('金额');
    final amount = double.tryParse(text);
    if (text.isNotEmpty &&
        (!RegExp(r'^-?\d{1,12}(\.\d{1,2})?$').hasMatch(text) ||
            amount == null)) {
      throw StateError('请输入有效金额，最多保留两位小数');
    }
    await session.repo.save(
      widget.id,
      InvoiceInfo(
        number: value('票号'),
        issued: date('开票日期'),
        seller: value('销售方'),
        cents: amount == null ? null : (amount * 100).round(),
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
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: sheetFrame(
        context,
        title: '发票详情',
        close: close,
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SpaceEditorSection(
              children: [
                Row(
                  children: [
                    IconButtonS(
                      'invoice',
                      '发票原件',
                      selected: !attachments,
                      onPressed: busy
                          ? null
                          : () => setState(() => attachments = false),
                    ),
                    const SizedBox(width: 8),
                    IconButtonS(
                      'clip',
                      '关联附件（${entry.attachments.length}）',
                      selected: attachments,
                      onPressed: busy
                          ? null
                          : () => setState(() => attachments = true),
                    ),
                    const Spacer(),
                    if (attachments)
                      SpaceButton.form(
                        '添加附件',
                        onPressed: busy ? null : addAttachments,
                      ),
                  ],
                ),
                if (attachments && files.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButtonS(
                        'left',
                        '上一个附件',
                        size: spaceFormControlHeight,
                        onPressed: busy || index == 0
                            ? null
                            : () => showAttachment(files[index - 1].id),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: IgnorePointer(
                          ignoring: busy,
                          child: ExcludeFocus(
                            excluding: busy,
                            child: SpaceSelect(
                              value: files[index].id,
                              label: '预览附件',
                              options: {for (final f in files) f.id: f.name},
                              onChanged: showAttachment,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButtonS(
                        'right',
                        '下一个附件',
                        size: spaceFormControlHeight,
                        onPressed: busy || index + 1 == files.length
                            ? null
                            : () => showAttachment(files[index + 1].id),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                if (displayed == null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '可添加关联行程单或报销凭证',
                      style: textStyle(p, color: p.muted),
                    ),
                  )
                else ...[
                  _FilePreview(key: ValueKey(displayed.id), file: displayed),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButtonS(
                        'preview',
                        Platform.isWindows ? '在系统应用中打开' : '在速览中打开',
                        onPressed: busy
                            ? null
                            : () => act(
                                () => DesktopHost.preview(displayed.path),
                              ),
                      ),
                      const SizedBox(width: 8),
                      IconButtonS(
                        'save',
                        attachments ? '下载附件' : '下载原件',
                        onPressed: busy ? null : () => download(displayed),
                      ),
                      const Spacer(),
                      if (attachments)
                        SpaceButton.form(
                          '删除附件',
                          danger: true,
                          onPressed: busy
                              ? null
                              : () => removeAttachment(displayed),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            SpaceEditorSection(
              title: '发票信息',
              detail: '填写票面信息与报销信息。',
              children: [
                IgnorePointer(
                  ignoring: busy,
                  child: Column(
                    children: [
                      for (final pair in [
                        ('票号', '开票日期'),
                        ('销售方', '金额'),
                        ('消费时间', '报销月份'),
                      ]) ...[
                        Row(
                          children: [
                            Expanded(child: input(pair.$1)),
                            const SizedBox(width: 12),
                            Expanded(child: input(pair.$2)),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      input('用途'),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: field(
                              context,
                              '报销项目',
                              SpaceSelect(
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
                          ),
                          const SizedBox(width: 8),
                          IconButtonS(
                            'project',
                            '管理共用项目',
                            size: spaceFormControlHeight,
                            onPressed: busy
                                ? null
                                : () => act(() async {
                                    await openProjectEditor(
                                      context,
                                      widget.store,
                                    );
                                    if (!mounted) return;
                                    await reload();
                                    if (!session.projects.containsKey(
                                      project,
                                    )) {
                                      project = '';
                                    }
                                  }),
                          ),
                        ],
                      ),
                      SpaceCheckbox(
                        label: '已报销',
                        value: reimbursed,
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                reimbursed = !reimbursed;
                                dirty = true;
                              }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        footer: [
          SpaceButton.form(
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
          SpaceButton.form('取消', onPressed: busy ? null : close),
          const SizedBox(width: 8),
          SpaceButton.form(
            '保存更改',
            primary: true,
            onPressed: busy || !dirty ? null : save,
          ),
        ],
      ),
    );
  }

  Widget input(String key) => field(
    context,
    key,
    SpaceInput(
      controller: inputs[key]!,
      label: key,
      hint: key.endsWith('日期') || key.endsWith('时间')
          ? 'YYYY-MM-DD'
          : key.endsWith('月份')
          ? 'YYYY-MM'
          : '',
      onChanged: (_) {
        if (!dirty) setState(() => dirty = true);
      },
    ),
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
