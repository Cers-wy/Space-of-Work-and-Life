import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'models.dart';

class SyncCodec {
  static final aes = AesGcm.with256bits();
  static final header = utf8.encode('SPACE-GITHUB-1\n');
  static String fingerprint(SpaceState s) => sha256
      .convert(utf8.encode(swiftJson(s.toJson(portable: true))))
      .toString();
  static String gitBlob(List<int> bytes) => sha1.convert([
    ...utf8.encode('blob ${bytes.length}\x00'),
    ...bytes,
  ]).toString();
  static List<int> recoveryKey(String key) {
    final k = base64Decode(key.trim());
    if (k.length != 32) invalid('恢复密钥必须为32字节Base64');
    return k;
  }

  // Legacy Base64 recovery keys remain compatible with the original envelope.
  static List<int>? _legacyKey(String value) {
    try {
      final bytes = base64Decode(value.trim());
      if (bytes.length == 32) return bytes;
    } on FormatException {
      /* User-set passphrase. */
    }
    return null;
  }

  static void validateGitHubKey(String value) {
    if (_legacyKey(value) != null) return;
    final key = value.trim();
    if (key.runes.length < 12 ||
        utf8.encode(key).length > 1024 ||
        controls(key)) {
      invalid('恢复密钥请至少填写12个字符，最多1024字节');
    }
  }

  static Future<List<int>> _passphraseKey(String value, List<int> salt) async {
    validateGitHubKey(value);
    return (await Pbkdf2.hmacSha256(
          iterations: 210000,
          bits: 256,
        ).deriveKeyFromPassword(password: value.trim(), nonce: salt))
        .extractBytes();
  }

