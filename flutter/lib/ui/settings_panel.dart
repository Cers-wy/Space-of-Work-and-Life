import 'dart:io';

import 'package:flutter/material.dart';

import '../host.dart';
import '../store.dart';
import 'controls.dart';
import 'dialogs.dart' show confirm, importBackup;
import 'sync_settings.dart';
import 'theme.dart';

/// Settings remain mounted when filtering, so in-progress connection edits and
/// their debounced persistence survive navigation and window resizing.
class SettingsPanel extends StatefulWidget {
  final SpaceStore store;
  const SettingsPanel({super.key, required this.store});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel>
    with SingleTickerProviderStateMixin {
  SpaceStore get s => widget.store;
  final scroll = ScrollController();
  late final AnimationController fade;
  late final Animation<double> opacity;
  int selected = 0;
  static const categories = [
    ('gear', '全部设置'),
    ('sun', '外观与交互'),
    ('save', '备份与恢复'),
    ('tray', '云端同步'),
    ('project', '数据管理'),
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

  Widget card(String title, Widget child, {String? subtitle, String? icon}) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.blend(Colors.white, const Color(0xff1f1f1f)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border(p)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                SpaceIcon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(title, style: textStyle(p, size: 18, bold: true)),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: textStyle(p, size: 12, color: p.muted)),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget appearance() {
    final p = Palette.of(context);
    return card(
      '外观与交互',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('界面主题', style: textStyle(p, bold: true)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final choice in const {
                'system': '跟随系统',
                'light': '浅色',
                'dark': '深色',
              }.entries) ...[
                if (choice.key != 'system') const SizedBox(width: 8),
                Expanded(
                  child: _ThemeTile(
                    value: choice.key,
                    label: choice.value,
                    selected: s.appearance == choice.key,
                    onPressed: s.busy
                        ? null
                        : () => s.preference('appearance', choice.key),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text('随系统自动切换浅色与深色外观', style: textStyle(p, size: 12, color: p.muted)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: border(p)),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('隐藏滚动条', style: textStyle(p, bold: true)),
                    const SizedBox(height: 4),
                    Text(
                      '仍可使用滚轮、触控板和键盘滚动',
                      style: textStyle(p, size: 12, color: p.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: '隐藏滚动条',
                child: Switch.adaptive(
                  activeTrackColor: p.primary,
                  value: s.hideScrollbars,
                  onChanged: s.busy
                      ? null
                      : (value) => s.preference('hideScrollbars', '$value'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget backup() {
    return card(
      '本地备份与恢复',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - 8) / 2;
              Widget button(String label, String icon, VoidCallback? action) =>
                  SizedBox(
                    width: width,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: border(Palette.of(context))),
                      ),
                      child: SpaceButton(
                        onPressed: action,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (width >= 160) ...[
                              SpaceIcon(icon, size: 16),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: width < 160 ? 12 : 14,
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
              final enabled = s.loaded && !s.busy;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  button(
                    '导出SQLite',
                    'up',
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
                  ),
                  button(
                    '导入SQLite',
                    'down',
                    enabled ? () => importBackup(context, s) : null,
                  ),
                  button(
                    '恢复上次备份',
                    'undo',
                    enabled && File(s.repository.previous).existsSync()
                        ? () => action(() async {
                            final incoming = await s.repository.readExternal(
                              s.repository.previous,
                            );
                            if (!context.mounted) return;
                            if (await confirm(
                                  context,
                                  '恢复上次备份',
                                  '恢复写入前的 ${incoming.tasks.length} 项任务？当前任务库也会先备份。',
                                  '恢复',
                                ) &&
                                context.mounted) {
                              await s.applyBackup(incoming);
                            }
                          })
                        : null,
                  ),
                  button(
                    '打开数据库文件夹',
                    'folder',
                    enabled
                        ? () => DesktopHost.reveal(s.repository.path)
                        : null,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            '导入前自动备份，校验通过后再确认恢复。',
            style: textStyle(
              Palette.of(context),
              size: 12,
              color: Palette.of(context).muted,
            ),
          ),
        ],
      ),
      subtitle: 'SQLite 数据库',
    );
  }

  Widget management() {
    final p = Palette.of(context);
    return card(
      '数据管理',
      Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('体验示例内容', style: textStyle(p))),
              const SizedBox(width: 8),
              SpaceButton(
                height: 32,
                onPressed: s.busy
                    ? null
                    : () => action(() async {
                        if (await confirm(
                          context,
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
                      }),
                child: const Text('载入演示任务', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: border(p)),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('清空全部任务', style: textStyle(p, color: p.red)),
                    const SizedBox(height: 4),
                    Text(
                      '操作前需再次确认，可撤销',
                      style: textStyle(p, size: 12, color: p.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SpaceButton(
                height: 32,
                danger: true,
                onPressed: s.busy || s.state.tasks.isEmpty
                    ? null
                    : () => action(() async {
                        if (await confirm(
                          context,
                          '清空所有任务',
                          '项目和状态保留，可以撤销恢复任务。',
                          '清空所有任务',
                        )) {
                          await s.commit(s.state.copy(tasks: []), '任务已清空，可撤销');
                        }
                      }),
                child: const Text('清空所有任务', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget retained(bool visible, Widget child) => ExcludeFocus(
    excluding: !visible,
    child: Visibility(visible: visible, maintainState: true, child: child),
  );

  Widget navigation(bool compact) {
    final p = Palette.of(context);
    return ColoredBox(
      color: p.blend(const Color(0xfff1f4f9), const Color(0xff181818)),
      child: FocusTraversalGroup(
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < categories.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                SpaceButton(
                  key: ValueKey('settings-category-$i'),
                  selected: selected == i,
                  tooltip: compact ? categories[i].$2 : null,
                  height: 40,
                  padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                  onPressed: () => select(i),
                  child: Row(
                    mainAxisAlignment: compact
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      SpaceIcon(
                        categories[i].$1,
                        size: 18,
                        color: selected == i ? p.accent : p.secondary,
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 8),
                        Text(categories[i].$2),
                      ],
                    ],
                  ),
                ),
              ],
              const Spacer(),
              if (!compact)
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: p.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '数据保存在本机',
                      style: textStyle(p, size: 12, color: p.muted),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget content() {
    final p = Palette.of(context);
    final all = selected == 0;
    return FadeTransition(
      opacity: opacity,
      child: SingleChildScrollView(
        key: const ValueKey('settings-scroll'),
        controller: scroll,
        padding: const EdgeInsets.all(24),
        child: FocusTraversalGroup(
          child: LayoutBuilder(
            builder: (context, box) {
              final dual = all && box.maxWidth >= 720;
              final left = dual ? (box.maxWidth - 16) * .46 : box.maxWidth;
              final right = dual ? box.maxWidth - left - 16 : box.maxWidth;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    all ? '工作台偏好' : categories[selected].$2,
                    style: textStyle(p, size: 24, bold: true),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '管理界面外观、数据备份与云端同步',
                    style: textStyle(p, size: 14, color: p.muted),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    key: const ValueKey('settings-columns'),
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      retained(
                        all || selected != 3,
                        SizedBox(
                          width: left,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              retained(all || selected == 1, appearance()),
                              if (all) const SizedBox(height: 16),
                              retained(all || selected == 2, backup()),
                              if (all) const SizedBox(height: 16),
                              retained(all || selected == 4, management()),
                            ],
                          ),
                        ),
                      ),
                      retained(
                        all || selected == 3,
                        SizedBox(
                          width: right,
                          child: card(
                            'GitHub 私有仓库同步',
                            GitHubSettings(store: s),
                            subtitle: '通过私有仓库备份和恢复任务数据',
                            icon: 'tray',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (s.error != null || s.notice != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        s.error ?? s.notice!,
                        style: textStyle(
                          p,
                          size: 12,
                          color: s.error != null ? p.red : p.green,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.blend(const Color(0xfff7f9fc), const Color(0xff181818)),
          border: Border.all(color: border(p)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  const Mark(size: 32),
                  const SizedBox(width: 8),
                  Text('Space', style: textStyle(p, size: 20, bold: true)),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      '数据与设置',
                      style: textStyle(p, size: 18, bold: true),
                    ),
                  ),
                  IconButtonS(
                    'x',
                    '关闭数据与设置',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
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
                      Expanded(child: content()),
                    ],
                  );
                },
              ),
            ),
            Divider(height: 1, color: border(p)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Space · 个人工作台',
                      style: textStyle(p, size: 12, color: p.muted),
                    ),
                  ),
                  SpaceButton(
                    height: 32,
                    primary: true,
                    onPressed: () => Navigator.pop(context),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final String value, label;
  final bool selected;
  final VoidCallback? onPressed;
  const _ThemeTile({
    required this.value,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? p.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? p.accent
              : p.blend(const Color(0xffe1e7f0), const Color(0xff313131)),
        ),
      ),
      child: SpaceButton(
        selected: selected,
        height: 96,
        padding: const EdgeInsets.all(8),
        onPressed: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 48,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Row(
                        children: [
                          Expanded(child: _MiniWindow(dark: value == 'dark')),
                          if (value == 'system')
                            const Expanded(child: _MiniWindow(dark: true)),
                        ],
                      ),
                    ),
                    if (selected)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: p.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: SpaceIcon(
                              'check',
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _MiniWindow extends StatelessWidget {
  final bool dark;
  const _MiniWindow({required this.dark});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: dark ? const Color(0xff272727) : const Color(0xfff1f4f9),
    child: Column(
      children: [
        Container(
          height: 8,
          color: dark ? const Color(0xff313131) : const Color(0xffe1e7f0),
        ),
        Expanded(
          child: Row(
            children: [
              Container(
                width: 12,
                color: dark ? const Color(0xff181818) : const Color(0xffe7edf7),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        Expanded(
                          child: ColoredBox(
                            color: dark
                                ? const Color(0xff313131)
                                : Colors.white,
                          ),
                        ),
                        if (i < 2) const SizedBox(height: 2),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
