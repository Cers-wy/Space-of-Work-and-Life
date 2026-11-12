import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../core/invoice_pdf.dart';
import '../core/invoices.dart';
import '../host.dart';
import '../store.dart';
import 'controls.dart';
import 'dialogs.dart';
import 'invoice_details.dart';
import 'invoice_workspace.dart' show InvoiceHint;
import 'theme.dart';

Future<void> openInvoiceMerge(
  BuildContext context,
  SpaceStore store,
  InvoiceRepository repo, {
  required List<InvoiceEntry> entries,
}) => invoiceModal(
  store,
  () => sheet<void>(
    context,
    InvoiceMergeEditor(repo: repo, entries: entries),
    width: 1136,
    height: 750,
  ),
);

class InvoiceMergeEditor extends StatefulWidget {
  final InvoiceRepository repo;
  final List<InvoiceEntry>? entries;
  const InvoiceMergeEditor({super.key, required this.repo, this.entries});

  @override
  State<InvoiceMergeEditor> createState() => _MergeEditorState();
}

typedef _MergeInput = ({
  String path,
  String name,
  String issued,
  List<InvoiceFile> attachments,
});

/// 一式两份：每个票面连续出现两次，配合每页 2 张即可得到同页两联。
List<InvoiceSourcePage> duplicateForDoubleCopy(
  List<InvoiceSourcePage> sources,
  bool enabled,
) => [
  for (final s in sources) ...[s, if (enabled) s],
];

class _MergeEditorState extends State<InvoiceMergeEditor> {
  final inputs = <_MergeInput>[];
  final sourcePages = <String, List<InvoiceSourcePage>>{};
  final attachmentPages = <String, List<InvoiceSourcePage>>{};
  final margin = [for (var i = 0; i < 4; i++) TextEditingController(text: '5')];
  final gap = TextEditingController(text: '10');
  List<Map<String, Object>> sheets = [];
  bool busy = false, reading = false, dragging = false, landscape = false;
  bool cutLines = true, includeAttachments = false, doubleCopy = false;
  String sortBy = 'default';
  int perPage = 2, current = 0, previewRevision = 0;
  int? perPageBeforeDouble;
  String? error, feedback, layoutError, previewError;
  Uint8List? preview;
  Timer? timer;

  bool get fromLedger => widget.entries != null;
  bool get canWork => !busy && !reading;
  bool get ready => canWork && sheets.isNotEmpty && layoutError == null;
  bool get hasAttachments => inputs.any((f) => f.attachments.isNotEmpty);

  /// 排序同时作用于来源列表与合并后的票面顺序。
  List<_MergeInput> get orderedInputs {
    final list = [...inputs];
    if (sortBy == 'date') {
      list.sort((a, b) {
        final x = a.issued.isEmpty ? '9999-99-99' : a.issued;
        final y = b.issued.isEmpty ? '9999-99-99' : b.issued;
        final byDate = x.compareTo(y);
        return byDate != 0 ? byDate : a.name.compareTo(b.name);
      });
    } else if (sortBy == 'name') {
      list.sort((a, b) => a.name.compareTo(b.name));
    }
    return list;
  }

  int get sourceCount =>
      orderedInputs.fold(0, (n, f) => n + (sourcePages[f.path]?.length ?? 1));

  String get perPageLabel => doubleCopy ? '2 张（一式两份）' : '$perPage 张';

  String get summary =>
      '$sourceCount 张发票 · 每页 $perPageLabel · ${sheets.length} 张 A4';
  double _margin(int i) => double.tryParse(margin[i].text.trim()) ?? double.nan;
  double get _gap => double.tryParse(gap.text.trim()) ?? double.nan;
  InvoiceLayout get layout => InvoiceLayout(
    landscape: landscape,
    cutLines: cutLines,
    perPage: perPage,
    top: _margin(0),
    right: _margin(1),
    bottom: _margin(2),
    left: _margin(3),
    gap: _gap,
  );