  static String newRecoveryKey() =>
      base64Encode(List.generate(32, (_) => Random.secure().nextInt(256)));
  static Future<Uint8List> _seal(
    List<int> bytes,
    List<int> key, {
    List<int> aad = const [],
  }) async {
    final box = await aes.encrypt(bytes, secretKey: SecretKey(key), aad: aad);
    return Uint8List.fromList([
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  static Future<Uint8List> _open(
    List<int> bytes,
    List<int> key, {
    List<int> aad = const [],
  }) async {
    if (bytes.length < 28) invalid('加密包不完整');
    try {
      return Uint8List.fromList(
        await aes.decrypt(
          SecretBox(
            bytes.sublist(12, bytes.length - 16),
            nonce: bytes.sublist(0, 12),
            mac: Mac(bytes.sublist(bytes.length - 16)),
          ),
          secretKey: SecretKey(key),
          aad: aad,
        ),
      );
    } catch (_) {
      invalid('密钥不正确或加密包被修改');
    }
  }

  static final passphraseHeader = utf8.encode('SPACE-GITHUB-2\n');
  static Future<Uint8List> githubSeal(SpaceState state, String key) async {
    validateGitHubKey(key);
    final legacy = _legacyKey(key);
    final salt = legacy == null
        ? List.generate(16, (_) => Random.secure().nextInt(256))
        : <int>[];
    final prefix = [...(legacy == null ? passphraseHeader : header), ...salt];
    final bytes = Uint8List.fromList([
      ...prefix,
      ...await _seal(
        utf8.encode(swiftJson(state.toJson(portable: true))),
        legacy ?? await _passphraseKey(key, salt),
        aad: prefix,
      ),
    ]);
    if (bytes.length > 24 * 1024 * 1024) invalid('GitHub加密包超过24 MB');
    return bytes;
  }

  static Future<SpaceState> githubOpen(List<int> bytes, String key) async {
    if (bytes.length > 24 * 1024 * 1024 || bytes.length < header.length + 28) {
      invalid('不是有效的GitHub备份包');
    }
    final magic = utf8.decode(
      bytes.take(header.length).toList(),
      allowMalformed: true,
    );
    final v2 = magic == utf8.decode(passphraseHeader);
    if (!v2 && magic != utf8.decode(header)) invalid('不是有效的GitHub备份包');
    final offset = header.length + (v2 ? 16 : 0);
    if (bytes.length < offset + 28) invalid('GitHub加密包不完整');
    final secret = v2
        ? await _passphraseKey(key, bytes.sublist(header.length, offset))
        : recoveryKey(key);
    return SpaceState.fromJson(
      jsonDecode(
            utf8.decode(
              await _open(
                bytes.sublist(offset),
                secret,
                aad: bytes.sublist(0, offset),
              ),
            ),
          )
          as Map<String, dynamic>,
    );
  }

  static String cleanCode(String code) {
    var c = code.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (c.startsWith('SP')) c = c.substring(2);
    if (!RegExp(r'^[0-9A-F]{32}$').hasMatch(c)) invalid('请输入完整SP验证码');
    return c;
  }

  static String newCode() {
    final r = Random.secure();
    final h = List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join().toUpperCase();
    return 'SP-${List.generate(8, (i) => h.substring(i * 4, i * 4 + 4)).join('-')}';
  }

  static String receipt(String code) =>
      sha256.convert(utf8.encode(cleanCode(code))).toString();
  static List<int> _spKey(String code) => sha256
      .convert(
        utf8.encode('Space encrypted SQLite backup v1:${cleanCode(code)}'),
      )
      .bytes;
  static Future<String> spSeal(
    List<int> database,
    String code, {
    DateTime? now,
  }) async {
    if (database.length > 32 * 1024 * 1024) invalid('数据库超过32 MB');
    final time = (now ?? DateTime.now()).toUtc();
    final body = {
      'database': base64Encode(database),
      'digest': sha256.convert(database).toString(),
      'createdAt': time.millisecondsSinceEpoch / 1000 - 978307200,
      'expiresAt':
          time.add(const Duration(days: 7)).millisecondsSinceEpoch / 1000 -
          978307200,
    };
    return jsonEncode({
      'format': 1,
      'sealed': base64Encode(
        await _seal(utf8.encode(jsonEncode(body)), _spKey(code)),
      ),
    });
  }

  static Future<Uint8List> spOpen(
    String envelope,
    String code, {
    DateTime? now,
  }) async {
    if (utf8.encode(envelope).length > 64 * 1024 * 1024) invalid('下载信封超过64 MB');
    final j = jsonDecode(envelope) as Map<String, dynamic>;
    if (j['format'] != 1) invalid('不支持同步包版本');
    final body =
        jsonDecode(
              utf8.decode(
                await _open(base64Decode(j['sealed'] as String), _spKey(code)),
              ),
            )
            as Map<String, dynamic>;
    final time =
        (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch / 1000 -
        978307200;
    if ((body['expiresAt'] as num) <= time) invalid('验证码已超过7天有效期');
    if ((body['createdAt'] as num) > time + 300) invalid('备份创建时间异常');
    final bytes = base64Decode(body['database'] as String);
    if (bytes.length > 32 * 1024 * 1024 ||
        sha256.convert(bytes).toString() != body['digest']) {
      invalid('数据库长度或摘要校验失败');
    }
    return bytes;
  }
}

enum SyncDecision { initialize, connect, unchanged, upload, download, conflict }

SyncDecision decideSync({
  required String local,
  String? baseFingerprint,
  String? remote,
  String? baseSHA,
}) {
  if (remote == null) {
    return baseSHA == null ? SyncDecision.initialize : SyncDecision.conflict;
  }
  if (baseSHA == null || baseFingerprint == null) return SyncDecision.connect;
  final localChanged = local != baseFingerprint,
      remoteChanged = remote != baseSHA;
  if (localChanged && remoteChanged) return SyncDecision.conflict;
  if (localChanged) return SyncDecision.upload;
  if (remoteChanged) return SyncDecision.download;
  return SyncDecision.unchanged;
}

SpaceState mergeStates(SpaceState local, SpaceState remote) {
  local.validate();
  remote.validate();
  final projects = [...local.projects];
  final remap = <String, String>{};
  for (final p in remote.projects) {
    final sameID = projects.where((x) => x.id == p.id).firstOrNull;
    if (sameID != null &&
        (sameID.name.toLowerCase() != p.name.toLowerCase() ||
            sameID.disabled != p.disabled)) {
      invalid('项目ID冲突，备份后明确替换');
    }
    final sameName = projects
        .where((x) => x.name.toLowerCase() == p.name.toLowerCase())
        .firstOrNull;
    if (sameName != null) {
      remap[p.id] = sameName.id;
    } else {
      projects.add(p);
      remap[p.id] = p.id;
    }
  }
  final tasks = {for (final t in local.tasks) t.id: t};
  for (var t in remote.tasks) {
    if (t.projectID != null) t = t.patch({'projectID': remap[t.projectID]});
    final old = tasks[t.id];
    if (old == null) {
      tasks[t.id] = t;
      continue;
    }
    if (jsonEncode(sortedObject(old.toJson())) ==
        jsonEncode(sortedObject(t.toJson()))) {
      continue;
    }
    final cmp = validTime(t.updatedAt).compareTo(validTime(old.updatedAt));
    if (cmp == 0) invalid('相同更新时间存在不同任务内容，不能自动合并');
    if (cmp > 0) tasks[t.id] = t;
  }
  final statuses = [...local.statuses], disabled = [...local.disabledStatuses];
  for (final s in remote.statuses) {
    if (!statuses.contains(s)) {
      statuses.insert(statuses.indexOf('done'), s);
      if (remote.disabledStatuses.contains(s)) disabled.add(s);
    }
  }
  final result = local.copy(
    tasks: tasks.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
    projects: projects,
    statuses: statuses,
    disabledStatuses: disabled,
    settings: {
      ...local.settings,
      for (final e in remote.settings.entries)
        if (!e.key.startsWith('sync.')) e.key: e.value,
    },
  );
  result.validate();
  return result;
}
