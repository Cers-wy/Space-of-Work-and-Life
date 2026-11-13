import 'dart:io';

import 'package:flutter/material.dart';

import '../core/drive.dart';
import '../store.dart';
import 'controls.dart';
import 'dialogs.dart' show field;
import 'settings_controls.dart';
import 'theme.dart';

/// 文件网盘配置保留原存储与安全令牌，只迁入全局设置。
class DriveSettings extends StatefulWidget {
  final SpaceStore store;
  const DriveSettings({super.key, required this.store});
  @override
  State<DriveSettings> createState() => _DriveSettingsState();
}

class _DriveSettingsState extends State<DriveSettings> {
  late final service = driveFor(widget.store);
  final address = TextEditingController(),
      branch = TextEditingController(),
      device = TextEditingController(),
      token = TextEditingController();
  bool loading = true, saving = false;
  String? error, notice;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await service.initialize();
    if (!mounted) return;
    address.text = service.config.ready
        ? 'https://github.com/${service.config.owner}/${service.config.repository}'
        : '';
    branch.text = service.config.branch;
    device.text = service.config.device.isEmpty
        ? Platform.localHostname
        : service.config.device;
    setState(() => loading = false);
  }

  @override
  void dispose() {
    for (final c in [address, branch, device, token]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> connect() async {
    if (saving || loading) return;
    setState(() {
      saving = true;
      error = notice = null;
    });
    try {
      final next = DriveConfig.fromAddress(
        address.text,
        branch: branch.text,
        device: device.text,
      );
      await service.connect(
        next,
        token.text.trim().isEmpty ? service.token : token.text.trim(),
      );
      if (!mounted) return;
      token.clear();
      notice = '仓库连接已保存';
    } catch (e) {
      if (mounted) error = driveError(e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget input(
      String label,
      TextEditingController controller, {
      bool secret = false,
      String hint = '',
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: field(
        context,
        label,
        SpaceInput(
          controller: controller,
          label: label,
          hint: hint,
          obscure: secret,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '文件管理独立使用此仓库连接，不修改任务数据的云端备份配置。',
            style: textStyle(p, size: 12, color: p.muted),
          ),
          const SizedBox(height: 16),
          SpaceEditorSection(
            title: '仓库连接',
            children: [
              input('仓库地址', address, hint: 'GitHub 仓库链接或账号/仓库'),
              input('分支', branch),
              input('来源设备', device),
              input(
                '访问令牌',
                token,
                secret: true,
                hint: service.token.isEmpty ? '输入访问令牌' : '留空沿用本机已保存的令牌',
              ),
              Text(
                '需要所选私有仓库的 Contents 读写权限，令牌保存在本机系统安全存储。新分支将独立初始化，不改动业务备份分支。',
                style: textStyle(p, size: 12, color: p.muted),
              ),
              const SizedBox(height: 16),
              if (error != null || notice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      error ?? notice!,
                      style: textStyle(
                        p,
                        size: 12,
                        color: error == null ? p.green : p.red,
                      ),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: SettingsAction(
                  onPressed: loading || saving ? null : connect,
                  child: Text(
                    saving ? '正在连接…' : '保存并连接',
                    style: textStyle(p, size: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
