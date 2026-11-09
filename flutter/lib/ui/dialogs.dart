import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_quill/quill_delta.dart' show Delta;

import '../core/models.dart';
import '../core/releases.dart';
import '../core/richtext.dart';
import '../host.dart';
import '../store.dart';
import 'theme.dart';
import 'controls.dart';
import 'settings_panel.dart';
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
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 200),
  transitionBuilder: (_, animation, _, child) => FadeTransition(
    opacity: animation.drive(CurveTween(curve: spaceCurve)),
    child: child,
  ),
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
              SpaceTitleBar(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle(p, bold: true),
                    ),
                  ),
                  IconButtonS.toolbar('x', '关闭$title', onPressed: close),
                ],
              ),
              Divider(height: 1, color: p.border),
              Expanded(child: body),
              Divider(height: 1, color: p.border),
              SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SpaceEditorSection(
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
                  ],
                ),
                const SizedBox(height: 16),
                SpaceEditorSection(
                  title: '任务属性',
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: field(
                            c,
                            '所属分类',
                            SpaceSelect(
                              value: draft.category,
                              options: s.state.taskCategories,
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
                                  if (!s.state.disabledStatuses.contains(
                                        status,
                                      ) ||
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
                    const SizedBox(height: 12),
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
                                    options: projectChoices(
                                      s.state,
                                      selected: draft.projectID,
                                    ),
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
                    const SizedBox(height: 12),
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
                              onChanged: (v) => setState(
                                () => draft = draft.patch({'due': v}),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SpaceEditorSection(
                  children: [
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
                                    style: textStyle(
                                      p,
                                      size: 12,
                                      color: p.muted,
                                    ),
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
                  ],
                ),
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
  await anchoredPopup(
    c,
    _Filters(store: s),
    width: 384,
    height: 518,
    barrierColor: s.dark
        ? Colors.transparent
        : Colors.black.withValues(alpha: .18),
  );
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
                  for (final spec in [
                    (
                      '任务状态',
                      s.query.statusIDs,
                      {for (final v in s.state.statuses) v: statusName(v)},
                    ),
                    ('优先级', s.query.priorityIDs, priorities),
                    ('所属分类', s.query.categoryIDs, s.state.taskCategories),
                    (
                      '截止日期',
                      s.query.dueFilters,
                      {'today': '今天截止', 'overdue': '已逾期', 'none': '未设置日期'},
                    ),
                    (
                      '项目',
                      s.query.projectIDs,
                      {for (final v in s.state.projects) v.id: v.name},
                    ),
                  ]) ...[
                    field(
                      c,
                      spec.$1,
                      SpaceMultiSelect(
                        values: spec.$2,
                        options: spec.$3,
                        label: spec.$1,
                        onChanged: () {
                          if (spec.$1 == '截止日期') s.query.dueFilter = 'all';
                          s.refreshQuery();
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
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
            key: const ValueKey('filter-footer'),
            children: [
              Expanded(
                child: Text(
                  '${s.visible.length} 个匹配任务',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle(p, size: 12, color: p.muted),
                ),
              ),
              SpaceButton(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: s.saveDefaultFilters,
                child: const Text('设为默认配置', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
              SpaceButton(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: s.resetDefaultFilters,
                child: const Text('重置默认', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
              SpaceButton(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onPressed: s.query.hasFilters
                    ? () {
                        s.query.clear();
                        search.clear();
                        s.refreshQuery();
                      }
                    : null,
                child: const Text('清除筛选', style: TextStyle(fontSize: 12)),
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
    await openProjectEditor(c, s);
  } finally {
    s.modal = false;
    s.refreshQuery();
  }
}

Future<void> openProjectEditor(BuildContext c, SpaceStore s) =>
    sheet(c, _Projects(store: s), width: 640, height: 560);

class _Projects extends StatefulWidget {
  final SpaceStore store;
  const _Projects({required this.store});
  @override
  State<_Projects> createState() => _ProjectsState();
}

class _ProjectsState extends State<_Projects> {
  final name = TextEditingController();
  final nameFocus = FocusNode();
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
    nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    return PopScope(
      canPop: !s.busy,
      child: sheetFrame(
        c,
        title: '项目管理',
        close: () {
          if (!s.busy) Navigator.pop(c);
        },
        footer: [
          const Spacer(),
          SpaceButton(
            primary: true,
            height: 32,
            onPressed: s.busy ? null : () => Navigator.pop(c),
            child: const Text('完成'),
          ),
        ],
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SpaceEditorSection(
                detail: '项目供任务和报销共用。停用后保留已有归属，选择时隐藏。',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SpaceInput(
                          controller: name,
                          focusNode: nameFocus,
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
                                if (await s.saveProject(
                                      name.text,
                                      id: editing,
                                    ) &&
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
                ],
              ),
              const SizedBox(height: 16),
              if (s.state.projects.isEmpty)
                Text('暂无项目，可在上方新建。', style: textStyle(p, color: p.muted)),
              for (final project in s.state.projects) ...[
                SpaceEditorRow(
                  selected: editing == project.id,
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
                          : () {
                              setState(() {
                                editing = project.id;
                                name.text = project.name;
                              });
                              nameFocus.requestFocus();
                            },
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
                                '删除“${project.name}”后，相关任务和发票会保留，项目归属将清空。',
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
                const SizedBox(height: 8),
              ],
              if (s.error != null)
                Text(s.error!, style: textStyle(p, size: 12, color: p.red)),
            ],
          ),
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
  bool categoriesPage = false;
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
      title: '状态与分类管理',
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                SpaceButton(
                  selected: !categoriesPage,
                  onPressed: () => setState(() => categoriesPage = false),
                  child: const Text('任务状态'),
                ),
                const SizedBox(width: 8),
                SpaceButton(
                  selected: categoriesPage,
                  onPressed: () => setState(() => categoriesPage = true),
                  child: const Text('任务分类'),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                alignment: Alignment.topLeft,
                children: [...previous, if (current != null) current],
              ),
              duration: MediaQuery.disableAnimationsOf(c)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              child: categoriesPage
                  ? _CategorySettings(
                      key: const ValueKey('categories'),
                      store: s,
                    )
                  : SingleChildScrollView(
                      key: const ValueKey('statuses'),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SpaceEditorSection(
                            detail: '新增状态后，看板会自动增加一列。',
                            children: [
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
                            ],
                          ),
                          const SizedBox(height: 16),
                          for (final status in s.state.statuses) ...[
                            SpaceEditorRow(
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
                                  Text(
                                    '内置',
                                    style: textStyle(
                                      p,
                                      size: 12,
                                      color: p.muted,
                                    ),
                                  )
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
                                      String target = s.state.statuses
                                          .firstWhere(
                                            (x) =>
                                                x != status &&
                                                !s.state.disabledStatuses
                                                    .contains(x),
                                          );
                                      final chosen = await showDialog<String>(
                                        context: c,
                                        builder: (c) => StatefulBuilder(
                                          builder: (c, set) => Dialog(
                                            backgroundColor: Colors.transparent,
                                            child: SizedBox(
                                              width: 400,
                                              child: Glass(
                                                padding: const EdgeInsets.all(
                                                  24,
                                                ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
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
                                                      style: textStyle(
                                                        p,
                                                        size: 12,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 16),
                                                    SpaceSelect(
                                                      value: target,
                                                      options: {
                                                        for (final v
                                                            in s.state.statuses)
                                                          if (v != status &&
                                                              !s
                                                                  .state
                                                                  .disabledStatuses
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
                                                          onPressed: () =>
                                                              Navigator.pop(c),
                                                          child: const Text(
                                                            '取消',
                                                          ),
                                                        ),
                                                        SpaceButton(
                                                          primary: true,
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                c,
                                                                target,
                                                              ),
                                                          child: const Text(
                                                            '迁移并删除',
                                                          ),
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
                            const SizedBox(height: 8),
                          ],
                          if (s.error != null)
                            Text(
                              s.error!,
                              style: textStyle(p, size: 12, color: p.red),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
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

Future<void> showSettings(
  BuildContext c,
  SpaceStore s, {
  ReleaseChecker? updates,
}) async {
  if (s.modal) return;
  s.modal = true;
  s.refreshQuery();
  try {
    final reduced = MediaQuery.disableAnimationsOf(c);
    await showGeneralDialog<void>(
      context: c,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: reduced
          ? const Duration(milliseconds: 200)
          : spaceDuration,
      pageBuilder: (context, a, b) => Stack(
        children: [
          Positioned.fill(
            child: ModalBarrier(
              color: Colors.black.withValues(
                alpha: Palette.of(context).dark ? .28 : .18,
              ),
              dismissible: true,
              semanticsLabel: '关闭设置',
              onDismiss: () => Navigator.pop(context),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 960,
                height: 640,
                child: Focus(
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.escape) {
                      Navigator.pop(context);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Material(
                    type: MaterialType.transparency,
                    child: SettingsPanel(store: s, updates: updates),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      transitionBuilder: (context, animation, secondary, child) {
        final curve = animation.drive(CurveTween(curve: spaceCurve));
        return FadeTransition(
          opacity: curve,
          child: reduced
              ? child
              : ScaleTransition(
                  scale: Tween<double>(begin: .985, end: 1).animate(curve),
                  child: child,
                ),
        );
      },
    );
  } finally {
    s.modal = false;
    s.refreshQuery();
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

class _CategorySettings extends StatefulWidget {
  final SpaceStore store;
  const _CategorySettings({super.key, required this.store});
  @override
  State<_CategorySettings> createState() => _CategorySettingsState();
}

class _CategorySettingsState extends State<_CategorySettings> {
  final name = TextEditingController();
  final nameFocus = FocusNode();
  String? editing;
  @override
  void dispose() {
    name.dispose();
    nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final s = widget.store, p = Palette.of(c);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SpaceEditorSection(
            detail: '分类可自定义或改名，已有任务会保留所属分类。',
            children: [
              Row(
                children: [
                  Expanded(
                    child: SpaceInput(
                      controller: name,
                      focusNode: nameFocus,
                      label: '分类名称',
                      hint: '分类名称，1至20字',
                    ),
                  ),
                  const SizedBox(width: 12),
                  SpaceButton(
                    primary: true,
                    onPressed: s.busy
                        ? null
                        : () async {
                            await s.saveCategory(name.text, id: editing);
                            if (s.error == null && mounted) {
                              setState(() {
                                name.clear();
                                editing = null;
                              });
                            }
                          },
                    child: Text(editing == null ? '新增分类' : '保存分类'),
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
            ],
          ),
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(s.error!, style: textStyle(p, color: p.red)),
            ),
          const SizedBox(height: 16),
          for (final e in s.state.taskCategories.entries) ...[
            SpaceEditorRow(
              selected: editing == e.key,
              children: [
                Expanded(child: CategoryLabel(e.key, name: e.value)),
                Text(
                  '${s.state.tasks.where((t) => t.category == e.key).length} 项',
                  style: textStyle(p, size: 12, color: p.muted),
                ),
                const SizedBox(width: 12),
                SpaceButton(
                  height: 32,
                  onPressed: () {
                    setState(() {
                      editing = e.key;
                      name.text = e.value;
                    });
                    nameFocus.requestFocus();
                  },
                  child: const Text('编辑'),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
