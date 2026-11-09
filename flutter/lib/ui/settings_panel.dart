import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/releases.dart';
import '../host.dart';
import '../store.dart';
import 'controls.dart';
import 'dialogs.dart' show confirm, importBackup;
import 'settings_controls.dart';
import 'sync_settings.dart';
import 'theme.dart';

class SettingsPanel extends StatefulWidget {
  final SpaceStore store;
  final ReleaseChecker? updates;
  const SettingsPanel({super.key, required this.store, this.updates});
  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel>
    with SingleTickerProviderStateMixin {
  SpaceStore get s => widget.store;
  late final ReleaseChecker updates;
  final scroll = ScrollController();
  late final AnimationController fade;
  late final Animation<double> opacity;
  int selected = 0;
  String? linkError;
  bool copyEmail = false;
  static const categories = [
    ('all', '全部设置', '管理你的工作台偏好'),
    ('appearance', '外观与交互', '选择主题与交互偏好'),
    ('backup', '备份与恢复', '为本机数据保留一份副本'),
    ('cloud', '云端同步', '通过 GitHub 私有仓库备份和恢复任务数据'),
    ('data', '数据管理', '管理示例内容和本机任务'),
    ('info', '关于 Space', '软件信息与更新'),
  ];
  @override
  void initState() {
    super.initState();
    fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1,
    );
    opacity = fade.drive(CurveTween(curve: spaceCurve));
    s.addListener(change);
    updates = widget.updates ?? ReleaseChecker();
    updates.addListener(change);
    updates.check();
  }

  void change() {
    if (mounted) setState(() {});
  }

  void select(int index) {
    if (index == selected) return;
    setState(() => selected = index);
    if (scroll.hasClients) scroll.jumpTo(0);
    if (MediaQuery.disableAnimationsOf(context)) {
      fade.value = 1;
    } else {
      fade.forward(from: .65);
    }
  }

  @override
  void dispose() {
    s.removeListener(change);
    updates.removeListener(change);
    if (widget.updates == null) updates.dispose();
    scroll.dispose();
    fade.dispose();
    super.dispose();
  }