  @override
  void initState() {
    super.initState();
    if (fromLedger) {
      inputs.addAll(
        widget.entries!.map(
          (e) => (
            path: e.original.path,
            name: e.original.name,
            issued: e.info.issued,
            attachments: e.attachments,
          ),
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) readSources();
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    for (final m in margin) {
      m.dispose();
    }
    gap.dispose();
    super.dispose();
  }

  void close() {
    if (canWork) Navigator.pop(context);
  }

  Future<void> choose() async {
    if (!canWork) return;
    setState(() {
      busy = true;
      error = feedback = null;
    });
    try {
      final paths = await DesktopHost.openFiles(
        title: '选择 PDF 发票',
        extensions: const ['pdf'],
      );
      if (mounted) add(paths);
    } catch (e) {
      error = invoiceError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void add(List<String> paths) {
    if (paths.isEmpty) return;
    for (final path in paths) {
      if (inputs.any((f) => f.path == path)) continue;
      inputs.add((
        path: path,
        name: Uri.file(path).pathSegments.last,
        issued: '',
        attachments: const [],
      ));
    }
    unawaited(readSources());
  }

  Future<void> readSources() async {
    setState(() {
      reading = true;
      error = feedback = null;
    });
    final failures = <String>[];
    for (final f in inputs) {
      if (!mounted) return;
      if (!sourcePages.containsKey(f.path)) {
        try {
          sourcePages[f.path] = await InvoicePdf.inspect(f.path, trim: true);
        } catch (e) {
          failures.add('${f.name}：${invoiceError(e)}');
        }
      }
      if (includeAttachments && sourcePages.containsKey(f.path)) {
        for (final attachment in f.attachments) {
          if (!mounted) return;
          if (attachmentPages.containsKey(attachment.path)) continue;
          try {
            attachmentPages[attachment.path] = await InvoicePdf.inspect(
              attachment.path,
              trim: false,
            );
          } catch (e) {
            failures.add('${attachment.name}：${invoiceError(e)}');
          }
        }
      }
    }
    if (!mounted) return;
    setState(() {
      reading = false;
      if (failures.isNotEmpty) error = failures.join('\n');
      arrange();
    });
  }

  void arrange() {
    sheets = [];
    try {
      if (inputs.any((f) => !sourcePages.containsKey(f.path))) {
        throw StateError('请移除无法读取的发票，或重试');
      }
      if (includeAttachments &&
          inputs
              .expand((f) => f.attachments)
              .any((a) => !attachmentPages.containsKey(a.path))) {
        throw StateError('有附件无法读取。可关闭打印附件，或返回台账检查附件');
      }
      final ordered = orderedInputs;
      sheets = layout.arrange(
        duplicateForDoubleCopy([
          for (final f in ordered) ...sourcePages[f.path]!,
        ], doubleCopy),
        includeAttachments
            ? ordered
                  .expand((f) => f.attachments)
                  .expand((a) => attachmentPages[a.path]!)
                  .toList()
            : [],
      );
      layoutError = null;
    } catch (e) {
      layoutError = invoiceError(e);
    }
    current = sheets.isEmpty ? 0 : current.clamp(0, sheets.length - 1);
    schedulePreview();
  }

  void schedulePreview() {
    timer?.cancel();
    final revision = ++previewRevision;
    preview = null;
    previewError = null;
    if (sheets.isEmpty) return;
    final page = sheets[current];
    timer = Timer(const Duration(milliseconds: 100), () async {
      try {
        final bytes = await InvoicePdf.render(page);
        if (mounted && revision == previewRevision) {
          setState(() => preview = bytes);
        }
      } catch (e) {
        if (mounted && revision == previewRevision) {
          setState(() => previewError = invoiceError(e));
        }
      }
    });
  }

  Future<void> output({required bool print}) async {
    if (!ready) return;
    final pages = sheets;
    setState(() {
      busy = true;
      error = feedback = null;
    });
    try {
      if (print) {
        await InvoicePdf.print(layout, pages);
      } else {
        final path = await DesktopHost.saveFile('发票合并.pdf', title: '保存合并 PDF');
        if (path != null) {
          await InvoicePdf.save(widget.repo, path, pages);
          feedback = '已保存 ${pages.length} 页 PDF';
        }
      }
    } catch (e) {
      error = invoiceError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final body = Column(
      children: [
        SizedBox(
          height: 2,
          child: reading || busy ? const LinearProgressIndicator() : null,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(flex: 25, child: sources()),
                const SizedBox(width: 12),
                Expanded(flex: 47, child: paperPreview()),
                const SizedBox(width: 12),
                Expanded(flex: 28, child: settings()),
              ],
            ),
          ),
        ),
      ],
    );
    final footer = <Widget>[
      Expanded(
        child: Tooltip(
          message: error ?? layoutError ?? '',
          child: Text(
            reading
                ? '正在读取文件…'
                : busy
                ? '正在处理…'
                : error ?? layoutError ?? feedback ?? summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textStyle(
              p,
              size: 12,
              color: error != null || layoutError != null ? p.red : p.muted,
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      IconButtonS(
        'save',
        '保存 PDF',
        onPressed: ready ? () => output(print: false) : null,
      ),
      const SizedBox(width: 8),
      IconButtonS(
        'printer',
        '打印',
        primary: true,
        onPressed: ready ? () => output(print: true) : null,
      ),
    ];
    if (!fromLedger) {
      return Column(
        children: [
          Expanded(child: body),
          SpaceEditorFooter(children: footer),
        ],
      );
    }
    return PopScope(
      canPop: canWork,
      child: sheetFrame(
        context,
        title: '勾选发票 · 合并打印',
        close: close,
        body: body,
        footer: footer,
      ),
    );
  }

  Widget sources() {
    final p = Palette.of(context);
    final content = Glass(
      card: true,
      blur: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpaceTitleBar(
            children: [
              Expanded(
                child: Text(
                  '发票来源',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle(p, bold: true),
                ),
              ),
              if (canWork && error != null && inputs.isNotEmpty)
                IconButtonS.toolbar('refresh', '重新读取', onPressed: readSources),
              if (!fromLedger)
                IconButtonS.toolbar(
                  'plus',
                  '添加 PDF',
                  onPressed: canWork ? choose : null,
                ),
            ],
          ),
          Expanded(
            child: inputs.isEmpty
                ? InvoiceHint(
                    'upload',
                    dragging ? '松开以添加' : '拖入 PDF 发票',
                    compact: true,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: orderedInputs.length,
                    itemBuilder: (context, index) {
                      final f = orderedInputs[index];
                      return Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SpaceIcon('invoice', size: 16, color: p.accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Tooltip(
                                message: f.name,
                                child: Text(
                                  f.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textStyle(
                                    p,
                                    size: 12,
                                    color:
                                        !reading &&
                                            !sourcePages.containsKey(f.path)
                                        ? p.red
                                        : p.text,
                                  ),
                                ),
                              ),
                            ),
                            IconButtonS(
                              'x',
                              '移除 ${f.name}',
                              onPressed: !canWork
                                  ? null
                                  : () => setState(() {
                                      inputs.removeWhere(
                                        (item) => item.path == f.path,
                                      );
                                      error = feedback = null;
                                      arrange();
                                    }),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
    if (fromLedger) return content;
    return DropTarget(
      onDragEntered: (_) {
        if (canWork) setState(() => dragging = true);
      },
      onDragExited: (_) {
        if (dragging) setState(() => dragging = false);
      },
      onDragDone: (d) {
        if (dragging) setState(() => dragging = false);
        if (canWork) add(d.files.map((f) => f.path).toList());
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: dragging ? Border.all(color: p.accent, width: 2) : null,
        ),
        child: content,
      ),
    );
  }

  Widget paperPreview() {
    final p = Palette.of(context);
    final waiting = reading || sheets.isNotEmpty && previewError == null;
    return Glass(
      card: true,
      blur: false,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('A4 排版预览', style: textStyle(p, bold: true))),
              Text(
                landscape ? '横向' : '纵向',
                style: textStyle(p, size: 12, color: p.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: preview == null && !waiting
                ? InvoiceHint(
                    'file',
                    previewError ??
                        (layoutError == null ? '添加发票后预览' : '请检查发票或排版设置'),
                    compact: true,
                  )
                : Center(
                    child: AspectRatio(
                      aspectRatio: layout.width / layout.height,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: p.popupBorder),
                        ),
                        child: preview != null
                            ? Image.memory(preview!, fit: BoxFit.contain)
                            : const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButtonS(
                'left',
                '上一页',
                size: 28,
                onPressed: current > 0 ? () => turn(-1) : null,
              ),
              Text(
                sheets.isEmpty ? '0 / 0' : '${current + 1} / ${sheets.length}',
                style: textStyle(p, size: 12),
              ),
              IconButtonS(
                'right',
                '下一页',
                size: 28,
                onPressed: current + 1 < sheets.length ? () => turn(1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void turn(int by) => setState(() {
    current += by;
    schedulePreview();
  });

  /// 排版方式用网格示意直接选择，横向与纵向的槽位方向随纸张方向变化。
  Widget _layoutButton(Palette p, int count) {
    final selected = perPage == count;
    final columns = count == 4 ? 2 : (landscape ? count : 1);
    final rows = count == 4 ? 2 : (landscape ? 1 : count);
    final color = selected ? p.accent : p.secondary;
    return Expanded(
      child: SpaceButton(
        key: ValueKey('merge-layout-$count'),
        height: 64,
        soft: true,
        selected: selected,
        tooltip: doubleCopy ? '一式两份固定每页 2 张' : '$count 张 / 页',
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        onPressed: doubleCopy || !canWork
            ? null
            : () => setState(() {
                perPage = count;
                arrange();
              }),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 28,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: p.card.withValues(alpha: p.dark ? .30 : .60),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: selected ? p.accent : p.border),
              ),
              child: Column(
                children: [
                  for (var r = 0; r < rows; r++) ...[
                    if (r > 0) const SizedBox(height: 2),
                    Expanded(
                      child: Row(
                        children: [
                          for (var c = 0; c < columns; c++) ...[
                            if (c > 0) const SizedBox(width: 2),
                            Expanded(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: .16),
                                  border: Border.all(color: color, width: 1),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$count 张',
              style: textStyle(
                p,
                size: 10,
                color: selected ? p.accent : p.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget settings() {
    final p = Palette.of(context);
    return Glass(
      card: true,
      blur: false,
      child: AbsorbPointer(
        absorbing: !canWork,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text('排版设置', style: textStyle(p, bold: true)),
            const SizedBox(height: 4),
            Text(summary, style: textStyle(p, size: 11, color: p.muted)),
            const SizedBox(height: 10),
            field(
              context,
              '纸张方向',
              SpaceSelect(
                value: landscape ? 'landscape' : 'portrait',
                label: '纸张方向',
                options: const {'portrait': '纵向 A4', 'landscape': '横向 A4'},
                onChanged: (v) => setState(() {
                  landscape = v == 'landscape';
                  arrange();
                }),
              ),
            ),
            const SizedBox(height: 10),
            Text('排版方式', style: textStyle(p, bold: true)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var count = 1; count <= 4; count++) ...[
                  if (count > 1) const SizedBox(width: 8),
                  _layoutButton(p, count),
                ],
              ],
            ),
            const SizedBox(height: 10),
            field(
              context,
              '排序设置',
              SpaceSelect(
                value: sortBy,
                label: '排序设置',
                options: const {
                  'default': '按添加顺序',
                  'date': '按开票日期',
                  'name': '按文件名',
                },
                onChanged: (v) => setState(() {
                  sortBy = v;
                  arrange();
                }),
              ),
            ),
            const SizedBox(height: 10),
            Text('边距（mm）', style: textStyle(p, bold: true)),
            const SizedBox(height: 8),
            for (final indexes in [
              [0, 1],
              [2, 3],
            ]) ...[
              Row(
                children: [
                  for (final i in indexes) ...[
                    if (i == indexes.last) const SizedBox(width: 8),
                    Expanded(
                      child: field(
                        context,
                        ['上', '右', '下', '左'][i],
                        SpaceInput(
                          controller: margin[i],
                          label: '${['上', '右', '下', '左'][i]}边距',
                          onChanged: (_) => setState(arrange),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
            ],
            field(
              context,
              '票间距（mm）',
              SpaceInput(
                controller: gap,
                label: '票间距',
                onChanged: (_) => setState(arrange),
              ),
            ),
            const SizedBox(height: 8),
            SpaceCheckbox(
              label: '一式两份',
              description: '一张 A4 纸打印两张相同发票',
              value: doubleCopy,
              onPressed: !canWork
                  ? null
                  : () => setState(() {
                      doubleCopy = !doubleCopy;
                      if (doubleCopy) {
                        perPageBeforeDouble = perPage;
                        perPage = 2;
                        cutLines = true;
                      } else {
                        perPage = perPageBeforeDouble ?? 2;
                      }
                      arrange();
                    }),
            ),
            SpaceCheckbox(
              label: '显示裁剪虚线',
              description: doubleCopy ? '一式两份时自动显示' : null,
              value: cutLines,
              onPressed: doubleCopy || !canWork
                  ? null
                  : () => setState(() {
                      cutLines = !cutLines;
                      arrange();
                    }),
            ),
            if (fromLedger)
              SpaceCheckbox(
                label: '打印附件',
                description: '附件在发票页之后单独分页',
                value: includeAttachments,
                onPressed: !hasAttachments || !canWork
                    ? null
                    : () {
                        if (!includeAttachments) {
                          includeAttachments = true;
                          readSources();
                        } else {
                          setState(() {
                            includeAttachments = false;
                            error = null;
                            arrange();
                          });
                        }
                      },
              ),
          ],
        ),
      ),
    );
  }
}
