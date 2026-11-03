import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/core/richtext.dart';
import 'package:space_flutter/core/sync.dart';
import 'package:space_flutter/core/sync_service.dart';

final fixtures = Directory('test/fixtures');
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('${fixtures.path}/$name').readAsStringSync());
SpaceState baseline() => SpaceState.fromJson(fixture('05-json-v6.json'));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final name in [
    '01-json-v1.json',
    '01b-json-v2.json',
    '02-json-v3.json',
    '03-json-v4.json',
    '04-json-v5.json',
    '05-json-v6.json',
  ]) {
    test('原生样本 $name 无损往返', () {
      final original = fixture(name);
      final state = SpaceState.fromJson(original);
      final reread = SpaceState.fromJson(state.toJson());
      expect(reread.tasks.single.toJson(), original['tasks'][0]);
      expect(reread.statuses, state.statuses);
      expect(
        reread.projects.map((p) => p.toJson()),
        state.projects.map((p) => p.toJson()),
      );
    });
  }
  test('非法时间戳、NFC重复名称与V1状态字段拒绝', () {
    expect(() => validTime('20261102'), throwsFormatException);
    expect(() => validTime('2026-02-29T00:00:00Z'), throwsFormatException);
    expect(normalizedName(' e\u0301 '), 'é');
    expect(
      () => SpaceState(
        projects: [Project('1', 'é'), Project('2', 'e\u0301')],
      ).validate(),
      throwsFormatException,
    );
    final j = fixture('01-json-v1.json');
    expect(
      () => SpaceState.fromJson({...j, 'statuses': builtins}),
      throwsFormatException,
    );
  });
  test('严格公历与北京时间跨日', () {
    expect(parseDay('2026-02-29'), isNull);
    expect(parseDay('2026-04-31'), isNull);
    expect(parseDay('2026-1-01'), isNull);
    expect(
      dayString(beijingDay(DateTime.parse('2026-11-01T17:00:00Z'))),
      '2026-11-02',
    );
  });
  test('默认排期只展示，拖动才写真实日期', () {
    final t = SpaceState.fromJson(fixture('01-json-v1.json')).tasks.single;
    final schedule = TaskSchedule.forTask(t, DateTime.utc(2026, 11, 2));
    expect(schedule.end, DateTime.utc(2026, 11, 7));
    expect(schedule.defaultDeadline, isTrue);
    expect(t.due, isEmpty);
    expect(t.startDate, isNull);
    final moved = schedule.adjusting('move', 2).apply(t);
    expect(moved.startDate, '2026-11-04');
    expect(moved.due, '2026-11-09');
  });
  test('完成与重开时间一致', () {
    final t = SpaceState.fromJson(fixture('01-json-v1.json')).tasks.single;
    final done = t.moving('done');
    done.validate();
    expect(done.completedAt, isNotNull);
    expect(done.moving('todo').completedAt, isNull);
    expect(
      () => done.patch({'completedAt': null}).validate(),
      throwsFormatException,
    );
  });
  test('未来格式与矛盾版本拒绝', () {
    final j = fixture('05-json-v6.json');
    expect(
      () => SpaceState.fromJson({...j, 'version': 7}),
      throwsFormatException,
    );
    expect(
      () => SpaceState.fromJson({...j, 'version': 5}),
      throwsFormatException,
    );
  });
  test('引用与重复任务拒绝', () {
    final s = baseline();
    expect(
      () => s.copy(tasks: [...s.tasks, ...s.tasks]).validate(),
      throwsFormatException,
    );
    expect(() => s.copy(projects: []).validate(), throwsFormatException);
  });
  test('排序日期/创建/ID稳定，清除保留排序', () {
    final original = SpaceState.fromJson(
      fixture('01-json-v1.json'),
    ).tasks.single;
    final s = SpaceState(
      tasks: [
        original.patch({'id': 'b', 'due': '2026-11-03'}),
        original.patch({'id': 'a', 'due': '2026-11-03'}),
        original.patch({'id': 'c'}),
      ],
    );
    final q = TaskQuery()
      ..sort = 'priority'
      ..category = 'work';
    q.clear();
    expect(q.sort, 'priority');
    expect(q.apply(s, '2026-11-02').map((x) => x.id), ['a', 'b', 'c']);
  });
  test('RTFD真实样本粗体、下划线、图片及中文往返', () {
    final s = baseline();
    final bytes = base64Decode(s.tasks.single.richDescription!);
    final runs = FlatRtfd.decode(bytes);
    expect(runs.any((r) => r.bold), isTrue);
    expect(runs.any((r) => r.underline), isTrue);
    expect(runs.where((r) => r.image != null).length, 1);
    final again = FlatRtfd.decode(FlatRtfd.encode(runs));
    expect(again.map((r) => r.text).join(), runs.map((r) => r.text).join());
    expect(
      again.where((r) => r.image != null).single.image,
      runs.where((r) => r.image != null).single.image,
    );
  });
  test('GitHub portable 字节与原生指纹完全一致', () {
    final s = baseline();
    final expected = File(
      '${fixtures.path}/09-github-portable.json',
    ).readAsStringSync();
    expect(swiftJson(s.toJson(portable: true)), expected);
    expect(
      SyncCodec.fingerprint(s),
      fixture('EXPECTED.json')['githubFingerprint'],
    );
  });
  test('原生GitHub加密包解密，错误密钥与篡改拒绝', () async {
    final facts = fixture('EXPECTED.json');
    final bytes = base64Decode(
      File('${fixtures.path}/07-github-packet.base64.txt').readAsStringSync(),
    );
    final key = facts['testRecoveryKeyBase64'] as String;
    final state = await SyncCodec.githubOpen(bytes, key);
    expect(state.tasks.single.toJson(), baseline().tasks.single.toJson());
    await expectLater(
      SyncCodec.githubOpen(bytes, SyncCodec.newRecoveryKey()),
      throwsFormatException,
    );
    bytes[bytes.length - 1] ^= 1;
    await expectLater(SyncCodec.githubOpen(bytes, key), throwsFormatException);
  });
  test('GitHub加密nonce随机且内容等价', () async {
    final key = SyncCodec.newRecoveryKey();
    final a = await SyncCodec.githubSeal(baseline(), key),
        b = await SyncCodec.githubSeal(baseline(), key);
    expect(a, isNot(b));
    expect(
      SyncCodec.fingerprint(await SyncCodec.githubOpen(a, key)),
      SyncCodec.fingerprint(baseline()),
    );
  });
  test('原生SP包2001 epoch，七天过期与哈希匹配', () async {
    final facts = fixture('EXPECTED.json'),
        code = facts['testSPCode'] as String;
    final envelope = File(
      '${fixtures.path}/08-sp-envelope.json',
    ).readAsStringSync();
    final bytes = await SyncCodec.spOpen(
      envelope,
      code,
      now: DateTime.parse(facts['fixedNow']),
    );
    expect(sha256.convert(bytes).toString(), facts['sqliteSHA256']);
    expect(SyncCodec.receipt(code), facts['spReceiptID']);
    await expectLater(
      SyncCodec.spOpen(
        envelope,
        code,
        now: DateTime.parse(facts['spExpiresAt']),
      ),
      throwsFormatException,
    );
  });
  test('GitHub双边变化停止；单边变化方向正确', () {
    expect(
      decideSync(local: 'a', baseFingerprint: 'a', remote: 'b', baseSHA: 'b'),
      SyncDecision.unchanged,
    );
    expect(
      decideSync(local: 'c', baseFingerprint: 'a', remote: 'b', baseSHA: 'b'),
      SyncDecision.upload,
    );
    expect(
      decideSync(local: 'a', baseFingerprint: 'a', remote: 'c', baseSHA: 'b'),
      SyncDecision.download,
    );
    expect(
      decideSync(local: 'c', baseFingerprint: 'a', remote: 'c', baseSHA: 'b'),
      SyncDecision.conflict,
    );
    expect(decideSync(local: 'a', remote: null), SyncDecision.initialize);
    expect(
      decideSync(local: 'a', baseSHA: 'b', remote: null),
      SyncDecision.conflict,
    );
  });
  test('GitHub配置路径和身份校验', () {
    expect(
      () => const GitHubConfig(path: '../secret').validate(),
      throwsFormatException,
    );
    expect(
      () => const GitHubConfig(branch: 'bad branch').validate(),
      throwsFormatException,
    );
    expect(
      const GitHubConfig(owner: 'ABC').identity,
      const GitHubConfig(owner: 'abc').identity,
    );
  });
  test('合并相同更新时间不同内容停止', () {
    final s = baseline();
    expect(
      () => mergeStates(
        s,
        s.copy(
          tasks: [
            s.tasks.single.patch({'title': '不同内容'}),
          ],
        ),
      ),
      throwsFormatException,
    );
  });
  test('SQLite原生样本读写、上次快照与并发保护', () async {
    final dir = await Directory.systemTemp.createTemp('space-flutter-core-');
    try {
      final repo = SpaceRepository(dir);
      final file = File(repo.path);
      await file.writeAsBytes(
        base64Decode(
          File(
            '${fixtures.path}/06-synthetic-sqlite.base64.txt',
          ).readAsStringSync(),
        ),
      );
      final loaded = await repo.load();
      expect(loaded.tasks.single.toJson(), baseline().tasks.single.toJson());
      final second = SpaceRepository(dir);
      await second.load();
      final saved = await repo.save(
        loaded.copy(
          tasks: [
            loaded.tasks.single.patch({'title': 'Flutter互通保存'}),
          ],
        ),
      );
      expect(
        repo.readFile(repo.previous).tasks.single.title,
        loaded.tasks.single.title,
      );
      expect(
        (await SpaceRepository(dir).load()).tasks.single.title,
        'Flutter互通保存',
      );
      await expectLater(second.save(loaded), throwsStateError);
      await repo.save(
        saved.copy(settings: {'dark': 'true'}),
        preferencesOnly: true,
      );
      expect(
        repo.readFile(repo.previous).tasks.single.title,
        loaded.tasks.single.title,
      );
      final export = '${dir.path}/export.sqlite';
      await repo.exportSQLite(export);
      expect(repo.readFile(export).tasks.single.title, 'Flutter互通保存');
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('损坏数据库不被初始化覆盖', () async {
    final dir = await Directory.systemTemp.createTemp('space-flutter-bad-');
    try {
      final repo = SpaceRepository(dir);
      final original = Uint8List.fromList([1, 2, 3, 4]);
      await File(repo.path).writeAsBytes(original);
      await expectLater(repo.load(), throwsA(anything));
      expect(File(repo.path).readAsBytesSync(), original);
      expect(repo.loaded, isFalse);
      await expectLater(repo.save(SpaceState()), throwsStateError);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('本地SP快照独占创建，防止覆盖已有包', () async {
    final dir = await Directory.systemTemp.createTemp('space-flutter-sp-');
    try {
      final transport = ManualTransport(dir.path, '', '');
      await transport.put('test.spacesync', [1, 2, 3]);
      expect(await transport.get('test.spacesync'), [1, 2, 3]);
      await expectLater(
        transport.put('test.spacesync', [4]),
        throwsA(anything),
      );
      expect(await transport.get('test.spacesync'), [1, 2, 3]);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
