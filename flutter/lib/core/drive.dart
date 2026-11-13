import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../host.dart';
import '../store.dart';
import 'models.dart';

Future<Uint8List> _encodeDriveBody(Object body) =>
    Isolate.run(() => Uint8List.fromList(utf8.encode(jsonEncode(body))));
Future<dynamic> _decodeDriveBody(Uint8List bytes) =>
    Isolate.run(() => jsonDecode(utf8.decode(bytes)));
Future<Uint8List> _decodeDriveBlob(String encoded) =>
    Isolate.run(() => base64Decode(encoded.replaceAll(RegExp(r'\s'), '')));
Future<String> _driveDigest(Uint8List bytes) =>
    Isolate.run(() => sha256.convert(bytes).toString());
Future<(String, String)> _prepareDriveFile(
  String source,
  int expectedSize,
  int expectedModified,
) => Isolate.run(() {
  final file = File(source);
  final stat = file.statSync();
  if (stat.size != expectedSize ||
      stat.modified.millisecondsSinceEpoch != expectedModified) {
    throw StateError('源文件已变化，请重新添加文件');
  }
  final bytes = file.readAsBytesSync();
  return (base64Encode(bytes), sha256.convert(bytes).toString());
});

String driveError(Object error) => error is StateError
    ? error.message.toString()
    : error is DriveError
    ? error.message
    : error is SocketException
    ? '无法连接仓库，请检查网络后重试。'
    : error.toString();

const driveFileLimit = 32 * 1024 * 1024;

enum UploadStatus {
  waiting,
  uploading,
  committing,
  failed,
  complete,
  cancelled,
  interrupted,
}

extension UploadLabel on UploadStatus {
  String get label => ['待上传', '上传中', '正在提交', '失败', '已完成', '已取消', '已中断'][index];
  bool get active =>
      this == UploadStatus.waiting ||
      this == UploadStatus.uploading ||
      this == UploadStatus.committing;
}

class DriveConfig {
  factory DriveConfig.fromAddress(
    String address, {
    required String branch,
    required String device,
  }) {
    var value = address.trim();
    if (value.contains('://')) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.toLowerCase() != 'github.com' ||
          uri.userInfo.isNotEmpty) {
        throw StateError('请输入 GitHub 仓库链接或账号/仓库');
      }
      value = uri.path;
    }
    final parts = value
        .replaceAll(RegExp(r'^/+|/+$'), '')
        .replaceFirst(RegExp(r'\.git$'), '')
        .split('/');
    if (parts.length != 2) throw StateError('请输入 GitHub 仓库链接或账号/仓库');
    final result = DriveConfig(
      owner: parts[0],
      repository: parts[1],
      branch: branch.trim(),
      device: device.trim(),
    );
    result.validate();
    return result;
  }
  final String owner, repository, branch, device;
  const DriveConfig({
    this.owner = '',
    this.repository = '',
    this.branch = 'space-drive',
    this.device = '',
  });
  bool get ready => owner.isNotEmpty && repository.isNotEmpty;
  Map<String, Object?> toJson() => {
    'owner': owner,
    'repository': repository,
    'branch': branch,
    'device': device,
  };
  factory DriveConfig.fromJson(Map j) => DriveConfig(
    owner: j['owner'] as String? ?? '',
    repository: j['repository'] as String? ?? '',
    branch: j['branch'] as String? ?? 'space-drive',
    device: j['device'] as String? ?? '',
  );
  void validate() {
    for (final part in [owner, repository]) {
      if (!RegExp(r'^[A-Za-z0-9_.-]{1,100}$').hasMatch(part) ||
          part == '.' ||
          part == '..') {
        throw StateError('GitHub账号或仓库名称无效');
      }
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_./-]{0,150}$').hasMatch(branch) ||
        branch.contains('..') ||
        branch.contains('//') ||
        branch.endsWith('/') ||
        branch.endsWith('.lock')) {
      throw StateError('分支名称无效');
    }
    if (device.trim().isEmpty || device.length > 80) {
      throw StateError('请填写来源设备名称（最多80字）');
    }
  }
}

