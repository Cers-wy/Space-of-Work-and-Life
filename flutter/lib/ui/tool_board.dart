import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/drive.dart';
import '../core/tool_board.dart';
import '../host.dart';
import '../store.dart';
import 'controls.dart';
import 'dialogs.dart';
import 'file_drive.dart';
import 'theme.dart';

class ToolBoard extends StatefulWidget {
  final SpaceStore store;
  final DriveService drive;
  final bool editing;
  final Widget illustration;
  final VoidCallback openMerge, uploads, files;
  const ToolBoard({
    super.key,
    required this.store,
    required this.drive,
    required this.editing,
    required this.illustration,
    required this.openMerge,
    required this.uploads,
    required this.files,
  });
  @override
  State<ToolBoard> createState() => ToolBoardState();
}

class ToolBoardState extends State<ToolBoard> {
  List<ToolModule> modules = [];
  String? error;
  bool saving = false;
  ToolModule? resizing;
  Offset drag = Offset.zero;
  @override
  void initState() {
    super.initState();
    try {
      modules = decodeToolBoard(widget.store.state.settings);
    } catch (_) {
      error = '工具配置无法读取，原配置已保留。';
    }
  }

  Future<bool> save(List<ToolModule> next) async {
    if (saving) return false;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final ok = await widget.store.preferences(
        encodeToolBoard(next, widget.store.state.settings),
      );
      if (!mounted) return ok;
      setState(() {
        if (ok) {
          modules = next;
        } else {
          error = widget.store.error ?? '工具配置未保存，请重试。';
        }
      });
      return ok;
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '工具配置未保存，请重试。',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<bool> replace(ToolModule module) => save([
    for (final m in modules)
      if (m.id == module.id) module else m,
  ]);

  Future<void> addModule() async {
    final m = await editToolModule(context);
    if (m != null && mounted) await save([...modules, m]);
  }

  Future<void> hiddenModules() async {
    await sheet<void>(
      context,
      StatefulBuilder(
        builder: (c, set) => sheetFrame(
          c,
          title: '隐藏的模块',
          close: () => Navigator.pop(c),
          body: ListView(
            children: [
              if (!modules.any((m) => m.hidden))
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('没有隐藏的模块', style: textStyle(Palette.of(c))),
                ),
              for (final m in modules.where((m) => m.hidden))
                ListTile(
                  title: Text(m.name),
                  trailing: SpaceButton.form(
                    '恢复',
                    onPressed: saving
                        ? null
                        : () async {
                            await replace(m.copy(hidden: false));
                            if (c.mounted) set(() {});
                          },
                  ),
                ),
            ],
          ),
          footer: [],
        ),
      ),
      width: 440,
      height: 440,
    );
  }

