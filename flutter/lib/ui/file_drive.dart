import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../core/drive.dart';
import '../core/drive_query.dart';
import '../store.dart';
import '../host.dart';
import 'controls.dart';
import 'dialogs.dart';
import 'theme.dart';

String driveSize(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
    : bytes >= 1024
    ? '${(bytes / 1024).toStringAsFixed(0)} KB'
    : '$bytes B';
String driveTime(DateTime? date) {
  if (date == null) return '—';
  final d = date.toLocal();
  String n(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${n(d.month)}-${n(d.day)} ${n(d.hour)}:${n(d.minute)}';
}

class DriveToolCard extends StatelessWidget {
  final DriveService service;
  final VoidCallback uploads, files;
  final VoidCallback? onUpload;
  final Future<void> Function(List<String>)? onDrop;
  const DriveToolCard({
    super.key,
    required this.service,
    required this.uploads,
    required this.files,
    this.onUpload,
    this.onDrop,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final p = Palette.of(context);
      final batch = service.tasks
          .where((t) => t.batch == service.activeBatch)
          .toList();
      final done = batch.where((t) => t.status == UploadStatus.complete).length;
      final failed = batch.where((t) => t.status == UploadStatus.failed).length;
      final ordered = [...batch]
        ..sort((a, b) {
          int priority(UploadTask t) => switch (t.status) {
            UploadStatus.uploading || UploadStatus.committing => 0,
            UploadStatus.failed => 1,
            UploadStatus.waiting => 2,
            _ => 3,
          };
          return priority(a).compareTo(priority(b));
        });
      final card = Glass(
        card: true,
        blur: false,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SpaceIcon('folder', size: 20, color: p.muted),
                const SizedBox(width: 8),
                Text('文件管理', style: textStyle(p, bold: true)),
                const Spacer(),
                IconButtonS('upload', '上传文件', onPressed: onUpload ?? uploads),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    service.scanning
                        ? '正在扫描，已发现 ${service.discovered} 项'
                        : service.active
                        ? '文件正在后台上传'
                        : batch.isEmpty
                        ? '拖入文件或文件夹，开始上传'
                        : failed > 0
                        ? '部分文件上传失败'
                        : '上传记录',
                    style: textStyle(p, size: 12, color: p.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$done / ${batch.length} 已完成${failed > 0 ? ' · $failed 项失败' : ''}',
                  style: textStyle(p, size: 12, color: p.accent),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  if (batch.isEmpty) {
                    return Center(
                      child: Text(
                        '暂无上传任务',
                        style: textStyle(p, size: 12, color: p.muted),
                      ),
                    );
                  }
                  final n = math.max(0, (box.maxHeight / 32).floor());
                  return Column(
                    children: [
                      for (final t in ordered.take(n))
                        SizedBox(
                          height: 32,
                          child: SpaceButton(
                            height: 32,
                            padding: EdgeInsets.zero,
                            onPressed: files,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textStyle(p, size: 12),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 88,
                                  child: LinearProgressIndicator(
                                    value: t.status == UploadStatus.complete
                                        ? 1
                                        : t.progress,
                                    minHeight: 3,
                                    color: t.status == UploadStatus.failed
                                        ? p.red
                                        : p.accent,
                                    backgroundColor: p.hover,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 40,
                                  child: Text(
                                    t.status == UploadStatus.uploading
                                        ? '${(t.progress * 100).floor()}%'
                                        : t.status == UploadStatus.committing
                                        ? '提交中'
                                        : t.status.label,
                                    style: textStyle(
                                      p,
                                      size: 10,
                                      color: t.status == UploadStatus.failed
                                          ? p.red
                                          : p.muted,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Row(
              children: [
                IconButtonS('right', '进入文件管理', primary: true, onPressed: files),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '上传后，可在其他电脑查看与下载。',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(p, size: 12, color: p.muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      return _DriveDropCard(open: files, add: onDrop, child: card);
    },
  );
}

class _DriveDropCard extends StatefulWidget {
  final Widget child;
  final VoidCallback open;
  final Future<void> Function(List<String>)? add;
  const _DriveDropCard({required this.child, required this.open, this.add});
  @override
  State<_DriveDropCard> createState() => _DriveDropCardState();
}

class _DriveDropCardState extends State<_DriveDropCard> {
  bool dragging = false, hover = false, focus = false;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return DropTarget(
      onDragEntered: (_) => setState(() => dragging = true),
      onDragExited: (_) => setState(() => dragging = false),
      onDragDone: (details) async {
        setState(() => dragging = false);
        await widget.add?.call(details.files.map((f) => f.path).toList());
      },
      child: FocusableActionDetector(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.open();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (v) => setState(() => focus = v),
        onShowHoverHighlight: (v) => setState(() => hover = v),
        child: Semantics(
          button: true,
          label: '打开文件管理，可拖入文件或文件夹上传',
          child: GestureDetector(
            onTap: widget.open,
            behavior: HitTestBehavior.opaque,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : spaceDuration,
                curve: spaceCurve,
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: dragging || focus
                        ? p.accent
                        : hover
                        ? p.accent.withValues(alpha: .3)
                        : Colors.transparent,
                  ),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> addDriveFiles(
  BuildContext context,
  DriveService service,
  List<String> paths,
  Future<void> Function() settings,
) async {
  try {
    if (!service.config.ready || service.token.isEmpty) {
      await settings();
      if (!service.config.ready || service.token.isEmpty) return;
    }
    await service.add(paths);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(driveError(e))));
    }
  }
}

Future<void> chooseDriveFiles(
  BuildContext context,
  DriveService service,
  Future<void> Function() settings, {
  bool folder = false,
}) async {
  if (!service.config.ready || service.token.isEmpty) {
    await settings();
    if (!context.mounted || !service.config.ready || service.token.isEmpty) {
      return;
    }
  }
  final paths = folder
      ? [await DesktopHost.channel.invokeMethod<String>('openFolder')]
            .whereType<String>()
            .toList()
      : await DesktopHost.openFiles(title: '上传文件', multiple: true);
  if (paths.isNotEmpty && context.mounted) {
    await addDriveFiles(context, service, paths, settings);
  }
}

class _DriveFilters extends StatefulWidget {
  final DriveFileFilter filter;
  final int Function() count;
  const _DriveFilters({required this.filter, required this.count});
  @override
  State<_DriveFilters> createState() => _DriveFiltersState();
}

class _DriveFiltersState extends State<_DriveFilters> {
  late final search = TextEditingController(text: widget.filter.query);
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.filter,
    builder: (context, _) {
      final p = Palette.of(context), f = widget.filter;
      return Glass(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('筛选文件', style: textStyle(p, size: 16, bold: true)),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(4),
                child: Column(
                  children: [
                    field(
                      context,
                      '文件名称',
                      SpaceInput(
                        controller: search,
                        hint: '搜索当前目录的文件名称',
                        autofocus: true,
                        onChanged: (v) {
                          f.query = v;
                          f.changed();
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    field(
                      context,
                      '创建日期',
                      DateField(
                        value: f.date,
                        label: '创建日期',
                        matchFieldWidth: true,
                        onChanged: (v) {
                          f.date = v;
                          f.changed();
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    field(
                      context,
                      '文件类型',
                      SpaceMultiSelect(
                        values: f.types,
                        options: driveFileTypes,
                        label: '文件类型',
                        matchFieldWidth: true,
                        onChanged: f.changed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.count()} 个匹配项',
                    style: textStyle(p, size: 12, color: p.muted),
                  ),
                ),
                SpaceButton(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onPressed: !f.active
                      ? null
                      : () {
                          search.clear();
                          f.clear();
                        },
                  child: const Text('清除筛选', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class DrivePage extends StatefulWidget {
  final SpaceStore store;
  final DriveService service;
  final bool initialUploads;
  final Widget Function(List<Widget>) titleBuilder;
  const DrivePage({
    super.key,
    required this.store,
    required this.service,
    required this.titleBuilder,
    this.initialUploads = false,
  });
  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage> with WidgetsBindingObserver {
  DriveService get service => widget.service;
  Timer? timer;
  List<DriveFile> files = [];
  bool loading = false;
  int listingGeneration = 0;
  String filter = '全部', folder = '', notice = '';
  final fileFilter = DriveFileFilter();
  final filterAnchor = GlobalKey();
  final cloudScroll = ScrollController(), uploadScroll = ScrollController();
  late bool cloud = !widget.initialUploads;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fileFilter.addListener(filtersChanged);
    {
      if (cloud) refresh();
      timer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed &&
            cloud) {
          refresh();
        }
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    fileFilter.dispose();
    cloudScroll.dispose();
    uploadScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && cloud) refresh();
  }

  Future<void> run(Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => notice = driveError(e));
    }
  }

  Future<void> refresh() async {
    if (loading || !service.config.ready || service.token.isEmpty) return;
    final generation = ++listingGeneration;
    setState(() => loading = true);
    try {
      final value = await service.list();
      if (mounted && generation == listingGeneration) {
        setState(() {
          files = value;
          notice = '';
        });
      }
    } catch (e) {
      if (mounted && generation == listingGeneration) {
        setState(() => notice = driveError(e));
      }
    } finally {
      if (mounted && generation == listingGeneration) {
        setState(() => loading = false);
      }
    }
  }

  void filtersChanged() {
    if (mounted) setState(() {});
  }

  Future<void> settings() async {
    final before =
        '${service.config.owner}/${service.config.repository}/${service.config.branch}';
    await showSettings(context, widget.store, initialCategory: 'drive');
    if (!mounted) return;
    final after =
        '${service.config.owner}/${service.config.repository}/${service.config.branch}';
    if (before != after) {
      setState(() {
        listingGeneration++;
        loading = false;
        folder = '';
        files = [];
      });
    }
    if (cloud) await refresh();
  }

  Future<void> choose({bool folder = false}) =>
      run(() => chooseDriveFiles(context, service, settings, folder: folder));
  Future<void> showFilters() async {
    if (widget.store.modal) return;
    widget.store.modal = true;
    widget.store.refreshQuery();
    try {
      await anchoredPopup<void>(
        filterAnchor.currentContext!,
        _DriveFilters(filter: fileFilter, count: () => visibleFiles.length),
        width: 384,
        height: 392,
        constrainHeight: true,
        barrierColor: widget.store.dark
            ? Colors.transparent
            : Colors.black.withValues(alpha: .18),
      );
    } finally {
      widget.store.modal = false;
      widget.store.refreshQuery();
    }
  }

  List<Widget> toolbar() {
    Widget action(String icon, String label, VoidCallback? callback) =>
        IconButtonS.toolbar(icon, label, onPressed: callback);
    return [
      if (cloud) ...[
        IconButtonS.toolbar(
          'filter',
          '筛选文件',
          key: filterAnchor,
          selected: fileFilter.active,
          onPressed: showFilters,
        ),
        const SizedBox(width: 8),
        IconButtonS.toolbar(
          'reload',
          '刷新仓库列表',
          onPressed: loading ? null : refresh,
        ),
      ] else ...[
        action('upload', '添加文件', service.scanning ? null : () => choose()),
        action(
          'folder',
          '添加文件夹',
          service.scanning ? null : () => choose(folder: true),
        ),
        action(
          'reload',
          '重试失败',
          !service.tasks.any((t) => t.status == UploadStatus.failed)
              ? null
              : () => run(() async {
                  for (final t
                      in service.tasks
                          .where((t) => t.status == UploadStatus.failed)
                          .toList()) {
                    await service.retry(t);
                  }
                }),
        ),
        action(
          'trash',
          '清除已完成',
          !service.tasks.any((t) => t.status == UploadStatus.complete)
              ? null
              : () => run(() async {
                  for (final t
                      in service.tasks
                          .where((t) => t.status == UploadStatus.complete)
                          .toList()) {
                    await service.remove(t);
                  }
                }),
        ),
      ],
      const SizedBox(width: 8),
      IconButtonS.toolbar('settings', '网盘设置', onPressed: settings),
      const SizedBox(width: 8),
    ];
  }

  Widget text(String s, Palette p, {int flex = 1, bool right = false}) =>
      Expanded(
        flex: flex,
        child: Text(
          s,
          style: textStyle(p, size: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: right ? TextAlign.right : TextAlign.left,
        ),
      );
  Widget uploadRow(UploadTask t, Palette p) => Container(
    constraints: const BoxConstraints(minHeight: 56),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: p.border)),
    ),
    child: Row(
      children: [
        text(t.name, p, flex: 4),
        const SizedBox(width: 12),
        text(driveSize(t.size), p),
        text(path.extension(t.name).replaceFirst('.', '').toUpperCase(), p),
        text(driveTime(t.created), p, flex: 2),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.status.label,
                style: textStyle(
                  p,
                  size: 12,
                  color: t.status == UploadStatus.failed
                      ? p.red
                      : t.status == UploadStatus.complete
                      ? p.green
                      : p.secondary,
                ),
              ),
              if (t.status == UploadStatus.uploading) ...[
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: t.progress,
                  minHeight: 3,
                  color: p.accent,
                  backgroundColor: p.hover,
                ),
                Text(
                  '${(t.progress * 100).floor()}%',
                  style: textStyle(p, size: 10, color: p.muted),
                ),
              ],
              if (t.error.isNotEmpty)
                Tooltip(
                  message: t.error,
                  child: Text(
                    t.error,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(p, size: 10, color: p.red),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          width: 80,
          child: Row(
            children: [
              if (t.status.active)
                IconButtonS(
                  'x',
                  '取消上传',
                  onPressed: () => run(() => service.cancel(t)),
                )
              else ...[
                if (t.status != UploadStatus.complete)
                  IconButtonS(
                    'reload',
                    '重试',
                    onPressed: () => run(() => service.retry(t)),
                  ),
                IconButtonS(
                  'trash',
                  '删除本机记录',
                  onPressed: () => run(() => service.remove(t)),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
  List<DriveFile> get visibleFiles =>
      driveDirectoryFiles(files, folder, fileFilter);

  Future<void> download(DriveFile f, {bool preview = false}) async =>
      run(() async {
        final supported = {'pdf', 'png', 'jpg', 'jpeg', 'txt'};
        if (preview &&
            !supported.contains(
              path.extension(f.name).replaceFirst('.', '').toLowerCase(),
            )) {
          setState(() => notice = '此类型暂不支持内嵌预览，请下载后打开。');
          return;
        }
        if (preview) {
          final result = await service.download(f);
          await DesktopHost.preview(result.path);
        } else {
          final destination = await DesktopHost.saveFile(f.name, title: '下载文件');
          if (destination != null) {
            await service.download(f, destination: destination);
            if (mounted) setState(() => notice = '文件已下载并校验');
          }
        }
      });
  Widget cloudRow(DriveFile f, Palette p) => Container(
    constraints: const BoxConstraints(minHeight: 56),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: p.border)),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 4,
          child: SpaceButton(
            height: 40,
            padding: EdgeInsets.zero,
            onPressed: () => f.folder
                ? setState(() => folder = f.path)
                : download(f, preview: true),
            child: Row(
              children: [
                SpaceIcon(
                  f.folder ? 'folder' : 'file',
                  size: 16,
                  color: p.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    f.name.isEmpty
                        ? f.path.split('/').where((s) => s.isNotEmpty).last
                        : f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(p, size: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        text(driveTime(f.created), p, flex: 2),
        text(f.folder ? '—' : driveSize(f.size), p),
        text(f.device.isEmpty ? '—' : f.device, p, flex: 2),
        SizedBox(
          width: 112,
          child: Row(
            children: [
              if (!f.folder) ...[
                IconButtonS(
                  'preview',
                  '预览',
                  onPressed: () => download(f, preview: true),
                ),
                IconButtonS('save', '下载', onPressed: () => download(f)),
                IconButtonS(
                  'trash',
                  '删除网盘文件',
                  onPressed: () => run(() async {
                    if (await confirm(
                      context,
                      '删除网盘文件？',
                      '${f.name}\n其他设备刷新后将无法再下载。Git历史仍保留。',
                      '删除',
                      destructive: true,
                    )) {
                      await service.delete(f);
                      await refresh();
                    }
                  }),
                ),
              ] else
                IconButtonS(
                  'right',
                  '打开文件夹',
                  onPressed: () => setState(() => folder = f.path),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final p = Palette.of(context);
      final rows = service.tasks
          .where(
            (t) =>
                filter == '全部' ||
                filter == '上传中' && t.status.active ||
                filter == t.status.label,
          )
          .toList()
          .reversed
          .toList();
      final cloudFiles = visibleFiles;
      return LayoutBuilder(
        builder: (context, pageBox) => Column(
          children: [
            widget.titleBuilder(toolbar()),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, box) {
                        final tabs = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final item in [
                              (true, '文件管理'),
                              (false, '上传记录'),
                            ]) ...[
                              SpaceButton(
                                height: 32,
                                selected: cloud == item.$1,
                                soft: true,
                                onPressed: () {
                                  setState(() => cloud = item.$1);
                                  if (cloud) refresh();
                                },
                                child: Text(
                                  item.$2,
                                  style: textStyle(p, size: 12),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                          ],
                        );
                        final path = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SpaceButton(
                              height: 32,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              onPressed: () => setState(() => folder = ''),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SpaceIcon('folder', size: 16, color: p.muted),
                                  const SizedBox(width: 8),
                                  Text(
                                    '根目录',
                                    style: textStyle(
                                      p,
                                      size: 12,
                                      color: p.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (folder.isNotEmpty) ...[
                              SpaceIcon('right', size: 12, color: p.muted),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Tooltip(
                                  message: folder,
                                  child: Text(
                                    folder,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textStyle(
                                      p,
                                      size: 12,
                                      color: p.muted,
                                    ),
                                  ),
                                ),
                              ),
                              IconButtonS(
                                'left',
                                '返回上一级',
                                onPressed: () => setState(() {
                                  final parts =
                                      folder
                                          .split('/')
                                          .where((s) => s.isNotEmpty)
                                          .toList()
                                        ..removeLast();
                                  folder = parts.isEmpty
                                      ? ''
                                      : '${parts.join('/')}/';
                                }),
                              ),
                            ],
                          ],
                        );
                        final statuses = Wrap(
                          spacing: 4,
                          children: [
                            for (final f in ['全部', '上传中', '失败', '已完成'])
                              SpaceButton(
                                height: 28,
                                selected: filter == f,
                                soft: true,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                onPressed: () => setState(() => filter = f),
                                child: Text(f, style: textStyle(p, size: 12)),
                              ),
                          ],
                        );
                        final detail = cloud ? path : statuses;
                        final count = Text(
                          cloud
                              ? '${visibleFiles.length} 项'
                              : '${service.tasks.where((t) => t.status == UploadStatus.complete).length} / ${service.tasks.length} 已完成',
                          style: textStyle(
                            p,
                            size: 12,
                            color: cloud ? p.muted : p.accent,
                          ),
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: box.maxWidth < 640
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [tabs, const Spacer(), count],
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(height: 32, child: detail),
                                  ],
                                )
                              : Row(
                                  children: [
                                    tabs,
                                    const SizedBox(width: 16),
                                    Expanded(child: detail),
                                    const SizedBox(width: 8),
                                    count,
                                  ],
                                ),
                        );
                      },
                    ),
                    if (notice.isNotEmpty || service.message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          notice.isNotEmpty ? notice : service.message,
                          style: textStyle(p, size: 12, color: p.red),
                        ),
                      ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: math.max(1040, box.maxWidth),
                            height: box.maxHeight,
                            child: Column(
                              children: [
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  color: p.hover,
                                  child: Row(
                                    children: cloud
                                        ? [
                                            text('文件名称', p, flex: 4),
                                            text('创建时间', p, flex: 2),
                                            text('大小', p),
                                            text('来源设备', p, flex: 2),
                                            const SizedBox(
                                              width: 112,
                                              child: Text('操作'),
                                            ),
                                          ]
                                        : [
                                            text('文件名称', p, flex: 4),
                                            const SizedBox(width: 12),
                                            text('大小', p),
                                            text('类型', p),
                                            text('时间', p, flex: 2),
                                            text('状态', p, flex: 2),
                                            const SizedBox(
                                              width: 80,
                                              child: Text('操作'),
                                            ),
                                          ],
                                  ),
                                ),
                                Expanded(
                                  child: loading
                                      ? const Center(
                                          child: CircularProgressIndicator(),
                                        )
                                      : (cloud
                                            ? cloudFiles.isEmpty
                                            : rows.isEmpty)
                                      ? Center(
                                          child: Text(
                                            cloud
                                                ? (!service.config.ready ||
                                                          service.token.isEmpty
                                                      ? '尚未连接仓库，请点击右上角设置'
                                                      : fileFilter.active
                                                      ? '没有匹配文件，可在筛选中清除条件'
                                                      : '此目录暂无文件')
                                                : '暂无上传记录',
                                            style: textStyle(p, color: p.muted),
                                          ),
                                        )
                                      : ListView.builder(
                                          key: ValueKey(cloud),
                                          controller: cloud
                                              ? cloudScroll
                                              : uploadScroll,
                                          itemCount: cloud
                                              ? cloudFiles.length
                                              : rows.length,
                                          itemBuilder: (context, i) => cloud
                                              ? cloudRow(cloudFiles[i], p)
                                              : uploadRow(rows[i], p),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      cloud
                          ? '创建时间为首次上传时间；来源设备为上传时的设备名称。'
                          : '删除上传记录只清理本机历史，不删除网盘文件。',
                      style: textStyle(p, size: 11, color: p.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<String?> showUploadExit(BuildContext context, int count) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        final p = Palette.of(c);
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Glass(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('仍有文件未上传完成', style: textStyle(p, size: 16, bold: true)),
                  const SizedBox(height: 12),
                  Text(
                    '还有 $count 个文件未完成，退出后将停止上传。',
                    style: textStyle(p, size: 12, color: p.muted),
                  ),
                  const SizedBox(height: 16),
                  for (final option in [
                    ('continue', '继续上传'),
                    ('wait', '上传完成后退出'),
                    ('stop', '停止上传并退出'),
                  ])
                    SpaceButton(
                      height: 40,
                      danger: option.$1 == 'stop',
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
        );
      },
    );