class UploadTask {
  final String id, source, name, batch, device;
  final int size, modified;
  final DateTime created;
  UploadStatus status;
  double progress;
  String error, digest, blob;
  UploadTask({
    required this.id,
    required this.source,
    required this.name,
    required this.batch,
    required this.device,
    required this.size,
    required this.modified,
    required this.created,
    this.status = UploadStatus.waiting,
    this.progress = 0,
    this.error = '',
    this.digest = '',
    this.blob = '',
  });
  Map<String, Object?> toJson() => {
    'id': id,
    'source': source,
    'name': name,
    'batch': batch,
    'device': device,
    'size': size,
    'modified': modified,
    'created': created.toUtc().toIso8601String(),
    'status': status.name,
    'error': error,
    'digest': digest,
    'blob': blob,
  };
  factory UploadTask.fromJson(Map j) => UploadTask(
    id: j['id'] as String,
    source: j['source'] as String,
    name: j['name'] as String,
    batch: j['batch'] as String,
    device: j['device'] as String,
    size: j['size'] as int,
    modified: j['modified'] as int,
    created: DateTime.parse(j['created'] as String),
    status: UploadStatus.values.firstWhere((s) => s.name == j['status']),
    error: j['error'] as String? ?? '',
    digest: j['digest'] as String? ?? '',
    blob: j['blob'] as String? ?? '',
  );
}

class DriveFile {
  final String path, sha;
  final int size;
  final bool folder;
  final DateTime? created;
  final String device, digest;
  const DriveFile(
    this.path,
    this.sha,
    this.size, {
    this.folder = false,
    this.created,
    this.device = '',
    this.digest = '',
  });
  String get name => p.posix.basename(path);
}

