import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../host.dart';

const projectUrl = 'https://github.com/Cers-wy/Space-of-Work-and-Life';
const feedbackEmail = 'wy18390208101@outlook.com';

class AppVersion implements Comparable<AppVersion> {
  final int major, minor, patch;
  const AppVersion(this.major, this.minor, this.patch);
  static AppVersion? parse(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:\+[\w.]+)?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    return AppVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  @override
  int compareTo(AppVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    return 0;
  }

  @override
  String toString() => '$major.$minor.$patch';
}

enum UpdateStatus { checking, current, available, unavailable, failed }

/// Only public release metadata is read. Sync tokens and task data are never used.
class ReleaseChecker extends ChangeNotifier {
  final Future<Map<String, dynamic>> Function() infoLoader;
  final Future<List<dynamic>> Function()? releaseLoader;
  final String platform;
  UpdateStatus status = UpdateStatus.checking;
  AppVersion? installed, latest;
  String build = '', message = '正在获取版本信息，请稍候。';
  Uri releaseUrl = Uri.parse('$projectUrl/releases/latest');
  Future<void>? _pending;
  HttpClient? _client;
  bool _disposed = false;

  ReleaseChecker({
    Future<Map<String, dynamic>> Function()? infoLoader,
    this.releaseLoader,
    String? platform,
  }) : infoLoader = infoLoader ?? DesktopHost.appInfo,
       platform = platform ?? (Platform.isMacOS ? 'macos' : 'windows');

  String get label => switch (status) {
    UpdateStatus.checking => '正在检查…',
    UpdateStatus.current => '已是最新版',
    UpdateStatus.available => '新版 $latest 可下载',
    UpdateStatus.unavailable => '暂无适用安装包',
    UpdateStatus.failed => '暂时无法检查',
  };

  Future<void> check() {
    if (_disposed) return Future.value();
    return _pending ??= _check().whenComplete(() => _pending = null);
  }

  Future<List<dynamic>> _fetch() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    _client = client;
    try {
      final request = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/Cers-wy/Space-of-Work-and-Life/releases?per_page=30',
        ),
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'Space/$installed');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close();
      if (response.statusCode == 403 || response.statusCode == 429) {
        throw const FormatException('更新服务暂时限流，请稍后重试或前往 GitHub 发布页查看。');
      }
      if (response.statusCode != 200) {
        throw const FormatException('无法获取发布信息，请稍后重试或前往 GitHub 发布页查看。');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const FormatException('发布信息过大，请前往 GitHub 发布页查看。');
        }
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! List) throw const FormatException('发布信息格式无效，请稍后重试。');
      return decoded;
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }

  bool _supports(dynamic assets) =>
      assets is List &&
      assets.any((asset) {
        if (asset is! Map || asset['name'] is! String) return false;
        final name = (asset['name'] as String).toLowerCase();
        if (platform == 'macos') {
          return RegExp(r'mac|darwin').hasMatch(name) &&
              RegExp(r'arm64|aarch64|universal').hasMatch(name) &&
              (name.endsWith('.dmg') || name.endsWith('.zip'));
        }
        return name.contains('win') &&
            RegExp(r'x64|amd64').hasMatch(name) &&
            (name.endsWith('.zip') ||
                name.endsWith('.exe') ||
                name.endsWith('.msi'));
      });

  Future<void> _check() async {
    status = UpdateStatus.checking;
    message = '正在获取版本信息，请稍候。';
    notifyListeners();
    try {
      if (installed == null) {
        final info = await infoLoader();
        installed = AppVersion.parse(info['version']?.toString() ?? '');
        build = info['build']?.toString() ?? '';
        if (installed == null) {
          throw const FormatException('无法读取当前版本，请重新打开设置后重试。');
        }
      }
      if (_disposed) return;
      final releases = await (releaseLoader?.call() ?? _fetch()).timeout(
        const Duration(seconds: 12),
      );
      if (_disposed) return;
      Map? chosen;
      AppVersion? newest;
      for (final release in releases) {
        if (release is! Map ||
            release['draft'] != false ||
            release['prerelease'] != false) {
          continue;
        }
        final version = AppVersion.parse(release['tag_name']?.toString() ?? '');
        final url = Uri.tryParse(release['html_url']?.toString() ?? '');
        if (version == null ||
            url == null ||
            url.scheme != 'https' ||
            url.host != 'github.com' ||
            url.userInfo.isNotEmpty ||
            !url.path.startsWith(
              '/Cers-wy/Space-of-Work-and-Life/releases/tag/',
            )) {
          continue;
        }
        if (newest == null || version.compareTo(newest) > 0) {
          newest = version;
          chosen = release;
        }
      }
      if (newest == null || chosen == null) {
        throw const FormatException('暂未找到有效的正式发布，请前往 GitHub 发布页查看。');
      }
      latest = newest;
      releaseUrl = Uri.parse(chosen['html_url'] as String);
      if (newest.compareTo(installed!) <= 0) {
        status = UpdateStatus.current;
        message = '当前已是最新版本。';
      } else if (!_supports(chosen['assets'])) {
        status = UpdateStatus.unavailable;
        message = '发现新版本 $newest，但暂未提供适合本机平台的安装包，可前往发布页查看。';
      } else {
        status = UpdateStatus.available;
        message = '可前往发布页下载安装。暂不支持在线热更新。';
      }
    } catch (error) {
      if (_disposed) return;
      status = UpdateStatus.failed;
      message = error is FormatException
          ? error.message
          : '无法连接更新服务，请检查网络后重试，或前往 GitHub 发布页查看。';
    } finally {
      _client?.close(force: true);
      _client = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _client?.close(force: true);
    super.dispose();
  }
}