  Future<void> action(Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      s.error = SpaceStore.readable(e);
      s.refreshQuery();
    }
  }

  Color border(Palette p) =>
      p.blend(const Color(0xffe1e7f0), const Color(0xff313131));
  Widget section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: SpaceEditorSection(title: title, children: children),
  );

  Widget row(String label, {String? detail, Widget? trailing}) {
    final p = Palette.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textStyle(p)),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(detail, style: textStyle(p, size: 12, color: p.muted)),
        ],
      ],
    );
    return Container(
      constraints: BoxConstraints(minHeight: detail == null ? 48 : 64),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: border(p))),
      ),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth < 400 && trailing != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  text,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: trailing),
                ],
              )
            : Row(
                children: [
                  Expanded(child: text),
                  if (trailing != null) ...[
                    const SizedBox(width: 16),
                    trailing,
                  ],
                ],
              ),
      ),
    );
  }

  Widget button(
    String label,
    VoidCallback? onPressed, {
    String? icon,
    bool quiet = false,
    bool danger = false,
  }) => SettingsAction(
    onPressed: onPressed,
    quiet: quiet,
    danger: danger,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          SettingsIcon(
            icon,
            size: 16,
            color: danger ? Palette.of(context).red : null,
          ),
          const SizedBox(width: 8),
        ],
        Text(label),
      ],
    ),
  );
  String get themeSummary => s.appearance == 'system'
      ? '跟随系统 · ${s.temporaryDark == null ? '' : '临时'}${s.dark ? '深色' : '浅色'}'
      : '固定${s.dark ? '深色' : '浅色'}';

  Widget overview() {
    final p = Palette.of(context);
    Widget entry(int index, String detail, String summary) => Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: border(p))),
      ),
      child: SettingsAction(
        height: 72,
        quiet: true,
        padding: EdgeInsets.zero,
        onPressed: () => select(index),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(categories[index].$2, style: textStyle(p)),
                  const SizedBox(height: 4),
                  Text(detail, style: textStyle(p, size: 12, color: p.muted)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (summary.isNotEmpty)
              Flexible(
                child: Text(
                  summary,
                  textAlign: TextAlign.right,
                  style: textStyle(p, size: 12, color: p.muted),
                ),
              ),
            const SizedBox(width: 8),
            const SettingsIcon('right', size: 16),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section('工作台', [
          entry(1, '主题与滚动体验', themeSummary),
          entry(2, '导出、导入和恢复本地备份', 'SQLite 本地备份'),
          entry(3, '通过私有仓库接续工作', ''),
          entry(4, '示例内容与任务清理', ''),
        ]),
        section('软件', [
          entry(5, '作者、反馈与软件更新', updates.installed?.toString() ?? ''),
        ]),
      ],
    );
  }

  Widget appearance() {
    final p = Palette.of(context);
    final choices = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.blend(
          Colors.white.withValues(alpha: .45),
          const Color(0xff181818).withValues(alpha: .55),
        ),
        border: Border.all(color: border(p)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final choice in const [
            ('system', '跟随系统'),
            ('light', '浅色'),
            ('dark', '深色'),
          ])
            SettingsAction(
              height: 32,
              quiet: true,
              navigation: true,
              selected: s.appearance == choice.$1,
              onPressed: s.busy
                  ? null
                  : () => s.preference('appearance', choice.$1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsIcon(
                    choice.$1 == 'light'
                        ? 'sun'
                        : choice.$1 == 'dark'
                        ? 'moon'
                        : 'system',
                    size: 16,
                    color: s.appearance == choice.$1
                        ? p.selectedButtonForeground(p.secondary)
                        : p.secondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    choice.$2,
                    style: textStyle(
                      p,
                      size: 12,
                      color: s.appearance == choice.$1
                          ? p.selectedButtonForeground(p.text)
                          : p.text,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section('外观', [
          row('主题', trailing: choices),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                s.appearance == 'system'
                    ? '系统当前为${s.systemDark ? '深色' : '浅色'}。'
                    : '固定${s.dark ? '深色' : '浅色'}，不随系统切换。',
                style: textStyle(p, size: 12, color: p.muted),
              ),
              if (s.temporaryDark != null && s.appearance == 'system') ...[
                Text(
                  '临时${s.dark ? '深色' : '浅色'}',
                  style: textStyle(p, size: 12, color: p.accent),
                ),
                button('恢复跟随', s.resumeSystemAppearance, quiet: true),
              ],
            ],
          ),
        ]),
        section('交互', [
          row(
            '隐藏滚动条',
            detail: '仍可使用滚轮、触控板和键盘滚动',
            trailing: SizedBox(
              width: 48,
              height: 32,
              child: FittedBox(
                child: Semantics(
                  label: '隐藏滚动条',
                  child: Switch.adaptive(
                    activeTrackColor: p.primary,
                    value: s.hideScrollbars,
                    onChanged: s.busy
                        ? null
                        : (value) => s.preference('hideScrollbars', '$value'),
                  ),
                ),
              ),
            ),
          ),
        ]),
        section('主题切换说明', [
          row(
            '跟随系统时，主界面的明暗切换仅临时生效。',
            detail: '系统下次切换外观或重启 Space 后，会恢复跟随。\n在此选择浅色或深色后，将固定使用该外观。',
          ),
        ]),
      ],
    );
  }

  Widget backup() {
    final p = Palette.of(context), enabled = s.loaded && !s.busy;
    final previous = File(s.repository.previous).existsSync();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section('本地备份', [
          row(
            '导出备份',
            detail: '保存为 SQLite 文件',
            trailing: button(
              '导出',
              enabled
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
              icon: 'up',
            ),
          ),
          row(
            '导入备份',
            detail: '校验文件内容后，再确认替换当前数据',
            trailing: button(
              '选择文件',
              enabled ? () => importBackup(context, s) : null,
              icon: 'down',
            ),
          ),
          row(
            '恢复上次备份',
            detail: previous ? '恢复上一次写入前的本地数据' : '尚无可恢复的历史备份',
            trailing: button(
              '恢复',
              enabled && previous
                  ? () => action(() async {
                      final incoming = await s.repository.readExternal(
                        s.repository.previous,
                      );
                      if (!mounted) return;
                      if (await confirm(
                            context,
                            '恢复上次备份',
                            '恢复写入前的 ${incoming.tasks.length} 项任务？当前任务库也会先备份。',
                            '恢复',
                          ) &&
                          mounted) {
                        await s.applyBackup(incoming);
                      }
                    })
                  : null,
              icon: 'backup',
            ),
          ),
          row(
            '数据库位置',
            detail: '打开 Space 本地数据目录',
            trailing: button(
              '打开文件夹',
              enabled
                  ? () => action(() => DesktopHost.reveal(s.repository.path))
                  : null,
              icon: 'folder',
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Text(
          '导入前自动备份。导出的 SQLite 文件包含本机连接配置，请妥善保存。',
          style: textStyle(p, size: 12, color: p.muted),
        ),
      ],
    );
  }

  Widget management() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      section('示例内容', [
        row(
          '体验示例任务',
          detail: '以合成任务替换当前内容，可撤销',
          trailing: button(
            '载入示例',
            s.busy
                ? null
                : () => action(() async {
                    if (await confirm(
                          context,
                          '载入示例任务',
                          '将当前任务替换为合成示例数据，可以撤销。',
                          '载入示例',
                        ) &&
                        mounted) {
                      await s.commit(
                        demoState().copy(
                          settings: s.state.settings,
                          workspaceID: s.state.workspaceID,
                        ),
                        '已载入示例任务',
                      );
                    }
                  }),
          ),
        ),
      ]),
      section('任务清理', [
        row(
          '清空全部任务',
          detail: '保留项目与状态，清空后可撤销',
          trailing: button(
            '清空任务',
            s.busy || s.state.tasks.isEmpty
                ? null
                : () => action(() async {
                    if (await confirm(
                          context,
                          '清空全部任务',
                          '项目和状态保留，可以撤销恢复任务。',
                          '清空任务',
                        ) &&
                        mounted) {
                      await s.commit(s.state.copy(tasks: []), '任务已清空，可撤销');
                    }
                  }),
            icon: 'trash',
            danger: true,
          ),
        ),
      ]),
    ],
  );
  Future<void> open(Uri uri) async {
    try {
      if (await DesktopHost.openExternal(uri)) return;
    } catch (_) {
      /* Show a usable inline fallback below. */
    }
    if (!mounted) return;
    setState(() {
      copyEmail = uri.scheme == 'mailto';
      linkError = copyEmail
          ? '无法打开邮件客户端，可复制邮箱地址。'
          : '无法打开浏览器，请复制项目地址后访问：$projectUrl';
    });
  }

  Widget infoRow(String label, Widget value) {
    final p = Palette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: border(p))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: textStyle(p, size: 12, color: p.muted)),
          ),
          const SizedBox(width: 12),
          Expanded(child: value),
        ],
      ),
    );
  }

  Widget about() {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(
            children: [
              const Mark(size: 40),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Space', style: textStyle(p, size: 18, bold: true)),
                  Text('个人工作台', style: textStyle(p, size: 12, color: p.muted)),
                ],
              ),
            ],
          ),
        ),
        infoRow(
          '版本',
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                updates.installed?.toString() ?? '读取中…',
                style: textStyle(p),
              ),
              Semantics(
                liveRegion: true,
                child: Text(
                  updates.label,
                  style: textStyle(
                    p,
                    size: 12,
                    color: updates.status == UpdateStatus.available
                        ? p.accent
                        : p.muted,
                  ),
                ),
              ),
              button(
                '检查更新',
                updates.status == UpdateStatus.checking ? null : updates.check,
                quiet: true,
                icon: 'refresh',
              ),
            ],
          ),
        ),
        infoRow('作者', Text('Cers', style: textStyle(p))),
        infoRow(
          'Bug 反馈',
          Align(
            alignment: Alignment.centerLeft,
            child: button(
              feedbackEmail,
              () => open(Uri(scheme: 'mailto', path: feedbackEmail)),
              quiet: true,
            ),
          ),
        ),
        infoRow(
          '项目',
          Align(
            alignment: Alignment.centerLeft,
            child: button(
              'GitHub 项目',
              () => open(Uri.parse(projectUrl)),
              quiet: true,
              icon: 'external',
            ),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            updates.message,
            style: textStyle(p, size: 12, color: p.muted),
          ),
        ),
        if (updates.status == UpdateStatus.available ||
            updates.status == UpdateStatus.unavailable ||
            updates.status == UpdateStatus.failed) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: button(
              updates.status == UpdateStatus.available ? '下载新版' : '查看发布页',
              () => open(updates.releaseUrl),
              icon: 'external',
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          '暂不支持在线热更新，请前往发布页下载安装。',
          style: textStyle(p, size: 12, color: p.muted),
        ),
        if (linkError != null) ...[
          const SizedBox(height: 16),
          Text(linkError!, style: textStyle(p, size: 12, color: p.red)),
          if (copyEmail)
            Align(
              alignment: Alignment.centerLeft,
              child: button('复制邮箱', () async {
                await Clipboard.setData(
                  const ClipboardData(text: feedbackEmail),
                );
                if (mounted) setState(() => linkError = '邮箱地址已复制。');
              }, quiet: true),
            ),
        ],
      ],
    );
  }

  Widget retained(int index, Widget child) => ExcludeFocus(
    excluding: selected != index,
    child: TickerMode(
      enabled: selected == index,
      child: Offstage(offstage: selected != index, child: child),
    ),
  );
  Widget navigation(bool compact) {
    final p = Palette.of(context);
    return Container(
      color: p.blend(
        const Color(0xfff1f4f9).withValues(alpha: .52),
        const Color(0xff181818).withValues(alpha: .35),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 12),
              child: Text(
                '偏好设置',
                style: textStyle(p, size: 12, color: p.muted),
              ),
            ),
          for (var i = 0; i < categories.length; i++) ...[
            SettingsAction(
              key: ValueKey('settings-category-$i'),
              height: 40,
              quiet: true,
              navigation: true,
              selected: selected == i,
              tooltip: compact ? categories[i].$2 : null,
              padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
              onPressed: () => select(i),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  SettingsIcon(
                    categories[i].$1,
                    size: 16,
                    color: selected == i
                        ? p.selectedButtonForeground(p.secondary)
                        : p.secondary,
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        categories[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle(
                          p,
                          color: selected == i
                              ? p.selectedButtonForeground(p.secondary)
                              : p.secondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
          const Spacer(),
          if (!compact)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '•  数据保存在本机',
                style: textStyle(p, size: 12, color: p.muted),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Glass(
      contour: 'settings',
      background: const Ambient(),
      blur: false,
      child: Column(
        children: [
          SpaceTitleBar(
            key: const ValueKey('settings-titlebar'),
            children: [
              Text('设置', style: textStyle(p, bold: true)),
              const SizedBox(width: 12),
              Text('Space', style: textStyle(p, size: 12, color: p.muted)),
              const Spacer(),
              IconButtonS.toolbar(
                'x',
                '关闭设置',
                key: const ValueKey('settings-close'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Divider(height: 1, color: border(p)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final compact = box.maxWidth < 760;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: compact ? 64 : 184,
                      child: navigation(compact),
                    ),
                    VerticalDivider(width: 1, color: border(p)),
                    Expanded(
                      child: FadeTransition(
                        opacity: opacity,
                        child: SingleChildScrollView(
                          key: const ValueKey('settings-scroll'),
                          controller: scroll,
                          padding: EdgeInsets.all(compact ? 16 : 24),
                          child: FocusTraversalGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  categories[selected].$2,
                                  style: textStyle(p, size: 16, bold: true),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  categories[selected].$3,
                                  style: textStyle(p, size: 12, color: p.muted),
                                ),
                                retained(0, overview()),
                                retained(1, appearance()),
                                retained(2, backup()),
                                retained(
                                  3,
                                  Padding(
                                    padding: const EdgeInsets.only(top: 24),
                                    child: GitHubSettings(store: s),
                                  ),
                                ),
                                retained(4, management()),
                                retained(5, about()),
                                if (s.error != null || s.notice != null) ...[
                                  const SizedBox(height: 16),
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      s.error ?? s.notice!,
                                      style: textStyle(
                                        p,
                                        size: 12,
                                        color: s.error != null
                                            ? p.red
                                            : p.green,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Divider(height: 1, color: border(p)),
          SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      themeSummary,
                      style: textStyle(p, size: 12, color: p.muted),
                    ),
                  ),
                  Text(
                    'Space ${updates.installed ?? ''}',
                    style: textStyle(p, size: 12, color: p.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