class DriveError implements Exception {
  final String message;
  final int status;
  DriveError(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

/// No backup state, data or recovery keys enter this client.
class DriveApi {
  final DriveConfig config;
  final String token;
  final Uri _apiOrigin;
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30);
  DriveApi(this.config, this.token, {Uri? apiOrigin})
    : _apiOrigin = apiOrigin ?? Uri.parse('https://api.github.com');
  String get root => '/repos/${config.owner}/${config.repository}';
  void close() => client.close(force: true);
  Future<dynamic> request(
    String method,
    String suffix, {
    Object? body,
    void Function(double)? progress,
  }) async {
    final uri = _apiOrigin.resolve('$root$suffix');
    final req = await client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 30));
    req.followRedirects = false;
    req.headers.set('Authorization', 'Bearer $token');
    req.headers.set('User-Agent', 'Space-Drive');
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('X-GitHub-Api-Version', '2022-11-28');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      final encoded = await _encodeDriveBody(body);
      req.contentLength = encoded.length;
      for (var offset = 0; offset < encoded.length; offset += 65536) {
        final end = (offset + 65536).clamp(0, encoded.length);
        req.add(Uint8List.sublistView(encoded, offset, end));
        await req.flush().timeout(const Duration(seconds: 30));
        progress?.call(end / encoded.length);
      }
    }
    final response = await req.close().timeout(const Duration(seconds: 45));
    final bytes = BytesBuilder();
    await for (final chunk in response.timeout(const Duration(seconds: 45))) {
      bytes.add(chunk);
      if (bytes.length > 48 * 1024 * 1024) throw DriveError('仓库响应过大，请缩小目录范围');
    }
    final data = bytes.takeBytes();
    if (response.statusCode >= 300) {
      if (response.statusCode == 401) throw DriveError('访问令牌无效或过期', 401);
      if (response.statusCode == 429 ||
          response.headers.value('retry-after') != null ||
          response.headers.value('x-ratelimit-remaining') == '0') {
        throw DriveError('请求暂时受限，请稍后重试', 429);
      }
      final operation = switch ((method, suffix.split('?').first)) {
        ('POST', '/git/trees') => '创建网盘目录',
        ('POST', '/git/commits') => '创建网盘提交',
        ('POST', '/git/refs') => '创建网盘分支',
        ('POST', '/git/blobs') => '上传文件',
        ('GET', '') => '连接私有仓库',
        _ => 'GitHub请求',
      };
      String detail = '';
      try {
        final error = jsonDecode(utf8.decode(data)) as Map;
        final parts = <String>[
          if (error['message'] is String) error['message'] as String,
          if (error['errors'] is List)
            for (final item in error['errors'] as List)
              if (item is String)
                item
              else if (item is Map && item['message'] is String)
                item['message'] as String
              else if (item is Map && item['code'] is String)
                '${item['field'] ?? item['resource'] ?? ''}: ${item['code']}',
        ];
        detail = parts.join('；').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (token.isNotEmpty) detail = detail.replaceAll(token, '[已隐藏令牌]');
        detail = detail.replaceAll(
          RegExp(r'(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]+'),
          '[已隐藏令牌]',
        );
        if (detail.length > 360) detail = '${detail.substring(0, 360)}…';
      } catch (_) {
        // HTML and arbitrary server responses are not displayed in the form.
      }
      throw DriveError(
        '$operation失败（${response.statusCode}）${detail.isEmpty ? '，请稍后重试或核对仓库权限' : '：$detail'}',
        response.statusCode,
      );
    }
    return _decodeDriveBody(data);
  }

  Future<String> head() async =>
      (await request(
            'GET',
            '/git/ref/heads/${Uri.encodeComponent(config.branch)}',
          ))['object']['sha']
          as String;
  Future<Map<String, dynamic>> tree(String sha) async =>
      Map<String, dynamic>.from(await request('GET', '/git/trees/$sha'));
  Future<void> validate() async {
    final repo = await request('GET', '');
    if (repo['private'] != true) throw DriveError('文件网盘仅支持私有仓库');
    try {
      await head();
    } on DriveError catch (e) {
      if (e.status != 404) rethrow;
      // GitHub rejects a new tree with no entries. Seed only the empty drive
      // index; the orphan commit must not copy or change any backup branch.
      final tree = await request(
        'POST',
        '/git/trees',
        body: {
          'tree': [
            {
              'path': '.space-drive/index.json',
              'mode': '100644',
              'type': 'blob',
              'content': '{}',
            },
          ],
        },
      );
      final commit = await request(
        'POST',
        '/git/commits',
        body: {
          'message': 'Initialize Space file drive',
          'tree': tree['sha'],
          'parents': [],
        },
      );
      try {
        await request(
          'POST',
          '/git/refs',
          body: {'ref': 'refs/heads/${config.branch}', 'sha': commit['sha']},
        );
      } on DriveError catch (creationError) {
        if (creationError.status != 422) rethrow;
        // Another computer may have created the same branch meanwhile.
        try {
          await head();
        } on DriveError {
          throw creationError;
        }
      }
    }
  }

  Future<String> blob(
    String content, {
    void Function(double)? progress,
  }) async =>
      (await request(
            'POST',
            '/git/blobs',
            body: {'content': content, 'encoding': 'base64'},
            progress: progress,
          ))['sha']
          as String;
  Future<Uint8List> downloadBlob(String sha) async {
    final result = await request('GET', '/git/blobs/$sha');
    final encoded = result['content'] as String;
    return _decodeDriveBlob(encoded);
  }

  Future<Map<String, dynamic>> indexAt(String ref) async {
    try {
      final content = await request(
        'GET',
        '/contents/.space-drive/index.json?ref=${Uri.encodeComponent(ref)}',
      );
      final bytes =
          content['encoding'] == 'base64' &&
              (content['content'] as String? ?? '').isNotEmpty
          ? base64Decode(
              (content['content'] as String).replaceAll(RegExp(r'\s'), ''),
            )
          : await downloadBlob(content['sha'] as String);
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
    } on DriveError catch (e) {
      if (e.status == 404) return {};
      rethrow;
    }
  }

  Future<void> commit(
    List<Map<String, Object?>> changes, {
    List<Map<String, Object?>> records = const [],
    String? remove,
  }) async {
    for (var retry = 0; retry < 3; retry++) {
      final parent = await head();
      final base = (await request(
        'GET',
        '/git/commits/$parent',
      ))['tree']['sha'];
      final index = await indexAt(parent);
      for (final record in records) {
        index[record['id'] as String] = record;
      }
      if (remove != null) index.remove(remove);
      final next = [
        ...changes,
        {
          'path': '.space-drive/index.json',
          'mode': '100644',
          'type': 'blob',
          'content': jsonEncode(index),
        },
      ];
      final tree = await request(
        'POST',
        '/git/trees',
        body: {'base_tree': base, 'tree': next},
      );
      final commit = await request(
        'POST',
        '/git/commits',
        body: {
          'message': 'Space file drive update',
          'tree': tree['sha'],
          'parents': [parent],
        },
      );
      try {
        await request(
          'PATCH',
          '/git/refs/heads/${Uri.encodeComponent(config.branch)}',
          body: {'sha': commit['sha'], 'force': false},
        );
        return;
      } on DriveError catch (e) {
        if (e.status != 409 && e.status != 422) rethrow;
      }
    }
    throw DriveError('其他设备正在更新仓库，请稍后重试');
  }
}

