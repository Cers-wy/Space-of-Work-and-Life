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
  List<InvoiceFile> attachments,
});

class _MergeEditorState extends State<InvoiceMergeEditor> {
  final inputs = <_MergeInput>[];
  final sourcePages = <String, List<InvoiceSourcePage>>{};
  final attachmentPages = <String, List<InvoiceSourcePage>>{};
  final margin = [for (var i = 0; i < 4; i++) TextEditingController(text: '0')];
  List<Map<String, Object>> sheets = [];
  bool busy = false, reading = false, dragging = false, landscape = false;
  bool cutLines = true, includeAttachments = false;
  int perPage = 2, current = 0, previewRevision = 0;
  String? error, feedback, layoutError, previewError;
  Uint8List? preview;
  Timer? timer;

  bool get fromLedger => widget.entries != null;
  bool get canWork => !busy && !reading;
  bool get ready => canWork && sheets.isNotEmpty && layoutError == null;
  bool get hasAttachments => inputs.any((f) => f.attachments.isNotEmpty);
  double _margin(int i) => double.tryParse(margin[i].text.trim()) ?? double.nan;
  InvoiceLayout get layout => InvoiceLayout(
    landscape: landscape,
    cutLines: cutLines,
    perPage: perPage,
    top: _margin(0),
    right: _margin(1),
    bottom: _margin(2),
    left: _margin(3),
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
      sheets = layout.arrange(
        inputs.expand((f) => sourcePages[f.path]!).toList(),
        includeAttachments
            ? inputs
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
                : error ??
                      layoutError ??
                      feedback ??
                      '${inputs.length} 个来源 · ${sheets.length} 页 A4',
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
                    itemCount: inputs.length,
                    itemBuilder: (context, index) {
                      final f = inputs[index];
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
                                      inputs.removeAt(index);
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
            field(
              context,
              '每页发票数',
              SpaceSelect(
                value: '$perPage',
                label: '每页发票数',
                options: {for (var i = 1; i <= 4; i++) '$i': '$i 张 / 页'},
                onChanged: (v) => setState(() {
                  perPage = int.parse(v);
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
            SpaceCheckbox(
              label: '显示裁剪虚线',
              value: cutLines,
              onPressed: !canWork
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