  Future<void> menu(BuildContext anchor, ToolModule module) async {
    final action = await anchoredPopup<String>(
      anchor,
      Builder(
        builder: (c) => PopupSurface(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final option in [
                ('add', '添加小工具'),
                ('edit', '编辑模块与工具'),
                ('hide', '隐藏模块'),
                ('delete', '删除模块'),
              ])
                SpaceButton(
                  height: 40,
                  danger: option.$1 == 'delete',
                  onPressed: () => Navigator.pop(c, option.$1),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(option.$2),
                  ),
                ),
            ],
          ),
        ),
      ),
      width: 200,
      height: 180,
      barrierColor: Colors.transparent,
    );
    if (!mounted) return;
    switch (action) {
      case 'add':
        final link = await editToolLink(context);
        if (link != null && mounted) {
          await replace(module.copy(tools: [...module.tools, link]));
        }
      case 'edit':
        final edited = await editToolModule(context, initial: module);
        if (edited != null && mounted) await replace(edited);
      case 'hide':
        await replace(module.copy(hidden: true));
      case 'delete':
        if (await confirm(
          context,
          '删除${module.name}？',
          '只移除本模块与工具入口，不删除本地文件或应用。内置功能可重新添加。',
          '删除',
          destructive: true,
        )) {
          await save(modules.where((m) => m.id != module.id).toList());
        }
    }
  }

  Future<void> openLink(ToolModule m, ToolLink link) async {
    try {
      link.validate();
      if (link.kind == 'local' &&
          !await FileSystemEntity.isFile(link.target) &&
          !await Directory(link.target).exists()) {
        throw const FormatException('本地入口已移动或不存在，请重新选择。');
      }
      if (!await DesktopHost.openTool(link.target, web: link.kind == 'web')) {
        throw const FormatException('无法打开工具，请检查入口或重新选择。');
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => error = e is FormatException ? e.message : '无法打开工具，请检查入口。',
      );
      if (await confirm(context, '工具入口不可用', error!, '重新选择')) {
        if (!mounted) return;
        final edited = await editToolLink(context, initial: link);
        if (edited != null) {
          await replace(
            m.copy(
              tools: [
                for (final t in m.tools)
                  if (t.id == link.id) edited else t,
              ],
            ),
          );
        }
      }
    }
  }

  void openModule(ToolModule m) {
    if (widget.editing || saving) return;
    final selected = m.tools.where((t) => t.id == m.defaultTool).firstOrNull;
    if (selected != null) {
      openLink(m, selected);
      return;
    }
    if (m.builtin == 'merge') {
      widget.openMerge();
      return;
    }
    if (m.builtin == 'drive') {
      widget.files();
      return;
    }
    if (m.tools.isNotEmpty) {
      openLink(m, m.tools.first);
      return;
    }
    editEmpty(m);
  }

  Future<void> editEmpty(ToolModule m) async {
    final link = await editToolLink(context);
    if (link != null && mounted) await replace(m.copy(tools: [link]));
  }

  Widget links(ToolModule m) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final t in m.tools)
        SpaceButton(
          height: 40,
          onPressed: widget.editing ? null : () => openLink(m, t),
          tooltip: '${t.name}\n${t.target}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              toolIcon(t.svg, 'tools', context),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ],
  );
  Widget menuButton(ToolModule m) => Builder(
    builder: (c) => IconButtonS(
      'more',
      '管理${m.name}',
      onPressed: saving ? null : () => menu(c, m),
    ),
  );
  Widget card(ToolModule m) {
    final p = Palette.of(context);
    if (m.builtin == 'drive') {
      return DriveToolCard(
        service: widget.drive,
        title: m.name,
        leading: toolIcon(m.svg, 'folder', context),
        trailing: menuButton(m),
        footer: m.tools.isEmpty
            ? null
            : SizedBox(
                height: 80,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 8),
                  child: links(m),
                ),
              ),
        uploads: widget.uploads,
        files: widget.files,
        onUpload: () => chooseDriveFiles(
          context,
          widget.drive,
          () => showSettings(context, widget.store, initialCategory: 'drive'),
        ),
        onDrop: (paths) => addDriveFiles(
          context,
          widget.drive,
          paths,
          () => showSettings(context, widget.store, initialCategory: 'drive'),
        ),
      );
    }
    return Glass(
      card: true,
      blur: false,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              toolIcon(
                m.svg,
                m.builtin == 'merge' ? 'invoice' : 'tools',
                context,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle(p, bold: true),
                ),
              ),
              menuButton(m),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (m.builtin == 'merge')
                    SizedBox(
                      height: 172,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 12),
                                Text(
                                  '发票合并',
                                  style: textStyle(p, size: 20, bold: true),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '自动裁去票面留白，将多张电子发票排到同一张 A4 纸上。',
                                  style: textStyle(p, color: p.secondary),
                                ),
                                const Spacer(),
                                IconButtonS(
                                  'right',
                                  '打开发票合并',
                                  primary: true,
                                  onPressed: widget.editing
                                      ? null
                                      : widget.openMerge,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: widget.illustration),
                        ],
                      ),
                    ),
                  if (m.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        m.description,
                        style: textStyle(p, color: p.secondary),
                      ),
                    ),
                  if (m.tools.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: links(m),
                    ),
                  if (m.builtin.isEmpty && m.tools.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '点击添加常用工具入口',
                        style: textStyle(p, color: p.muted),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = modules.where((m) => !m.hidden).toList();
    return Column(
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error!,
              style: textStyle(
                Palette.of(context),
                color: Palette.of(context).red,
              ),
            ),
          ),
        if (widget.editing)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '拖动卡片右下角调整宽高，完成后保存布局。窄窗口仅调整高度。',
              style: textStyle(
                Palette.of(context),
                color: Palette.of(context).muted,
              ),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (c, box) {
              final width = math.max(1.0, box.maxWidth - 48);
              final layout = toolBoardLayout(visible, width);
              final height = layout.fold<double>(
                0,
                (h, r) => math.max(h, r.y + r.height),
              );
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: visible.isEmpty
                    ? Center(
                        child: SpaceButton.form('添加模块', onPressed: addModule),
                      )
                    : SizedBox(
                        height: height,
                        child: Stack(
                          children: [
                            for (var i = 0; i < visible.length; i++)
                              Positioned(
                                key: ValueKey('module-${visible[i].id}'),
                                left: layout[i].x,
                                top: layout[i].y,
                                width: layout[i].width,
                                height: layout[i].height,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Semantics(
                                        button: true,
                                        label: '打开${visible[i].name}',
                                        child: InkWell(
                                          onTap: widget.editing
                                              ? null
                                              : () => openModule(visible[i]),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: card(visible[i]),
                                        ),
                                      ),
                                    ),
                                    if (widget.editing)
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Tooltip(
                                          message: '拖动调整${visible[i].name}宽高',
                                          child: Semantics(
                                            label: '调整${visible[i].name}宽高',
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors
                                                  .resizeUpLeftDownRight,
                                              child: GestureDetector(
                                                key: ValueKey(
                                                  'resize-${visible[i].id}',
                                                ),
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onPanStart: saving
                                                    ? null
                                                    : (_) {
                                                        resizing = visible[i];
                                                        drag = Offset.zero;
                                                      },
                                                onPanUpdate: saving
                                                    ? null
                                                    : (details) {
                                                        if (resizing == null) {
                                                          return;
                                                        }
                                                        drag += details.delta;
                                                        final start = resizing!;
                                                        final span = width < 640
                                                            ? start.span
                                                            : (start.span +
                                                                      drag.dx /
                                                                          ((width +
                                                                                  12) /
                                                                              12))
                                                                  .round()
                                                                  .clamp(
                                                                    start
                                                                        .minSpan,
                                                                    12,
                                                                  );
                                                        final resized = start.copy(
                                                          span: span,
                                                          height:
                                                              (start.height +
                                                                      drag.dy)
                                                                  .clamp(
                                                                    start
                                                                        .minHeight,
                                                                    800,
                                                                  ),
                                                        );
                                                        setState(() {
                                                          modules = [
                                                            for (final m
                                                                in modules)
                                                              if (m.id ==
                                                                  start.id)
                                                                resized
                                                              else
                                                                m,
                                                          ];
                                                        });
                                                      },
                                                onPanEnd: saving
                                                    ? null
                                                    : (_) async {
                                                        final original =
                                                            resizing;
                                                        resizing = null;
                                                        if (!await save([
                                                              ...modules,
                                                            ]) &&
                                                            original != null &&
                                                            mounted) {
                                                          setState(() {
                                                            modules = [
                                                              for (final m
                                                                  in modules)
                                                                if (m.id ==
                                                                    original.id)
                                                                  original
                                                                else
                                                                  m,
                                                            ];
                                                          });
                                                        }
                                                      },
                                                onPanCancel: () {
                                                  final original = resizing;
                                                  resizing = null;
                                                  if (original != null) {
                                                    setState(() {
                                                      modules = [
                                                        for (final m in modules)
                                                          if (m.id ==
                                                              original.id)
                                                            original
                                                          else
                                                            m,
                                                      ];
                                                    });
                                                  }
                                                },
                                                child: SizedBox(
                                                  width: 32,
                                                  height: 32,
                                                  child: Center(
                                                    child: SpaceIcon(
                                                      'resize',
                                                      size: 16,
                                                      color: Palette.of(c)
                                                          .accent,
                                                    ),
                                                  ),
                                                ),
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
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

Widget toolIcon(String svg, String fallback, BuildContext context) =>
    svg.isEmpty
    ? SpaceIcon(fallback, size: 20, color: Palette.of(context).accent)
    : SvgPicture.string(svg, width: 20, height: 20);

Future<String?> chooseToolSvg() async {
  final file = await DesktopHost.openFile(
    title: '选择 SVG 图标',
    extensions: ['svg'],
  );
  if (file == null) return null;
  final source = File(file);
  if (await source.length() > 128 * 1024) {
    throw const FormatException('SVG 图标不能超过 128 KB');
  }
  return validateToolSvg(await source.readAsString());
}

Future<ToolLink?> editToolLink(
  BuildContext context, {
  ToolLink? initial,
}) async {
  final name = TextEditingController(text: initial?.name);
  final target = TextEditingController(text: initial?.target);
  var kind = initial?.kind ?? 'web', svg = initial?.svg ?? '';
  String? error;
  return sheet<ToolLink>(
    context,
    _ToolFormLifetime(
      controllers: [name, target],
      child: StatefulBuilder(
        builder: (c, set) => sheetFrame(
          c,
          title: initial == null ? '添加小工具' : '编辑小工具',
          close: () => Navigator.pop(c),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              field(c, '工具名称', SpaceInput(controller: name, hint: '工具名称')),
              const SizedBox(height: 16),
              field(
                c,
                '打开方式',
                SpaceSelect(
                  value: kind,
                  label: '打开方式',
                  options: const {'web': '浏览器网页', 'local': '本地 HTML 或应用'},
                  onChanged: (v) => set(() => kind = v),
                ),
              ),
              const SizedBox(height: 16),
              field(
                c,
                '工具入口',
                SpaceInput(
                  controller: target,
                  hint: kind == 'web' ? 'https://' : '文件或应用完整路径',
                ),
              ),
              if (kind == 'local')
                SpaceButton.form(
                  '选择本地入口',
                  onPressed: () async {
                    final path = await DesktopHost.openFile(
                      title: '选择 HTML 或应用',
                    );
                    if (path != null) target.text = path;
                  },
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  toolIcon(svg, 'tools', c),
                  const SizedBox(width: 8),
                  SpaceButton.form(
                    '上传 SVG',
                    onPressed: () async {
                      try {
                        final value = await chooseToolSvg();
                        if (value != null && c.mounted) {
                          set(() {
                            svg = value;
                            error = null;
                          });
                        }
                      } catch (_) {
                        if (c.mounted) {
                          set(() => error = 'SVG 无效，请选择独立的矢量图标（不超过 128 KB）。');
                        }
                      }
                    },
                  ),
                  if (svg.isNotEmpty)
                    IconButtonS(
                      'x',
                      '移除图标',
                      onPressed: () => set(() => svg = ''),
                    ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: textStyle(Palette.of(c), color: Palette.of(c).red),
                  ),
                ),
            ],
          ),
          footer: [
            SpaceButton.form('取消', onPressed: () => Navigator.pop(c)),
            const SizedBox(width: 8),
            SpaceButton.form(
              '保存',
              primary: true,
              onPressed: () {
                try {
                  final link = ToolLink(
                    id:
                        initial?.id ??
                        ToolLink.create(name: '', kind: kind, target: '').id,
                    name: name.text.trim(),
                    kind: kind,
                    target: target.text.trim(),
                    svg: svg,
                  );
                  link.validate();
                  Navigator.pop(c, link);
                } catch (e) {
                  set(
                    () => error = e is FormatException ? e.message : '工具入口无效',
                  );
                }
              },
            ),
          ],
        ),
      ),
    ),
    width: 520,
    height: 540,
  );
}

Future<ToolModule?> editToolModule(
  BuildContext context, {
  ToolModule? initial,
}) async {
  final name = TextEditingController(text: initial?.name);
  final description = TextEditingController(text: initial?.description);
  var builtin = initial?.builtin ?? '',
      svg = initial?.svg ?? '',
      defaultTool = initial?.defaultTool ?? '';
  var tools = [...?initial?.tools];
  String? error;
  return sheet<ToolModule>(
    context,
    _ToolFormLifetime(
      controllers: [name, description],
      child: StatefulBuilder(
        builder: (c, set) => sheetFrame(
          c,
          title: initial == null ? '添加模块' : '编辑模块与工具',
          close: () => Navigator.pop(c),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              field(c, '模块名称', SpaceInput(controller: name, hint: '模块名称')),
              const SizedBox(height: 16),
              field(c, '说明', SpaceInput(controller: description, hint: '可选')),
              const SizedBox(height: 16),
              if (initial == null) ...[
                field(
                  c,
                  '模块类型',
                  SpaceSelect(
                    value: builtin,
                    label: '模块类型',
                    options: const {
                      '': '自定义工具',
                      'merge': '内置发票合并',
                      'drive': '内置文件管理',
                    },
                    onChanged: (v) => set(() => builtin = v),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  toolIcon(svg, 'tools', c),
                  const SizedBox(width: 8),
                  SpaceButton.form(
                    '上传 SVG',
                    onPressed: () async {
                      try {
                        final value = await chooseToolSvg();
                        if (value != null && c.mounted) {
                          set(() {
                            svg = value;
                            error = null;
                          });
                        }
                      } catch (_) {
                        if (c.mounted) {
                          set(() => error = 'SVG 无效，请选择独立的矢量图标（不超过 128 KB）。');
                        }
                      }
                    },
                  ),
                  if (svg.isNotEmpty)
                    IconButtonS(
                      'x',
                      '移除图标',
                      onPressed: () => set(() => svg = ''),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              field(
                c,
                '卡片默认入口',
                SpaceSelect(
                  value: defaultTool,
                  label: '默认入口',
                  options: {
                    '': builtin.isEmpty ? '第一个小工具' : '内置功能',
                    for (final t in tools) t.id: t.name,
                  },
                  onChanged: (v) => set(() => defaultTool = v),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '小工具',
                      style: textStyle(Palette.of(c), bold: true),
                    ),
                  ),
                  IconButtonS(
                    'plus',
                    '添加小工具',
                    onPressed: () async {
                      final link = await editToolLink(c);
                      if (link != null && c.mounted) set(() => tools.add(link));
                    },
                  ),
                ],
              ),
              for (final t in tools)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButtonS(
                      'edit',
                      '编辑${t.name}',
                      onPressed: () async {
                        final link = await editToolLink(c, initial: t);
                        if (link != null && c.mounted) {
                          set(
                            () => tools = [
                              for (final old in tools)
                                if (old.id == t.id) link else old,
                            ],
                          );
                        }
                      },
                    ),
                    IconButtonS(
                      'trash',
                      '移除${t.name}',
                      onPressed: () async {
                        if (await confirm(
                              c,
                              '移除${t.name}？',
                              '只移除工具入口，不删除本地文件。',
                              '移除',
                              destructive: true,
                            ) &&
                            c.mounted) {
                          set(() {
                            tools.removeWhere((old) => old.id == t.id);
                            if (defaultTool == t.id) defaultTool = '';
                          });
                        }
                      },
                    ),
                  ],
                ),
              if (error != null)
                Text(
                  error!,
                  style: textStyle(Palette.of(c), color: Palette.of(c).red),
                ),
            ],
          ),
          footer: [
            SpaceButton.form('取消', onPressed: () => Navigator.pop(c)),
            const SizedBox(width: 8),
            SpaceButton.form(
              '保存',
              primary: true,
              onPressed: () {
                if (name.text.trim().isEmpty ||
                    name.text.trim().length > 60 ||
                    description.text.length > 240) {
                  set(() => error = '模块名称为 1 至 60 字，说明最多 240 字。');
                  return;
                }
                final m =
                    (initial ??
                            ToolModule.create(
                              name.text,
                              description.text,
                              builtin: builtin,
                            ))
                        .copy(
                          name: name.text.trim(),
                          description: description.text.trim(),
                          svg: svg,
                          tools: tools,
                          defaultTool: defaultTool,
                        );
                Navigator.pop(
                  c,
                  m.copy(height: math.max(m.height, m.minHeight)),
                );
              },
            ),
          ],
        ),
      ),
    ),
    width: 560,
    height: 660,
  );
}

class _ToolFormLifetime extends StatefulWidget {
  final List<TextEditingController> controllers;
  final Widget child;
  const _ToolFormLifetime({required this.controllers, required this.child});
  @override
  State<_ToolFormLifetime> createState() => _ToolFormLifetimeState();
}

class _ToolFormLifetimeState extends State<_ToolFormLifetime> {
  @override
  Widget build(BuildContext context) => widget.child;
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
