import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/releases.dart';

Map<String, dynamic> release(
  String version, {
  bool draft = false,
  bool prerelease = false,
  String platform = 'both',
}) => {
  'tag_name': version,
  'draft': draft,
  'prerelease': prerelease,
  'html_url': '$projectUrl/releases/tag/$version',
  'assets': [
    if (platform != 'windows') {'name': 'Space-$version-macOS-arm64.dmg'},
    if (platform != 'macos') {'name': 'Space-$version-Win11-x64-Portable.zip'},
  ],
};
ReleaseChecker checker(
  Future<List<dynamic>> Function() load, {
  String platform = 'macos',
}) => ReleaseChecker(
  infoLoader: () async => {'version': '2.1.0', 'build': '13'},
  releaseLoader: load,
  platform: platform,
);

void main() {
  test('版本按数字比较，兼容v前缀和构建号，拒绝无效与预发布标签', () {
    expect(
      AppVersion.parse('v2.10.0')!.compareTo(AppVersion.parse('2.9.0')!),
      greaterThan(0),
    );
    expect(AppVersion.parse('2.1.0+13').toString(), '2.1.0');
    for (final value in ['2.1', '2.2.0-beta', 'latest', '2.x.0']) {
      expect(AppVersion.parse(value), isNull);
    }
  });
  for (final platform in ['macos', 'windows']) {
    test('$platform 选择最高正式版本并检查本平台包', () async {
      final c = checker(
        () async => [
          release('v2.2.0'),
          release('2.10.0'),
          release('99.0.0', draft: true),
          release('98.0.0', prerelease: true),
        ],
        platform: platform,
      );
      await c.check();
      expect(c.status, UpdateStatus.available);
      expect(c.latest.toString(), '2.10.0');
      expect(c.installed.toString(), '2.1.0');
      expect(c.build, '13');
      c.dispose();
    });
    test('$platform 缺少匹配平台包不能提供下载按钮', () async {
      final c = checker(
        () async => [
          release('2.2.0', platform: platform == 'macos' ? 'windows' : 'macos'),
        ],
        platform: platform,
      );
      await c.check();
      expect(c.status, UpdateStatus.unavailable);
      c.dispose();
    });
  }
  test('相同/较低发布显示最新版；无正式发布不误报成功', () async {
    for (final v in ['2.1.0', '2.0.11']) {
      final c = checker(() async => [release(v)]);
      await c.check();
      expect(c.status, UpdateStatus.current);
      c.dispose();
    }
    final c = checker(() async => []);
    await c.check();
    expect(c.status, UpdateStatus.failed);
    c.dispose();
  });
  test('异常与无效发布链接给出重试反馈', () async {
    final c = checker(() async => throw const FormatException('更新服务暂时限流'));
    await c.check();
    expect(c.message, contains('限流'));
    expect(c.status, UpdateStatus.failed);
    c.dispose();
    final invalid = release('3.0.0')
      ..['html_url'] = 'https://attacker.test/releases/tag/3.0.0';
    final bad = checker(() async => [invalid]);
    await bad.check();
    expect(bad.status, UpdateStatus.failed);
    bad.dispose();
  });
  test('重复检查合并，关闭页面后不回调已销毁状态', () async {
    final gate = Completer<List<dynamic>>();
    int calls = 0, notifications = 0;
    final c = checker(() {
      calls++;
      return gate.future;
    });
    c.addListener(() => notifications++);
    final first = c.check(), second = c.check();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    c.dispose();
    final before = notifications;
    gate.complete([release('2.2.0')]);
    await Future.wait([first, second]);
    expect(notifications, before);
  });
}
