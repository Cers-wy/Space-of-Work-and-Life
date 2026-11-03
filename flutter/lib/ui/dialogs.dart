import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_quill/quill_delta.dart' show Delta;
import '../core/models.dart';
import '../core/richtext.dart';
import '../host.dart';
import '../store.dart';
import 'theme.dart';
import 'controls.dart';
import 'sync_settings.dart';
import 'image_preview.dart';

Future<T?> sheet<T>(
  BuildContext context,
  Widget child, {
  required double width,
  required double height,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: false,
  barrierLabel: '关闭面板',
  barrierColor: Colors.black.withValues(alpha: .18),
  transitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (c, a, b) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: height),
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(c).maybePop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    ),
  ),
);
Widget sheetFrame(
  BuildContext c, {
  required String title,
  required Widget body,
  required List<Widget> footer,
  required VoidCallback close,
}) {
  final p = Palette.of(c);
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Stack(
      children: [
        Positioned.fill(child: Ambient()),
        Glass(
          blur: false,
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Text(title, style: textStyle(p, size: 16, bold: true)),
                      const Spacer(),
                      IconButtonS('x', '关闭$title', size: 24, onPressed: close),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: p.border),
              Expanded(child: body),
              Divider(height: 1, color: p.border),
              SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(children: footer),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) {
        final p = Palette.of(c);
        return Dialog(
          backgroundColor: Colors.transparent,
          child: SizedBox(
            width: 420,
            child: PopupSurface(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textStyle(p, size: 16, bold: true)),
                  const SizedBox(height: 16),
                  Text(message, style: textStyle(p)),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SpaceButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      SpaceButton(
                        primary: true,
                        onPressed: () => Navigator.pop(c, true),
                        child: Text(action),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ) ??
    false;
Widget field(BuildContext c, String label, Widget child) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(label, style: textStyle(Palette.of(c), bold: true)),
    const SizedBox(height: 8),
    child,
  ],
);
Future<void> editTask(
  BuildContext c,
  SpaceStore s,
  SpaceTask task, {
  bool existing = false,
}) async {
  if (s.modal || !s.loaded || s.busy) return;
  s.modal = true;
  s.refreshQuery();
  try {
    await sheet(
      c,
      _TaskEditor(store: s, task: task, existing: existing),
      width: 640,
      height: 680,
    );
  } finally {
    s.modal = false;
    s.refreshQuery();
  }
}

class _TaskEditor extends StatefulWidget {
  final SpaceStore store;
  final SpaceTask task;
  final bool existing;
  const _TaskEditor({
    required this.store,
    required this.task,
    required this.existing,
  });
  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late SpaceTask draft;
  late TextEditingController title;
  final project = TextEditingController(),
      editorFocus = FocusNode(),
      titleFocus = FocusNode();
  String? titleError;
  late q.QuillController rich;
  late Delta initialDelta;
  bool creatingProject = false, saving = false, richFailed = false;
  String? error;
  SpaceStore get s => widget.store;
  @override
  void initState() {
    super.initState();
    draft = widget.task;
    title = TextEditingController(text: draft.title);
    List<Map<String, dynamic>> ops = [];
    try {
      final runs = draft.richDescription == null
          ? [RichRun(text: draft.description)]
          : FlatRtfd.decode(base64Decode(draft.richDescription!));
      for (final run in runs) {
        ops.add({
          'insert': run.image == null
              ? run.text
              : {'image': base64Encode(run.image!)},
          if (run.bold || run.underline)
            'attributes': {
              if (run.bold) 'bold': true,
              if (run.underline) 'underline': true,
            },
        });
      }
      if (ops.isEmpty ||
          ops.last['insert'] is! String ||
          !(ops.last['insert'] as String).endsWith('\n')) {
        ops.add({'insert': '\n'});
      }
    } catch (e) {
      richFailed = true;
      error = '图文暂时无法解码，原始内容已保留。可修改其他字段。';
      ops = [
        {'insert': '${draft.description}\n'},
      ];
    }
    rich = q.QuillController(
      document: q.Document.fromJson(ops),
      selection: const TextSelection.collapsed(offset: 0),
      config: q.QuillControllerConfig(
        clipboardConfig: q.QuillClipboardConfig(
          onClipboardPaste: paste,
          onImagePaste: (bytes) async => base64Encode(bytes),
        ),
      ),
    );
    rich.readOnly = richFailed;
    initialDelta = rich.document.toDelta();
    rich.addListener(changed);
    title.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
    DesktopHost.channel
        .invokeMethod("dirty", {"dirty": dirty})
        .catchError((_) => null);
  }

  bool get richDirty => initialDelta != rich.document.toDelta();
  bool get dirty =>
      title.text != widget.task.title ||
      (!identical(draft, widget.task) &&
          jsonEncode(draft.toJson()) != jsonEncode(widget.task.toJson())) ||
      richDirty ||
      creatingProject && project.text.isNotEmpty;
  Future<void> close() async {
    if (saving) return;
    if (dirty && !await confirm(context, '放弃未保存的更改？', '当前输入和附件尚未保存。', '放弃更改')) {
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<bool> paste() async {
    try {
      final files = await DesktopHost.clipboardFiles();
      if (files.isNotEmpty) {
        await upload(files: files, insert: true);
        return true;
      }
      final image = await DesktopHost.clipboardImage();
      if (image != null) {
        await _insertImage(image);
        return true;
      }
    } catch (e) {
      setState(() => error = SpaceStore.readable(e));
      return true;
    }
    return false;
  }

  Future<void> _insertImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    if (png == null) invalid('图片无法读取');
    final data = png.buffer.asUint8List();
    final selection = rich.selection;
    rich.replaceText(
      selection.start,
      selection.end - selection.start,
      q.BlockEmbed.image(base64Encode(data)),
      TextSelection.collapsed(offset: selection.start + 1),
    );
    rich.replaceText(
      selection.start + 1,
      0,
      '\n',
      TextSelection.collapsed(offset: selection.start + 2),
    );
  }

  Future<void> addAttachments(List<Attachment> files) async {
    final candidate = draft.patch({
      'attachments': [
        ...draft.attachments,
        ...files,
      ].map((a) => a.toJson()).toList(),
    });
    if (candidate.attachments.length > 20 ||
        candidate.attachments.fold<int>(0, (n, a) => n + a.data.length) >
            20 * 1024 * 1024) {
      invalid('每项任务最多20个附件、合计20 MB');
    }
    for (final file in files) {
      file.validate();
    }
    setState(() => draft = candidate);
  }

  Future<void> upload({List<String>? files, bool insert = false}) async {
    try {
      files ??= await DesktopHost.openFiles();
      final batch = <Attachment>[];
      for (final path in files) {
        final file = File(path);
        if (!file.existsSync() || file.lengthSync() > 10 * 1024 * 1024) {
          invalid('附件不存在或超过10 MB');
        }
        final name = path.replaceAll('\\', '/').split('/').last;
        final lower = name.toLowerCase();
        final type = lower.endsWith('.png')
            ? 'public.png'
            : lower.endsWith('.jpg') || lower.endsWith('.jpeg')
            ? 'public.jpeg'
            : lower.endsWith('.tiff')
            ? 'public.tiff'
            : 'public.data';
        final bytes = await file.readAsBytes();
        if (type != 'public.data') {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          frame.image.dispose();
          codec.dispose();
        }
        batch.add(
          Attachment(id: uid(), name: name, typeIdentifier: type, data: bytes),
        );
      }
      await addAttachments(
        insert
            ? batch.where((a) => a.typeIdentifier == 'public.data').toList()
            : batch,
      );
      if (insert) {
        for (final a in batch.where((a) => a.typeIdentifier != 'public.data')) {
          final index = rich.selection.start;
          rich.replaceText(
            index,
            rich.selection.end - index,
            q.BlockEmbed.image(base64Encode(a.data)),
            TextSelection.collapsed(offset: index + 1),
          );
          rich.replaceText(
            index + 1,
            0,
            '\n',
            TextSelection.collapsed(offset: index + 2),
          );
        }
      }
    } catch (e) {
      setState(() => error = SpaceStore.readable(e));
    }
  }

  List<RichRun> runs() {
    return rich.document.toDelta().toJson().map((op) {
      final data = op['insert'], attrs = op['attributes'] as Map? ?? {};
      return data is String
          ? RichRun(
              text: data,
              bold: attrs['bold'] == true,
              underline: attrs['underline'] == true,
            )
          : RichRun(image: base64Decode((data as Map)['image'] as String));
    }).toList();
  }

  Future<void> save() async {
    if (saving) return;
    if (title.text.trim().isEmpty || title.text.length > 100) {
      setState(
        () => titleError = title.text.trim().isEmpty
            ? '请输入任务标题。'
            : '任务标题最多 100 字。',
      );
      titleFocus.requestFocus();
      return;
    }
    setState(() {
      titleError = null;
      saving = true;
    });
    try {
      var result = draft.patch({'title': title.text});
      if (!richFailed && (richDirty || !widget.existing)) {
        final values = runs();
        if (values.isNotEmpty &&
            values.last.image == null &&
            values.last.text.endsWith('\n')) {
          final last = values.removeLast();
          values.add(
            RichRun(
              text: last.text.substring(0, last.text.length - 1),
              bold: last.bold,
              underline: last.underline,
            ),
          );
        }
        final plain = values
            .map((r) => r.image != null ? '\uFFFC' : r.text)
            .join();
        result = result.patch({
          'description': plain,
          'richDescription': base64Encode(FlatRtfd.encode(values)),
        });
      }
      if (result.description.length > 5000) {
        setState(() => titleError = '任务说明最多 5,000 字。');
        return;
      }
      final ok = await s.saveTask(
        result,
        initial: widget.existing ? widget.task : null,
        projectName: creatingProject ? project.text : null,
      );
      if (ok && mounted) {
        Navigator.pop(context);
      } else {
        setState(() => error = s.error);
      }
    } catch (e) {
      setState(() => error = SpaceStore.readable(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    DesktopHost.channel
        .invokeMethod("dirty", {"dirty": false})
        .catchError((_) => null);
    title.removeListener(changed);
    rich.removeListener(changed);
    title.dispose();
    project.dispose();
    rich.dispose();
    editorFocus.dispose();
    titleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        DesktopHost.channel
            .invokeMethod('dirty', {'dirty': dirty})
            .catchError((_) => null);
      }
    });
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) close();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): close,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): save,
          const SingleActivator(LogicalKeyboardKey.enter, control: true): save,
        },
        child: sheetFrame(
          c,
          title: widget.existing ? '任务详情' : '新建任务',
          close: close,
          footer: [
            if (widget.existing)
              SpaceButton(
                height: 32,
                danger: true,
                onPressed: saving
                    ? null
                    : () async {
                        if (await confirm(
                              c,
                              '删除任务',
                              '确定删除“${widget.task.title}”？删除后可撤销。',
                              '删除任务',
                            ) &&
                            await s.deleteTask(draft.id) &&
                            c.mounted) {
                          Navigator.pop(c);
                        }
                      },
                child: const Text('删除任务'),
              ),
            const Spacer(),
            SpaceButton(
              height: 32,
              onPressed: saving ? null : close,
              child: const Text('取消'),
            ),
            const SizedBox(width: 12),
            SpaceButton(
              height: 32,
              primary: true,
              onPressed: saving ? null : save,
              child: Text(widget.existing ? '保存更改' : '创建任务'),
            ),
          ],
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('任务标题 *', style: textStyle(p, bold: true)),
                    const Spacer(),
                    Text(
                      '${title.text.length}/100',
                      style: textStyle(p, size: 12, color: p.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SpaceInput(
                  controller: title,
                  hint: '下一步要做什么？',
                  label: '任务标题',
                  focusNode: titleFocus,
                  invalid: titleError != null,
                  autofocus: true,
                ),
                if (titleError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    titleError!,
                    style: textStyle(p, size: 12, color: p.red),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: field(
                        c,
                        '所属分类',
                        SpaceSelect(
                          value: draft.category,
                          options: categories,
                          label: '所属分类',
                          onChanged: (v) => setState(
                            () => draft = draft.patch({'category': v}),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: field(
                        c,
                        '任务状态',
                        SpaceSelect(
                          value: draft.status,
                          options: {
                            for (final status in s.state.statuses)
                              if (!s.state.disabledStatuses.contains(status) ||
                                  status == draft.status)
                                status: statusName(status),
                          },
                          label: '任务状态',
                          onChanged: (v) =>
                              setState(() => draft = draft.moving(v)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: field(
                        c,
                        '优先级',
                        SpaceSelect(
                          value: draft.priority,
                          options: {
                            for (final e in priorities.entries)
                              e.key: '${e.value}优先级',
                          },
                          label: '优先级',
                          onChanged: (v) => setState(
                            () => draft = draft.patch({'priority': v}),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                field(
                  c,
                  '项目 / 可选',
                  Row(
                    children: [
                      Expanded(
                        child: creatingProject
                            ? SpaceInput(
                                controller: project,
                                hint: '输入项目名称，保存任务时一起新建',
                                label: '新项目名称',
                                onChanged: (_) => setState(() {}),
                              )
                            : SpaceSelect(
                                value: draft.projectID ?? '',
                                options: {
                                  '': '无项目',
                                  for (final project in s.state.projects)
                                    if (!project.disabled ||
                                        project.id == draft.projectID)
                                      project.id:
                                          '${project.name}${project.disabled ? '（已停用）' : ''}',
                                },
                                label: '所属项目',
                                onChanged: (v) => setState(
                                  () => draft = draft.patch({
                                    'projectID': v.isEmpty ? null : v,
                                  }),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      SpaceButton(
                        onPressed: () => setState(() {
                          creatingProject = !creatingProject;
                          project.clear();
                        }),
                        child: Text(creatingProject ? '取消' : '新建'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: field(
                        c,
                        '开始日期 / 可选',
                        DateField(
                          value: draft.startDate ?? '',
                          label: '开始日期',
                          onChanged: (v) => setState(
                            () => draft = draft.patch({
                              'startDate': v.isEmpty ? null : v,
                            }),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: field(
                        c,
                        '截止日期',
                        DateField(
                          value: draft.due,
                          onChanged: (v) =>
                              setState(() => draft = draft.patch({'due': v})),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text('任务说明', style: textStyle(p, bold: true)),
                    const Spacer(),
                    Text(
                      '${rich.document.toPlainText().length - 1}/5,000',
                      style: textStyle(p, size: 12, color: p.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 192,
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: p.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: q.QuillEditor.basic(
                      controller: rich,
                      focusNode: editorFocus,
                      config: q.QuillEditorConfig(
                        padding: const EdgeInsets.all(8),
                        embedBuilders: [_ImageBuilder()],
                        customStyles: q.DefaultStyles(
                          paragraph: q.DefaultTextBlockStyle(
                            textStyle(p),
                            const q.HorizontalSpacing(0, 0),
                            const q.VerticalSpacing(0, 0),
                            const q.VerticalSpacing(0, 0),
                            null,
                          ),
                        ),
                        scrollable: true,
                        autoFocus: false,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SpaceButton(
                      onPressed: upload,
                      child: const Row(
                        children: [
                          SpaceIcon('clip'),
                          SizedBox(width: 8),
                          Text('上传附件'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '粘贴图片仅保存在任务说明中',
                        style: textStyle(p, size: 12, color: p.muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '单个附件≤10 MB，每项任务≤20个、合计≤20 MB',
                  style: textStyle(p, size: 12, color: p.muted),
                ),
                for (final a in draft.attachments) ...[
                  const SizedBox(height: 8),
                  Glass(
                    blur: false,
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => previewAttachment(a),
                          child: SizedBox(
                            width: 96,
                            height: 64,
                            child:
                                a.typeIdentifier == 'public.png' ||
                                    a.typeIdentifier == 'public.jpeg'
                                ? Image.memory(
                                    a.data,
                                    fit: BoxFit.contain,
                                    cacheWidth: 192,
                                    errorBuilder: (c, e, st) =>
                                        const SpaceIcon('file', size: 32),
                                  )
                                : const Center(
                                    child: SpaceIcon('file', size: 32),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.name,
                                style: textStyle(p, size: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${(a.data.length / 1024).toStringAsFixed(1)} KB',
                                style: textStyle(p, size: 12, color: p.muted),
                              ),
                            ],
                          ),
                        ),
                        IconButtonS(
                          'save',
                          '另存附件',
                          onPressed: () async {
                            final path = await DesktopHost.saveFile(a.name);
                            if (path != null) {
                              await File(
                                path,
                              ).writeAsBytes(a.data, flush: true);
                            }
                          },
                        ),
                        IconButtonS(
                          'x',
                          '移除附件',
                          onPressed: () => setState(
                            () => draft = draft.patch({
                              'attachments': draft.attachments
                                  .where((x) => x.id != a.id)
                                  .map((x) => x.toJson())
                                  .toList(),
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (widget.existing) ...[
                  const SizedBox(height: 24),
                  for (final e in {
                    '创建时间': draft.createdAt,
                    '最近更新': draft.updatedAt,
                    if (draft.completedAt != null) '完成时间': draft.completedAt!,
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Text(
                            e.key,
                            style: textStyle(p, size: 12, color: p.muted),
                          ),
                          const Spacer(),
                          Text(
                            validTime(e.value)
                                .toUtc()
                                .add(const Duration(hours: 8))
                                .toString()
                                .substring(0, 19),
                            style: textStyle(p, size: 12, color: p.secondary),
                          ),
                        ],
                      ),
                    ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Text(error!, style: textStyle(p, size: 12, color: p.red)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageBuilder extends q.EmbedBuilder {
  @override
  String get key => 'image';
  @override
  Widget build(BuildContext context, q.EmbedContext embedContext) {
    return RichImagePreview(source: embedContext.node.value.data as String);
  }
}

Future<void> previewAttachment(Attachment a) async {
  final directory = await Directory.systemTemp.createTemp('space-preview-');
  final extension = a.name.contains('.') ? '.${a.name.split('.').last}' : '';
  final file = File('${directory.path}/${uid()}$extension');
  await file.writeAsBytes(a.data);
  await DesktopHost.preview(file.path);
}

Future<void> showFilters(BuildContext c, SpaceStore s) async {
  await anchoredPopup(c, _Filters(store: s), width: 384, height: 518);
}

class _Filters extends StatefulWidget {
  final SpaceStore store;
  const _Filters({required this.store});
  @override
  State<_Filters> createState() => _FiltersState();
}

class _FiltersState extends State<_Filters> {
  late TextEditingController search;
  SpaceStore get s => widget.store;
  @override
  void initState() {
    super.initState();
    search = TextEditingController(text: s.query.text);
    s.addListener(change);
  }

  @override
  void dispose() {
    s.removeListener(change);
    search.dispose();
    super.dispose();
  }

  void change() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    return Glass(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('筛选与排序', style: textStyle(p, size: 16, bold: true)),
          const SizedBox(height: 16),
          SizedBox(
            height: 400,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(4),
              child: Column(
                children: [
                  field(
                    c,
                    '关键词',
                    SpaceInput(
                      controller: search,
                      hint: '搜索任务标题与说明',
                      autofocus: true,
                      onChanged: (v) {
                        s.query.text = v;
                        s.refreshQuery();
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  field(
                    c,
                    '任务状态',
                    SpaceSelect(
                      value: s.query.status ?? '',
                      options: {
                        '': '所有状态',
                        for (final status in s.state.statuses)
                          status:
                              '${statusName(status)}${s.state.disabledStatuses.contains(status) ? '（已停用）' : ''}',
                      },
                      label: '状态',
                      onChanged: (v) {
                        s.query.status = v.isEmpty ? null : v;
                        s.refreshQuery();
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  field(
                    c,
                    '优先级',
                    SpaceSelect(
                      value: s.query.priority ?? '',
                      options: {
                        '': '所有优先级',
                        for (final e in priorities.entries)
                          e.key: '${e.value}优先级',
                      },
                      label: '优先级',
                      onChanged: (v) {
                        s.query.priority = v.isEmpty ? null : v;
                        s.refreshQuery();
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  field(
                    c,
                    '所属分类',
                    SpaceSelect(
                      value: s.query.category ?? '',
                      options: {'': '所有分类', ...categories},
                      label: '分类',
                      onChanged: (v) {
                        s.query.category = v.isEmpty ? null : v;
                        s.refreshQuery();
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  field(
                    c,
                    '截止日期',
                    SpaceSelect(
                      value: s.query.dueFilter,
                      options: const {
                        'all': '所有日期',
                        'today': '今天截止',
                        'overdue': '已逾期',
                        'none': '未设置日期',
                      },
                      label: '截止日期',
                      onChanged: (v) {
                        s.query.dueFilter = v;
                        s.refreshQuery();
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  field(
                    c,
                    '项目',
                    SpaceSelect(
                      value: s.query.projectID ?? '',
                      options: {
                        '': '所有项目',
                        for (final project in s.state.projects)
                          project.id: project.name,
                      },
                      label: '项目筛选',
                      onChanged: (v) {
                        s.query.projectID = v.isEmpty ? null : v;
                        s.refreshQuery();
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  field(
                    c,
                    '排序方式',
                    SpaceSelect(
                      value: s.query.sort,
                      options: const {
                        'due': '截止日期优先',
                        'priority': '优先级由高到低',
                        'created': '最近创建优先',
                      },
                      label: '排序',
                      onChanged: (v) {
                        s.query.sort = v;
                        s.refreshQuery();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '${s.visible.length} 个匹配任务',
                style: textStyle(p, size: 12, color: p.muted),
              ),
              const Spacer(),
              SpaceButton(
                height: 32,
                onPressed: s.query.hasFilters
                    ? () {
                        s.query.clear();
                        search.clear();
                        s.refreshQuery();
                      }
                    : null,
                child: const Text('清除筛选'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showStatuses(BuildContext c, SpaceStore s) async {
  if (s.modal) return;
  s.modal = true;
  s.refreshQuery();
  try {
    await sheet(c, _Statuses(store: s), width: 640, height: 640);
  } finally {
    s.modal = false;
    s.refreshQuery();
  }
}

Future<void> showProjects(BuildContext c, SpaceStore s) async {
  if (s.modal) return;
  s.modal = true;
  s.refreshQuery();
  try {
    await sheet(c, _Projects(store: s), width: 640, height: 560);
  } finally {
    s.modal = false;
    s.refreshQuery();
  }
}

class _Projects extends StatefulWidget {
  final SpaceStore store;
  const _Projects({required this.store});
  @override
  State<_Projects> createState() => _ProjectsState();
}

class _ProjectsState extends State<_Projects> {
  final name = TextEditingController();
  String? editing;
  SpaceStore get s => widget.store;
  @override
  void initState() {
    super.initState();
    s.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(changed);
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    return sheetFrame(
      c,
      title: '项目管理',
      close: () => Navigator.pop(c),
      footer: [
        const Spacer(),
        SpaceButton(
          primary: true,
          height: 32,
          onPressed: () => Navigator.pop(c),
          child: const Text('完成'),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '停用后保留现有任务，创建任务时不再显示该项目。',
              style: textStyle(p, size: 12, color: p.secondary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SpaceInput(
                    controller: name,
                    label: '项目名称',
                    hint: '项目名称，1至60字',
                  ),
                ),
                const SizedBox(width: 12),
                SpaceButton(
                  primary: true,
                  onPressed: s.busy
                      ? null
                      : () async {
                          if (await s.saveProject(name.text, id: editing) &&
                              mounted) {
                            setState(() {
                              name.clear();
                              editing = null;
                            });
                          }
                        },
                  child: Text(editing == null ? '新建' : '保存名称'),
                ),
                if (editing != null)
                  SpaceButton(
                    onPressed: () => setState(() {
                      editing = null;
                      name.clear();
                    }),
                    child: const Text('取消'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (s.state.projects.isEmpty)
              Text('暂无项目，可在上方新建。', style: textStyle(p, color: p.muted)),
            for (final project in s.state.projects) ...[
              Glass(
                blur: false,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SpaceIcon(
                      'folder',
                      color: project.disabled ? p.muted : p.purple,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyle(p, bold: true),
                          ),
                          Text(
                            '${s.state.tasks.where((t) => t.projectID == project.id).length} 项任务${project.disabled ? ' · 已停用' : ''}',
                            style: textStyle(p, size: 12, color: p.muted),
                          ),
                        ],
                      ),
                    ),
                    IconButtonS(
                      'edit',
                      '编辑项目名称：${project.name}',
                      onPressed: s.busy
                          ? null
                          : () => setState(() {
                              editing = project.id;
                              name.text = project.name;
                            }),
                    ),
                    SpaceButton(
                      height: 32,
                      onPressed: s.busy
                          ? null
                          : () => s.toggleProject(project.id),
                      child: Text(project.disabled ? '启用' : '停用'),
                    ),
                    SpaceButton(
                      height: 32,
                      danger: true,
                      onPressed: s.busy
                          ? null
                          : () async {
                              if (await confirm(
                                c,
                                '删除项目',
                                '删除“${project.name}”后，其任务将保留并设为无项目。删除后可撤销。',
                                '删除项目',
                              )) {
                                await s.deleteProject(project.id);
                                if (mounted && editing == project.id) {
                                  setState(() {
                                    editing = null;
                                    name.clear();
                                  });
                                }
                              }
                            },
                      child: const Text('删除'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (s.error != null)
              Text(s.error!, style: textStyle(p, size: 12, color: p.red)),
          ],
        ),
      ),
    );
  }
}

class _Statuses extends StatefulWidget {
  final SpaceStore store;
  const _Statuses({required this.store});
  @override
  State<_Statuses> createState() => _StatusesState();
}

class _StatusesState extends State<_Statuses> {
  final name = TextEditingController();
  SpaceStore get s => widget.store;
  @override
  void initState() {
    super.initState();
    s.addListener(change);
  }

  void change() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(change);
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    return sheetFrame(
      c,
      title: '任务状态管理',
      close: () => Navigator.pop(c),
      footer: [
        const Spacer(),
        SpaceButton(
          primary: true,
          height: 32,
          onPressed: () => Navigator.pop(c),
          child: const Text('完成'),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '新增状态后，看板会自动增加一列。',
              style: textStyle(p, size: 12, color: p.secondary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SpaceInput(
                    controller: name,
                    hint: '新状态名称，1至20字',
                    label: '新状态名称',
                  ),
                ),
                const SizedBox(width: 12),
                SpaceButton(
                  primary: true,
                  onPressed: () async {
                    await s.addStatus(name.text);
                    if (s.error == null) name.clear();
                  },
                  child: const Text('新增状态'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            for (final status in s.state.statuses) ...[
              Glass(
                blur: false,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
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
                      child: Text(
                        statusName(status),
                        style: textStyle(p, bold: true),
                      ),
                    ),
                    Text(
                      '${s.state.tasks.where((t) => t.status == status).length} 项',
                      style: textStyle(p, size: 12, color: p.muted),
                    ),
                    const SizedBox(width: 12),
                    if (builtins.contains(status))
                      Text('内置', style: textStyle(p, size: 12, color: p.muted))
                    else ...[
                      SpaceButton(
                        height: 32,
                        onPressed: () => s.toggleStatus(status),
                        child: Text(
                          s.state.disabledStatuses.contains(status)
                              ? '启用'
                              : '停用',
                        ),
                      ),
                      const SizedBox(width: 8),
                      SpaceButton(
                        height: 32,
                        danger: true,
                        onPressed: () async {
                          String target = s.state.statuses.firstWhere(
                            (x) =>
                                x != status &&
                                !s.state.disabledStatuses.contains(x),
                          );
                          final chosen = await showDialog<String>(
                            context: c,
                            builder: (c) => StatefulBuilder(
                              builder: (c, set) => Dialog(
                                backgroundColor: Colors.transparent,
                                child: SizedBox(
                                  width: 400,
                                  child: Glass(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '迁移后删除${statusName(status)}',
                                          style: textStyle(
                                            p,
                                            size: 16,
                                            bold: true,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          '该状态的全部任务将迁移到所选状态，其他字段保留。',
                                          style: textStyle(p, size: 12),
                                        ),
                                        const SizedBox(height: 16),
                                        SpaceSelect(
                                          value: target,
                                          options: {
                                            for (final v in s.state.statuses)
                                              if (v != status &&
                                                  !s.state.disabledStatuses
                                                      .contains(v))
                                                v: statusName(v),
                                          },
                                          label: '迁移目标',
                                          onChanged: (v) =>
                                              set(() => target = v),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            SpaceButton(
                                              onPressed: () => Navigator.pop(c),
                                              child: const Text('取消'),
                                            ),
                                            SpaceButton(
                                              primary: true,
                                              onPressed: () =>
                                                  Navigator.pop(c, target),
                                              child: const Text('迁移并删除'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                          if (chosen != null) {
                            await s.deleteStatus(status, chosen);
                          }
                        },
                        child: const Text('删除'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (s.error != null)
              Text(s.error!, style: textStyle(p, size: 12, color: p.red)),
          ],
        ),
      ),
    );
  }
}

Future<void> importBackup(BuildContext c, SpaceStore s) async {
  try {
    final path = await DesktopHost.openFile(sqliteOnly: true);
    if (path == null) return;
    final incoming = await s.readBackup(path);
    if (c.mounted &&
        await confirm(
          c,
          '导入SQLite',
          '已校验 ${incoming.tasks.length} 项任务、${incoming.projects.length} 个项目和 ${incoming.statuses.length} 个状态。确认替换当前任务库？当前数据会先保留备份。',
          '替换并恢复',
        )) {
      await s.applyBackup(incoming);
    }
  } catch (e) {
    s.error = SpaceStore.readable(e);
    s.refreshQuery();
  }
}

Future<void> showSettings(BuildContext c, SpaceStore s) async {
  if (s.modal) return;
  s.modal = true;
  s.refreshQuery();
  try {
    await sheet(c, _Settings(store: s), width: 760, height: 760);
  } finally {
    s.modal = false;
    s.refreshQuery();
  }
}

class _Settings extends StatefulWidget {
  final SpaceStore store;
  const _Settings({required this.store});
  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  SpaceStore get s => widget.store;
  @override
  void initState() {
    super.initState();
    s.addListener(change);
  }

  void change() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(change);
    super.dispose();
  }

  Widget section(String title, List<Widget> children) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Glass(
        blur: false,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: textStyle(p, size: 16, bold: true)),
            for (final child in children) ...[
              const SizedBox(height: 12),
              child,
            ],
          ],
        ),
      ),
    );
  }

  Future<void> action(Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      s.error = SpaceStore.readable(e);
      s.refreshQuery();
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    return sheetFrame(
      c,
      title: '数据与设置',
      close: () => Navigator.pop(c),
      footer: [
        Text(
          'Space · Flutter 2.0.2 (3) · 基准 1.6.0 (10)',
          style: textStyle(p, size: 11, color: p.muted),
        ),
        const Spacer(),
        SpaceButton(
          height: 32,
          primary: true,
          onPressed: () => Navigator.pop(c),
          child: const Text('完成'),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            section('界面外观', [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final choice in const {
                    'system': '跟随系统',
                    'light': '浅色',
                    'dark': '深色',
                  }.entries)
                    SpaceButton(
                      selected: s.appearance == choice.key,
                      onPressed: s.busy
                          ? null
                          : () => s.preference('appearance', choice.key),
                      child: Text(choice.value),
                    ),
                ],
              ),
              Text(
                '选择跟随系统后，外观会随系统的浅色或深色设置自动切换。',
                style: textStyle(p, size: 12, color: p.secondary),
              ),
            ]),
            section('备份与恢复', [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SpaceButton(
                    onPressed: s.loaded
                        ? () => action(() async {
                            final path = await DesktopHost.saveFile(
                              'Space备份.sqlite',
                              sqliteOnly: true,
                            );
                            if (path != null) {
                              await s.repository.exportSQLite(path);
                              s.message('SQLite备份已导出');
                            }
                          })
                        : null,
                    child: const Text('导出SQLite'),
                  ),
                  SpaceButton(
                    onPressed: () => importBackup(c, s),
                    child: const Text('导入SQLite'),
                  ),
                  SpaceButton(
                    onPressed: File(s.repository.previous).existsSync()
                        ? () => action(() async {
                            final incoming = await s.repository.readExternal(
                              s.repository.previous,
                            );
                            if (c.mounted &&
                                await confirm(
                                  c,
                                  '恢复上次备份',
                                  '恢复写入前的 ${incoming.tasks.length} 项任务？当前任务库也会先备份。',
                                  '恢复',
                                )) {
                              await s.applyBackup(incoming);
                            }
                          })
                        : null,
                    child: const Text('恢复上次备份'),
                  ),
                  SpaceButton(
                    onPressed: () => DesktopHost.reveal(s.repository.path),
                    child: const Text('打开数据库文件夹'),
                  ),
                ],
              ),
              Text(
                '写入前自动保留space.previous.sqlite。导入会先校验并询问。',
                style: textStyle(p, size: 12, color: p.secondary),
              ),
            ]),
            section('GitHub私有仓库同步', [GitHubSettings(store: s)]),
            section('数据整理', [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SpaceButton(
                    onPressed: () async {
                      if (await confirm(
                        c,
                        '载入演示任务',
                        '将当前任务替换为合成演示数据，可以撤销。',
                        '载入演示任务',
                      )) {
                        await s.commit(
                          demoState().copy(
                            settings: s.state.settings,
                            workspaceID: s.state.workspaceID,
                          ),
                          '已载入演示任务',
                        );
                      }
                    },
                    child: const Text('载入演示任务'),
                  ),
                  SpaceButton(
                    danger: true,
                    onPressed: s.state.tasks.isEmpty
                        ? null
                        : () async {
                            if (await confirm(
                              c,
                              '清空所有任务',
                              '项目和状态保留，可以撤销恢复任务。',
                              '清空所有任务',
                            )) {
                              await s.commit(
                                s.state.copy(tasks: []),
                                '任务已清空，可撤销',
                              );
                            }
                          },
                    child: const Text('清空所有任务'),
                  ),
                ],
              ),
            ]),
            if (s.error != null)
              Text(s.error!, style: textStyle(p, size: 12, color: p.red)),
            if (s.notice != null)
              Text(s.notice!, style: textStyle(p, size: 12, color: p.green)),
          ],
        ),
      ),
    );
  }
}

Future<void> showHelp(BuildContext c, SpaceStore s) async {
  if (s.modal) return;
  s.modal = true;
  s.refreshQuery();
  try {
    final p = Palette.of(c);
    await sheet(
      c,
      Glass(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Mark(),
                const SizedBox(width: 12),
                Text('让每个行动，进入轨道。', style: textStyle(p, size: 20, bold: true)),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              '点击任务标题编辑项目、日期与内容；点击圆圈完成任务。拖动任务跨列移动，拖动列头手柄排序。状态管理支持新增、停用和迁移后删除。悬停按钮可查看功能提示。',
              style: textStyle(p),
            ),
            const SizedBox(height: 24),
            for (final e in {
              '新建任务': '⌘N / Ctrl+N / N',
              '搜索任务': '⌘F / Ctrl+F / /',
              '看板 / 列表': '⌘1 / ⌘2 或 1 / 2',
              '甘特图 / 日历': '⌘3 / ⌘4 或 3 / 4',
              '保存任务': '⌘Return / Ctrl+Return',
              '撤销最近一次任务更改': '⌘Z / Ctrl+Z',
              '数据与设置': '⌘, / Ctrl+,',
              '关闭面板': 'Esc',
            }.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(child: Text(e.key, style: textStyle(p))),
                    Text(
                      e.value,
                      style: textStyle(p, size: 12, color: p.muted),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              '单键快捷键在文本输入时暂停。日期按北京时间计算；未设截止日期时从今天（或开始日期）默认展示5天，不改写任务日期。甘特条中间拖动平移，两端拖动调整时长。',
              style: textStyle(p, size: 12, color: p.secondary),
            ),
            const SizedBox(height: 16),
            Text(
              '任务与设置保存在本地SQLite。可导入或导出SQLite备份，或手动同步到GitHub私有仓库；恢复云端数据前会先备份本地。',
              style: textStyle(p, size: 12, color: p.secondary),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: SpaceButton(
                primary: true,
                onPressed: () => Navigator.pop(c),
                child: const Text('开始使用'),
              ),
            ),
          ],
        ),
      ),
      width: 640,
      height: 700,
    );
  } finally {
    s.modal = false;
    s.refreshQuery();
  }
}
