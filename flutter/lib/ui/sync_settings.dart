import 'dart:async';
import 'package:flutter/material.dart';
import '../core/sync_service.dart';
import '../store.dart';
import 'theme.dart';
import 'settings_controls.dart';
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
  bool showToken = false, showRecoveryKey = false, showHelp = false;
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
            '将本机任务、发票台账、发票原件与附件上传到此私有仓库，替换当前云端备份。确认继续？',
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
        final invoices = sync.pending!.invoices;
        if (await confirm(
          context,
          '恢复云端数据',
          '已校验 ${backup.tasks.length} 项任务、${backup.projects.length} 个项目和 '
              '${invoices.invoices} 张发票。'
              '${invoices.files.isEmpty ? '该备份不含附件文件。' : '将同时下载 ${invoices.files.length} 个发票与附件文件。'}'
              '恢复前先备份本地；本机外观与连接配置保留，本地台账将改为云端内容。',
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
    final input = SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        enabled: !loading && !working && !sync.busy,
        obscureText: obscure && !revealed,
        style: textStyle(p),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: textStyle(p, color: p.muted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          filled: true,
          fillColor: p.card.withValues(alpha: .46),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: p.blend(const Color(0xffe1e7f0), const Color(0xff313131)),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: p.accent, width: 2),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: p.border),
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 40,
            maxWidth: 40,
          ),
          suffixIcon: toggle == null
              ? null
              : Padding(
                  padding: const EdgeInsets.all(4),
                  child: SettingsAction(
                    height: 32,
                    quiet: true,
                    padding: EdgeInsets.zero,
                    tooltip: '${revealed ? '隐藏' : '显示'}$label',
                    onPressed: loading || working || sync.busy ? null : toggle,
                    child: SettingsIcon(revealed ? 'eye-off' : 'eye', size: 16),
                  ),
                ),
        ),
      ),
    );
    final caption = Text(label, style: textStyle(p));
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth < 520
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [caption, const SizedBox(height: 8), input],
              )
            : Row(
                children: [
                  SizedBox(width: 112, child: caption),
                  const SizedBox(width: 16),
                  Expanded(child: input),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = !loading && !working && !sync.busy && !widget.store.busy;
    final date = sync.lastSyncedAt?.toLocal();
    return LayoutBuilder(
      builder: (context, box) {
        final indent = box.maxWidth < 520 ? 0.0 : 128.0;
        Widget indented(Widget child) => Padding(
          padding: EdgeInsets.only(left: indent),
          child: child,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                loading ? '正在读取连接配置…' : error ?? sync.message,
                style: textStyle(
                  p,
                  size: 12,
                  color: error != null ? p.red : p.muted,
                ),
              ),
            ),
            field('仓库地址', address, 'https://github.com/账号/仓库'),
            field(
              '访问令牌',
              token,
              sync.hasToken ? '已保存到SQLite，留空保留' : '填写此仓库的访问令牌',
              obscure: true,
              saved: sync.hasToken,
              revealed: showToken,
              toggle: () => setState(() => showToken = !showToken),
            ),
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
            indented(
              Text(
                '已保存的令牌和密钥，留空即可保留。',
                style: textStyle(p, size: 12, color: p.muted),
              ),
            ),
            const SizedBox(height: 24),
            indented(
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  SettingsAction(
                    onPressed: enabled ? () => transfer(false) : null,
                    child: const Text('同步到云端'),
                  ),
                  SettingsAction(
                    quiet: true,
                    onPressed: enabled ? () => transfer(true) : null,
                    child: const Text('恢复云端数据'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            indented(
              Text(
                '连接配置自动保存在本机。',
                style: textStyle(p, size: 12, color: p.muted),
              ),
            ),
            const SizedBox(height: 8),
            indented(
              Text(
                '发票原件与附件随同步加密上传，按内容摘要逐个续传，换机恢复时自动校验。',
                style: textStyle(p, size: 12, color: p.muted),
              ),
            ),
            if (date != null) ...[
              const SizedBox(height: 8),
              indented(
                Text(
                  '最近同步：${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                  style: textStyle(p, size: 12, color: p.muted),
                ),
              ),
            ],
            const SizedBox(height: 16),
            indented(
              Align(
                alignment: Alignment.centerLeft,
                child: SettingsAction(
                  quiet: true,
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => showHelp = !showHelp),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedRotation(
                        turns: showHelp ? .25 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : spaceDuration,
                        curve: spaceCurve,
                        child: const SettingsIcon('right', size: 12),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '备份与恢复说明',
                        style: textStyle(p, size: 12, color: p.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            indented(
              AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                switchInCurve: spaceCurve,
                switchOutCurve: spaceCurve,
                child: showHelp
                    ? Padding(
                        key: const ValueKey('sync-help'),
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '云端保存加密的任务、发票台账与附件文件，恢复时需使用相同密钥。'
                          '恢复前会先备份当前本地任务库及台账；本地多出的发票记录会被云端内容替换，磁盘上的附件文件保留。',
                          style: textStyle(p, size: 12, color: p.muted),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }
}