final _drives = Expando<DriveService>();
DriveService driveFor(SpaceStore store) => _drives[store] ??= DriveService(
  Directory('${store.repository.directory.path}/file-drive'),
);

class DriveService extends ChangeNotifier {
  final Directory directory;
  final DriveApi Function(DriveConfig, String) apiFactory;
  DriveService(
    this.directory, {
    DriveApi Function(DriveConfig, String)? apiFactory,
  }) : apiFactory = apiFactory ?? DriveApi.new;
  DriveConfig config = const DriveConfig();
  final List<UploadTask> tasks = [];
  String token = '', message = '';
  bool initialized = false,
      scanning = false,
      _pumping = false,
      _stopping = false;
  int discovered = 0, _scanGeneration = 0;
  final Map<String, DriveApi> _active = {};
  Future<void> _writes = Future.value();
  String? activeBatch;
  bool get active => scanning || tasks.any((t) => t.status.active);
  Future<void>? _initialization;
  Future<void> initialize() {
    if (initialized) return Future.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    directory.createSync(recursive: true);
    final state = File('${directory.path}/state.json');
    try {
      if (await state.exists()) {
        if (await state.length() > 8 * 1024 * 1024) throw StateError('上传记录过大');
        final data = jsonDecode(await state.readAsString()) as Map;
        config = DriveConfig.fromJson(data['config'] as Map);
        for (final row in data['tasks'] as List) {
          final task = UploadTask.fromJson(row as Map);
          if (task.status.active) task.status = UploadStatus.interrupted;
          tasks.add(task);
        }
        activeBatch = tasks.lastOrNull?.batch;
      }
    } catch (_) {
      message = '上传记录读取失败，原文件已保留。请检查本机文件管理目录。';
    }
    try {
      if (config.ready) {
        token = await DesktopHost.secret('file-drive-token') ?? '';
      }
    } catch (_) {
      message = '无法读取网盘令牌，请重新连接。';
    }
    initialized = true;
    notifyListeners();
  }

  Future<void> persist() {
    final data = jsonEncode({
      'config': config.toJson(),
      'tasks': tasks.map((t) => t.toJson()).toList(),
    });
    final next = _writes.catchError((Object _) {}).then((_) async {
      final file = File('${directory.path}/state.json');
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(data, flush: true);
      await temp.rename(file.path);
    });
    _writes = next;
    return next;
  }

  void changed() {
    notifyListeners();
  }

  Future<void> connect(DriveConfig next, String secret) async {
    if (active) throw StateError('请先等待或取消当前上传，再修改仓库连接');
    next.validate();
    if (secret.trim().isEmpty) throw StateError('请输入访问令牌');
    final api = apiFactory(next, secret.trim());
    try {
      await api.validate();
    } finally {
      api.close();
    }
    await DesktopHost.saveSecret('file-drive-token', secret.trim());
    _lastHead = null;
    _connectionGeneration++;
    _cachedFiles = [];
    _targets.clear();
    config = next;
    token = secret.trim();
    await persist();
    message = '已连接私有仓库';
    changed();
  }

  static String safeName(String name) {
    final parts = p.posix.split(name.replaceAll('\\', '/'));
    if (parts.any(
          (s) =>
              s.isEmpty ||
              s == '.' ||
              s == '..' ||
              s.endsWith('.') ||
              s.endsWith(' ') ||
              RegExp(r'[\x00-\x1f<>:"|?*]').hasMatch(s) ||
              RegExp(
                r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
                caseSensitive: false,
              ).hasMatch(s),
        ) ||
        name.length > 240) {
      throw StateError('文件名不兼容：$name');
    }
    return parts.join('/');
  }

