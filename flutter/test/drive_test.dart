import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/drive.dart';

class FakeRemote {
  final Map<String, dynamic> index = {};
  final Map<String, Uint8List> blobs = {};
  int revision = 0, commits = 0;
}

class FakeDriveApi extends DriveApi {
  final FakeRemote remote;
  FakeDriveApi(super.config, super.token, this.remote);
  @override
  Future<Map<String, dynamic>> indexAt(String ref) async =>
      Map.of(remote.index);
  @override
  Future<String> head() async => 'head-${remote.revision}';
  @override
  Future<String> blob(String content, {void Function(double)? progress}) async {
    final bytes = base64Decode(content);
    final id = sha256.convert(bytes).toString();
    remote.blobs[id] = bytes;
    progress?.call(1);
    return id;
  }

  @override
  Future<Uint8List> downloadBlob(String sha) async => remote.blobs[sha]!;
  @override
  Future<void> commit(
    List<Map<String, Object?>> changes, {
    List<Map<String, Object?>> records = const [],
    String? remove,
  }) async {
    for (final r in records) {
      remote.index[r['id'] as String] = r;
    }
    if (remove != null) remote.index.remove(remove);
    remote.revision++;
    remote.commits++;
  }
}

class RacingApi extends DriveApi {
  bool raced = false;
  Map<String, dynamic> lastTree = {};
  RacingApi()
    : super(
        const DriveConfig(owner: 'test', repository: 'test', device: 'test'),
        'fake',
      );
  @override
  Future<String> head() async => raced ? 'second' : 'first';
  @override
  Future<Map<String, dynamic>> indexAt(String ref) async => {
    'existing': {'path': 'existing.txt'},
    if (raced) 'other-computer': {'path': 'new.txt'},
  };
  @override
  Future<dynamic> request(
    String method,
    String suffix, {
    Object? body,
    void Function(double)? progress,
  }) async {
    if (method == 'GET') {
      return {
        'tree': {'sha': 'base'},
      };
    }
    final data = body as Map;
    if (suffix == '/git/trees') {
      lastTree = Map<String, dynamic>.from(data);
      return {'sha': 'tree'};
    }
    if (suffix == '/git/commits') return {'sha': 'commit'};
    if (method == 'PATCH') {
      expect(data['force'], false);
      if (!raced) {
        raced = true;
        throw DriveError('conflict', 409);
      }
      return {};
    }
    throw StateError('Unexpected request');
  }
}

class InitializingApi extends DriveApi {
  bool branchExists;
  final bool race;
  final List<(String, String, Object?)> calls = [];
  InitializingApi({this.branchExists = false, this.race = false})
    : super(
        const DriveConfig(owner: 'test', repository: 'backup', device: 'test'),
        'fake',
      );

  @override
  Future<dynamic> request(
    String method,
    String suffix, {
    Object? body,
    void Function(double)? progress,
  }) async {
    calls.add((method, suffix, body));
    if (method == 'GET' && suffix.isEmpty) return {'private': true};
    if (method == 'GET' && suffix.startsWith('/git/ref/heads/')) {
      if (!branchExists) throw DriveError('Not Found', 404);
      return {
        'object': {'sha': 'branch-head'},
      };
    }
    if (method == 'POST' && suffix == '/git/trees') {
      final entries = (body as Map)['tree'] as List;
      if (entries.isEmpty) {
        throw DriveError('Tree does not contain any files', 422);
      }
      return {'sha': 'seeded-tree'};
    }
    if (method == 'POST' && suffix == '/git/commits') {
      return {'sha': 'orphan-commit'};
    }
    if (method == 'POST' && suffix == '/git/refs') {
      branchExists = true;
      if (race) throw DriveError('Reference already exists', 422);
      return {'ref': 'refs/heads/space-drive'};
    }
    throw StateError('Unexpected request: $method $suffix');
  }
}

