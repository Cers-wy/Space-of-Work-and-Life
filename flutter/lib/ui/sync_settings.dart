import 'dart:async';
import 'package:flutter/material.dart';
import '../core/sync_service.dart';
import '../store.dart';
import 'theme.dart';
import 'controls.dart';
import 'dialogs.dart' show confirm;

class GitHubSettings extends StatefulWidget {
  final SpaceStore store;
  const GitHubSettings({super.key, required this.store});
  @override
  State<GitHubSettings> createState() => _GitHubSettingsState();
}

class _GitHubSettingsState extends State<GitHubSettings> {
  late final SyncService sync;
  final address = TextEditingController(),
      token = TextEditingController(),
      recoveryKey = TextEditingController();
  Timer? debounce;
  bool loading = true, working = false;
  bool showToken = false, showRecoveryKey = false;
  String? error;

  @override
  void initState() {
    super.initState();
    sync = syncFor(widget.store);
    sync.addListener(changed);
    load();
  }

  Future<void> load() async {
    await sync.initialize();
    if (!mounted) return;
    address.text = sync.config.url;
    for (final controller in [address, token, recoveryKey]) {
      controller.addListener(edited);
    }
    setState(() => loading = false);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void edited() {
    debounce?.cancel();
    debounce = Timer(
      const Duration(milliseconds: 600),
      () => persist(silent: true),
    );
    if (mounted) setState(() => error = null);
  }

  Future<bool> persist({bool silent = false}) async {
    if (loading || sync.busy) return false;
    try {
      final next = GitHubConfig.fromUrl(
        address.text,
        branch: sync.config.branch,
        path: sync.config.path,
      );
      if (silent &&
          ((token.text.trim().isEmpty && !sync.hasToken) ||
              (recoveryKey.text.trim().isEmpty && !sync.hasKey))) {
        return false;
      }
      final ok = await sync.save(next, token.text, recoveryKey.text);
      if (!ok && mounted && !silent) setState(() => error = sync.message);
      return ok;
    } on FormatException catch (e) {
      if (mounted && !silent) setState(() => error = e.message);
      return false;
    }
  }

  Future<void> transfer(bool download) async {
    if (working) return;
    debounce?.cancel();
    setState(() {
      working = true;
      error = null;
    });
    try {
      if (!await persist() || !mounted) return;
      if (!download &&
          !await confirm(
            context,
            '同步数据到云端',
            '将本机完整任务数据上传到此私有仓库，替换当前云端备份。确认继续？',
            '同步到云端',
          )) {
        return;
      }
      final previousSync = sync.lastSyncedAt;
      await sync.transfer(download: download);
      if (download ? sync.pending == null : sync.lastSyncedAt == previousSync) {
        error = sync.message;
      }
      if (download && sync.pending != null && mounted) {
        final backup = sync.pending!.backup;
        if (await confirm(
          context,
          '恢复云端数据',
          '已校验 ${backup.tasks.length} 项任务、${backup.projects.length} 个项目和 ${backup.statuses.length} 个状态。恢复前先备份本地；本机外观和连接配置保留。',
          '备份并恢复',
        )) {
          final previousRestore = sync.lastSyncedAt;
          await sync.restoreGitHub();
          if (sync.lastSyncedAt == previousRestore) error = sync.message;
        } else {
          sync.cancelPending();
        }
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    // Flush valid edits when closing before the debounce expires.
    if (!loading && !working && !sync.busy) unawaited(persist(silent: true));
    sync.removeListener(changed);
    for (final controller in [address, token, recoveryKey]) {
      controller.removeListener(edited);
      controller.dispose();
    }
    super.dispose();
  }

  Widget field(
    String label,
    TextEditingController controller,
    String hint, {
    bool obscure = false,
    bool saved = false,
    VoidCallback? toggle,
    bool revealed = false,
  }) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: textStyle(p))),
            if (saved)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: p.green.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '已保存',
                  style: textStyle(p, size: 12, color: p.green),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        IgnorePointer(
          ignoring: loading || working || sync.busy,
          child: Row(
            children: [
              Expanded(
                child: SpaceInput(
                  controller: controller,
                  hint: hint,
                  label: label,
                  obscure: obscure && !revealed,
                  borderColor: p.blend(
                    const Color(0xffe1e7f0),
                    const Color(0xff313131),
                  ),
                ),
              ),
              if (toggle != null) ...[
                const SizedBox(width: 4),
                SpaceButton(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tooltip: '${revealed ? '隐藏' : '显示'}$label',
                  onPressed: loading || working || sync.busy ? null : toggle,
                  child: Text(
                    revealed ? '隐藏' : '显示',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = !loading && !working && !sync.busy && !widget.store.busy;
    final succeeded =
        sync.message == '数据已同步到云端' || sync.message == '已备份本地并恢复云端数据';
    final statusColor = error != null
        ? p.red
        : working || sync.busy
        ? p.accent
        : succeeded
        ? p.green
        : p.secondary;
    final date = sync.lastSyncedAt?.toLocal();
    String two(int n) => '$n'.padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SpaceIcon(
                  succeeded && error == null && !working && !sync.busy
                      ? 'check'
                      : 'tray',
                  size: 18,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loading ? '正在读取连接配置…' : error ?? sync.message,
                        style: textStyle(
                          p,
                          size: 12,
                          bold: true,
                          color: statusColor,
                        ),
                      ),
                      if (date != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '最近同步：${date.year}/${two(date.month)}/${two(date.day)} ${two(date.hour)}:${two(date.minute)}',
                          style: textStyle(p, size: 12, color: p.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        field('仓库地址', address, 'https://github.com/账号/仓库'),
        const SizedBox(height: 16),
        field(
          'Token令牌',
          token,
          sync.hasToken ? '已保存到SQLite，留空保留' : '填写此仓库的访问令牌',
          obscure: true,
          saved: sync.hasToken,
          revealed: showToken,
          toggle: () => setState(() => showToken = !showToken),
        ),
        const SizedBox(height: 16),
        field(
          '恢复密钥',
          recoveryKey,
          sync.hasKey ? '已保存到SQLite，留空保留' : '自行设置至少12个字符，其他设备使用相同密钥',
          obscure: true,
          saved: sync.hasKey,
          revealed: showRecoveryKey,
          toggle: () => setState(() => showRecoveryKey = !showRecoveryKey),
        ),
        const SizedBox(height: 8),
        Text('留空则保留已保存的令牌和密钥', style: textStyle(p, size: 12, color: p.muted)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SpaceButton(
              primary: true,
              onPressed: enabled ? () => transfer(false) : null,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SpaceIcon('up', size: 16, color: Colors.white),
                  SizedBox(width: 8),
                  Text('同步数据到云端'),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: p.blend(
                    const Color(0xffe1e7f0),
                    const Color(0xff313131),
                  ),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SpaceButton(
                onPressed: enabled ? () => transfer(true) : null,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SpaceIcon('down', size: 16),
                    SizedBox(width: 8),
                    Text('恢复云端数据'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('备份与恢复说明', style: textStyle(p, bold: true)),
              const SizedBox(height: 8),
              Text(
                '云端仅保存加密任务数据，恢复时需使用相同密钥。',
                style: textStyle(p, size: 12, color: p.secondary),
              ),
              const SizedBox(height: 4),
              Text(
                'SQLite 导出文件包含本机连接配置，请妥善保管。',
                style: textStyle(p, size: 12, color: p.secondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('连接配置自动保存在本机', style: textStyle(p, size: 12, color: p.muted)),
      ],
    );
  }
}