  Future<void> add(List<String> paths) async {
    if (!config.ready || token.isEmpty) throw StateError('请先配置文件网盘连接');
    if (scanning) throw StateError('正在扫描文件夹，请稍候');
    _stopping = false;
    scanning = true;
    discovered = 0;
    final scan = ++_scanGeneration;
    final batch = uid();
    activeBatch = batch;
    changed();
    try {
      Future<void> addFile(File file, String name) async {
        if (scan != _scanGeneration) return;
        final stat = await file.stat();
        final valid = safeName(name);
        if (tasks.length >= 10000) throw StateError('本机记录已达10000条，请清理已结束记录');
        final task = UploadTask(
          id: uid(),
          source: file.path,
          name: valid,
          batch: batch,
          device: config.device,
          size: stat.size,
          modified: stat.modified.millisecondsSinceEpoch,
          created: DateTime.now(),
        );
        if (stat.size > driveFileLimit) {
          task.status = UploadStatus.failed;
          task.error = '超过单文件32 MiB限制';
        }
        tasks.add(task);
        discovered++;
        if (discovered % 16 == 0) {
          await persist();
          changed();
          unawaited(_pump());
        }
      }

      for (final source in paths) {
        if (scan != _scanGeneration) break;
        final type = await FileSystemEntity.type(source, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          await for (final entry in Directory(
            source,
          ).list(recursive: true, followLinks: false)) {
            if (scan != _scanGeneration) break;
            if (entry is File) {
              await addFile(
                entry,
                p.posix.join(
                  p.basename(source),
                  p
                      .relative(entry.path, from: source)
                      .split(p.separator)
                      .join('/'),
                ),
              );
            }
          }
        } else if (type == FileSystemEntityType.file) {
          await addFile(File(source), p.basename(source));
        }
      }
    } finally {
      scanning = false;
      await persist();
      changed();
      unawaited(_pump());
    }
  }

  Future<void> _pump() async {
    if (_pumping || _stopping) return;
    _pumping = true;
    try {
      while (!_stopping) {
        final batch = tasks
            .where((t) => t.status == UploadStatus.waiting)
            .take(8)
            .toList();
        if (batch.isEmpty) break;
        final api = apiFactory(config, token);
        final staged = <UploadTask>[];
        final changes = <Map<String, Object?>>[];
        final records = <Map<String, Object?>>[];
        try {
          final existing = await api.indexAt(config.branch);
          for (final task in batch) {
            if (_stopping) break;
            final uploadApi = apiFactory(config, token);
            _active[task.id] = uploadApi;
            try {
              task.status = UploadStatus.uploading;
              task.error = '';
              task.progress = 0;
              await persist();
              changed();
              if (existing.containsKey(task.id)) {
                task.status = UploadStatus.complete;
                task.progress = 1;
                continue;
              }
              final source = task.source;
              final expectedSize = task.size;
              final expectedModified = task.modified;
              final encoded = await _prepareDriveFile(
                source,
                expectedSize,
                expectedModified,
              );
              if (task.status == UploadStatus.cancelled || _stopping) continue;
              task.digest = encoded.$2;
              task.blob = await uploadApi.blob(
                encoded.$1,
                progress: (v) {
                  if (task.status == UploadStatus.uploading) {
                    task.progress = v * .98;
                    changed();
                  }
                },
              );
              if (task.status == UploadStatus.cancelled || _stopping) continue;
              task.status = UploadStatus.committing;
              task.progress = .99;
              staged.add(task);
              await persist();
              changed();
              final target = 'files/${task.id}/${task.name}';
              changes.add({
                'path': target,
                'mode': '100644',
                'type': 'blob',
                'sha': task.blob,
              });
              records.add({
                'id': task.id,
                'path': task.name,
                'stored': target,
                'blob': task.blob,
                'size': task.size,
                'sha256': task.digest,
                'created': task.created.toUtc().toIso8601String(),
                'device': task.device,
              });
            } catch (e) {
              if (task.status != UploadStatus.cancelled) {
                task.status = _stopping
                    ? UploadStatus.interrupted
                    : UploadStatus.failed;
                task.error = driveError(e);
              }
            } finally {
              _active.remove(task.id);
              uploadApi.close();
              changed();
            }
          }
          if (staged.isNotEmpty) {
            await api.commit(changes, records: records);
            for (final task in staged) {
              task.status = UploadStatus.complete;
              task.progress = 1;
            }
          }
        } catch (e) {
          for (final task in batch) {
            if (task.status.active) {
              task.status = _stopping
                  ? UploadStatus.interrupted
                  : UploadStatus.failed;
              task.error = driveError(e);
            }
          }
        } finally {
          api.close();
          await persist();
          changed();
        }
      }
    } finally {
      _pumping = false;
      changed();
    }
  }