void main() {
  test('首次连接创建带空索引的独立分支，不发送空树也不修改备份分支', () async {
    final api = InitializingApi();
    addTearDown(api.close);
    await api.validate();
    final tree =
        api.calls.singleWhere((call) => call.$2 == '/git/trees').$3 as Map;
    expect(tree.containsKey('base_tree'), false);
    final entry = (tree['tree'] as List).single as Map;
    expect(entry['path'], '.space-drive/index.json');
    expect(entry['content'], '{}');
    expect(entry['mode'], '100644');
    final commit =
        api.calls.singleWhere((call) => call.$2 == '/git/commits').$3 as Map;
    expect(commit['parents'], isEmpty);
    final ref =
        api.calls.singleWhere((call) => call.$2 == '/git/refs').$3 as Map;
    expect(ref['ref'], 'refs/heads/space-drive');
    expect(api.calls.any((call) => call.$1 == 'PATCH'), false);
  });

  test('分支已存在时连接只读校验，不创建新提交', () async {
    final api = InitializingApi(branchExists: true);
    addTearDown(api.close);
    await api.validate();
    expect(api.calls.every((call) => call.$1 == 'GET'), true);
  });

  test('另一台电脑同时创建分支后，重新确认远端分支并连接成功', () async {
    final api = InitializingApi(race: true);
    addTearDown(api.close);
    await api.validate();
    expect(
      api.calls.where((call) => call.$2.startsWith('/git/ref/heads/')).length,
      2,
    );
  });

  test('HTTP 422 保留失败操作与服务端具体原因，并隐藏令牌', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    const token = 'ghp_test_secret_123';
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 422;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'message': 'Validation Failed',
          'errors': [
            {'message': 'Tree does not contain any files'},
            {'message': token},
          ],
        }),
      );
      await request.response.close();
    });
    final api = DriveApi(
      const DriveConfig(owner: 'test', repository: 'test'),
      token,
      apiOrigin: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    addTearDown(api.close);
    await expectLater(
      api.request('POST', '/git/trees', body: {'tree': []}),
      throwsA(
        isA<DriveError>()
            .having((e) => e.status, 'status', 422)
            .having((e) => e.message, 'operation', contains('创建网盘目录'))
            .having(
              (e) => e.message,
              'detail',
              contains('Tree does not contain any files'),
            )
            .having((e) => e.message, 'secret', isNot(contains(token))),
      ),
    );
  });

  test('远端并发后重新合并目录，不强推也不丢其他设备文件', () async {
    final api = RacingApi();
    addTearDown(api.close);
    await api.commit(
      [
        {'path': 'files/new', 'mode': '100644', 'type': 'blob', 'sha': 'blob'},
      ],
      records: [
        {'id': 'local', 'path': 'mine.txt'},
      ],
    );
    expect(api.lastTree['base_tree'], 'base');
    final rows = api.lastTree['tree'] as List;
    final index = jsonDecode(rows.last['content'] as String) as Map;
    expect(index.keys, containsAll(['existing', 'other-computer', 'local']));
  });
  test('跨平台路径校验拒绝越界、Windows保留名和非法字符', () {
    for (final name in [
      '../a.txt',
      'CON.txt',
      'a:b.txt',
      'folder/../x',
      'folder/a.',
    ]) {
      expect(() => DriveService.safeName(name), throwsStateError);
    }
    expect(DriveService.safeName('资料/清单.pdf'), '资料/清单.pdf');
  });
  test('后台队列保存、跨设备列表、记录删除不删远端、刷新和远端删除', () async {
    final dir = await Directory.systemTemp.createTemp('space232-drive-');
    addTearDown(() => dir.delete(recursive: true));
    final remote = FakeRemote();
    DriveApi factory(DriveConfig c, String t) => FakeDriveApi(c, t, remote);
    final service = DriveService(dir, apiFactory: factory)
      ..config = const DriveConfig(
        owner: 'test',
        repository: 'repo',
        device: '电脑A',
      )
      ..token = 'fake';
    final f = File('${dir.path}/source.txt');
    await f.writeAsString('测试正文');
    await service.add([f.path]);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (service.active && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(
      service.tasks.single.status,
      UploadStatus.complete,
      reason: service.tasks.single.error,
    );
    expect(remote.commits, 1);
    final second =
        DriveService(Directory('${dir.path}/second'), apiFactory: factory)
          ..config = service.config
          ..token = 'fake';
    final entries = await second.list();
    expect(entries.single.name, 'source.txt');
    expect(entries.single.device, '电脑A');
    expect(entries.single.created, isNotNull);
    await service.remove(service.tasks.single);
    expect(remote.index, isNotEmpty);
    await second.delete(entries.single);
    expect(await second.list(), isEmpty);
    final persisted =
        jsonDecode(await File('${dir.path}/state.json').readAsString()) as Map;
    expect(persisted['tasks'], isEmpty);
  });
}
