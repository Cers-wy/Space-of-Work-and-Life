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
      await sync.transfer(download: download);
      if (download && sync.pending != null && mounted) {
        final backup = sync.pending!.backup;
        if (await confirm(
          context,
          '恢复云端数据',
          '已校验 ${backup.tasks.length} 项任务、${backup.projects.length} 个项目和 ${backup.statuses.length} 个状态。恢复前先备份本地；本机外观和连接配置保留。',
          '备份并恢复',
        )) {
          await sync.restoreGitHub();
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
  }) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textStyle(p, size: 12, color: p.muted)),
        const SizedBox(height: 4),
        IgnorePointer(
          ignoring: loading || working || sync.busy,
          child: SpaceInput(
            controller: controller,
            hint: hint,
            label: label,
            obscure: obscure,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = !loading && !working && !sync.busy && !widget.store.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '填写私有仓库地址与Token，设置恢复密钥，即可手动备份或恢复。连接配置自动保存在本地SQLite。',
          style: textStyle(p, size: 12, color: p.secondary),
        ),
        const SizedBox(height: 12),
        field('仓库地址', address, 'https://github.com/账号/仓库'),
        const SizedBox(height: 12),
        field(
          'Token令牌',
          token,
          sync.hasToken ? '已保存到SQLite，留空保留' : '填写此仓库的访问令牌',
          obscure: true,
        ),
        const SizedBox(height: 12),
        field(
          '恢复密钥',
          recoveryKey,
          sync.hasKey ? '已保存到SQLite，留空保留' : '自行设置至少12个字符，其他设备使用相同密钥',
          obscure: true,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SpaceButton(
              primary: true,
              onPressed: enabled ? () => transfer(false) : null,
              child: const Text('同步数据到云端'),
            ),
            SpaceButton(
              onPressed: enabled ? () => transfer(true) : null,
              child: const Text('恢复云端数据'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          error ?? sync.message,
          style: textStyle(
            p,
            size: 12,
            color: error == null ? p.secondary : p.red,
          ),
        ),
        if (sync.lastSyncedAt != null) ...[
          const SizedBox(height: 8),
          Text(
            '最近同步：${sync.lastSyncedAt!.toLocal()}',
            style: textStyle(p, size: 12, color: p.muted),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '云端只保存加密任务数据。恢复时需要相同密钥；SQLite导出文件含本机连接配置，请妥善保管。',
          style: textStyle(p, size: 12, color: p.muted),
        ),
      ],
    );
  }
}