  Future<void> cancel(UploadTask task) async {
    if (task.status == UploadStatus.committing) {
      message = '正在确认远端提交，请完成后再删除网盘文件';
      changed();
      return;
    }
    task.status = UploadStatus.cancelled;
    _active[task.id]?.close();
    await persist();
    changed();
  }

  Future<void> retry(UploadTask task) async {
    if (task.status.active) return;
    task.status = UploadStatus.waiting;
    task.error = '';
    _stopping = false;
    await persist();
    changed();
    unawaited(_pump());
  }

  Future<void> remove(UploadTask task) async {
    if (task.status.active) throw StateError('请先取消上传');
    tasks.remove(task);
    await persist();
    changed();
  }

  Future<void> stop() async {
    _stopping = true;
    _scanGeneration++;
    for (final task in tasks) {
      if (task.status == UploadStatus.committing) continue;
      if (task.status.active) {
        task.status = UploadStatus.interrupted;
        _active[task.id]?.close();
      }
    }
    while (_pumping || scanning) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await persist();
    changed();
  }

  Future<List<DriveFile>> list() async {
    if (!config.ready || token.isEmpty) throw StateError('请先连接私有仓库');
    final generation = _connectionGeneration;
    final api = apiFactory(config, token);
    try {
      final head = await api.head();
      if (generation != _connectionGeneration) throw StateError('仓库连接已变化，请刷新');
      if (head == _lastHead) return _cachedFiles;
      final index = await api.indexAt(head);
      if (generation != _connectionGeneration) throw StateError('仓库连接已变化，请刷新');
      final found = <DriveFile>[];
      _targets.clear();
      for (final value in index.values) {
        final data = Map<String, dynamic>.from(value as Map);
        final created = DateTime.tryParse(data['created'] as String);
        final file = DriveFile(
          data['path'] as String,
          data['blob'] as String? ?? '',
          data['size'] as int,
          created: created,
          device: data['device'] as String? ?? '',
          digest: data['sha256'] as String? ?? '',
        );
        found.add(file);
        _targets['${file.path}|${created?.toUtc().toIso8601String()}'] =
            data['stored'] as String;
      }
      found.sort(
        (a, b) => (b.created ?? DateTime(1970)).compareTo(
          a.created ?? DateTime(1970),
        ),
      );
      _lastHead = head;
      _cachedFiles = found;
      return found;
    } finally {
      api.close();
    }
  }

  String? _lastHead;
  int _connectionGeneration = 0;
  List<DriveFile> _cachedFiles = [];
  final _targets = <String, String>{};
  String target(DriveFile file) =>
      _targets['${file.path}|${file.created?.toUtc().toIso8601String()}'] ??
      (throw StateError('文件目录已变化，请刷新'));
  Future<File> download(DriveFile file, {String? destination}) async {
    final api = apiFactory(config, token);
    try {
      final remote = await api.request(
        'GET',
        '/contents/${target(file).split('/').map(Uri.encodeComponent).join('/')}?ref=${Uri.encodeComponent(config.branch)}',
      );
      final bytes = await api.downloadBlob(remote['sha'] as String);
      if (file.digest.isNotEmpty && await _driveDigest(bytes) != file.digest) {
        throw StateError('文件校验失败，请重新下载');
      }
      final cache = Directory('${directory.path}/cache');
      await cache.create(recursive: true);
      final output = File(
        destination ??
            '${cache.path}/${file.digest.substring(0, 12)}-${file.name}',
      );
      final temp = File('${output.path}.space-download');
      try {
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(output.path);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
      return output;
    } finally {
      api.close();
    }
  }

  Future<void> delete(DriveFile file) async {
    if (active) throw StateError('请等待当前上传完成后删除远端文件');
    final stored = target(file);
    final id = stored.split('/')[1];
    final api = apiFactory(config, token);
    try {
      await api.commit([
        {'path': stored, 'mode': '100644', 'type': 'blob', 'sha': null},
      ], remove: id);
    } finally {
      api.close();
    }
  }
}
