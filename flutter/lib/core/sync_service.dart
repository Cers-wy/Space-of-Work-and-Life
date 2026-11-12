import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../host.dart';
import '../store.dart';
import 'invoices.dart';
import 'models.dart';
import 'sync.dart';

class GitHubConfig {
  final String owner, repository, branch, path;
  const GitHubConfig({
    this.owner = 'Cers-wy',
    this.repository = 'space-sync-data',
    this.branch = 'main',
    this.path = 'backups/latest.space',
  });
  String get url => 'https://github.com/$owner/$repository';
  factory GitHubConfig.fromUrl(
    String value, {
    String branch = 'main',
    String path = 'backups/latest.space',
  }) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.hasPort) {
      invalid('请输入GitHub仓库地址，例如 https://github.com/账号/仓库');
    }
    final parts = uri.pathSegments.toList();
    if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
    if (parts.length != 2) invalid('仓库地址应为 https://github.com/账号/仓库');
    final result = GitHubConfig(
      owner: parts[0],
      repository: parts[1].replaceFirst(RegExp(r'\.git$'), ''),
      branch: branch,
      path: path,
    );
    result.validate();
    return result;
  }
  factory GitHubConfig.fromJson(Map<String, dynamic> j) => GitHubConfig(
    owner: j['owner'] as String,
    repository: j['repository'] as String,
    branch: j['branch'] as String,
    path: j['path'] as String,
  );
  Map<String, dynamic> toJson() => {
    'owner': owner,
    'repository': repository,
    'branch': branch,
    'path': path,
  };
  String get identity => sha256
      .convert(
        utf8.encode(
          '${owner.toLowerCase()}/${repository.toLowerCase()}\n$branch\n$path',
        ),
      )
      .toString();
  void validate() {
    for (final name in [owner, repository]) {
      if (!RegExp(r'^[a-zA-Z0-9_.-]{1,100}$').hasMatch(name) ||
          name == '.' ||
          name == '..') {
        invalid('GitHub账号或仓库名称无效');
      }
    }
    if (branch.isEmpty ||
        utf8.encode(branch).length > 255 ||
        RegExp(r'\s').hasMatch(branch) ||
        controls(branch)) {
      invalid('GitHub分支无效');
    }
    if (path.isEmpty ||
        utf8.encode(path).length > 512 ||
        controls(path) ||
        path.contains('\\') ||
        path
            .split('/')
            .any(
              (x) =>
                  x.isEmpty ||
                  x == '.' ||
                  x == '..' ||
                  utf8.encode(x).length > 100,
            )) {
      invalid('GitHub备份路径无效');
    }
  }
}

class APIError implements Exception {
  final String message;
  final bool limited;
  APIError(this.message, {this.limited = false});
}

class GitHubAPI {
  final GitHubConfig config;
  final String token;
  GitHubAPI(this.config, this.token);
  String get root =>
      '/repos/${Uri.encodeComponent(config.owner)}/${Uri.encodeComponent(config.repository)}';
  Future<({int status, Uint8List bytes})> request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool raw = false,
    bool allow404 = false,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 45);
    try {
      final uri = Uri.parse(
        'https://api.github.com$path',
      ).replace(queryParameters: query);
      final req = await client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 45));
      req.followRedirects = false;
      req.headers.set('Authorization', 'Bearer $token');
      req.headers.set('X-GitHub-Api-Version', '2022-11-28');
      req.headers.set('User-Agent', 'Space-Flutter');
      req.headers.set(
        'Accept',
        raw ? 'application/vnd.github.raw+json' : 'application/vnd.github+json',
      );
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      final response = await req.close().timeout(const Duration(seconds: 45));
      final status = response.statusCode;
      if (!(status >= 200 && status < 300) && !(status == 404 && allow404)) {
        if (status == 401) throw APIError('GitHub令牌无效或已过期');
        if (status == 429 ||
            status == 403 &&
                (response.headers.value('x-ratelimit-remaining') == '0' ||
                    response.headers.value('retry-after') != null)) {
          throw APIError('GitHub请求受限，暂停15分钟', limited: true);
        }
        if (status == 403) throw APIError('GitHub访问被拒绝，请检查仓库权限');
        if (status == 404) throw APIError('仓库或分支不存在，也可能未获授权');
        if (status == 409 || status == 422) throw APIError('云端备份已变化，已停止覆盖');
        throw APIError('GitHub请求失败（HTTP $status）');
      }
      final result = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 45))) {
        result.add(chunk);
        if (result.length > 40 * 1024 * 1024) invalid('GitHub响应超过限制');
      }
      return (status: status, bytes: result.takeBytes());
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> jsonBody(Uint8List b) =>
      jsonDecode(utf8.decode(b)) as Map<String, dynamic>;
  Future<void> validate() async {
    config.validate();
    final repo = jsonBody((await request('GET', root)).bytes);
    if (repo['private'] != true) throw APIError('只允许使用私有仓库');
    await request(
      'GET',
      '$root/branches/${Uri.encodeComponent(config.branch)}',
    );
  }

  String get contentPath =>
      '$root/contents/${config.path.split('/').map(Uri.encodeComponent).join('/')}';
  Future<({String sha, int size, Uint8List? data})?> metadata() async {
    final r = await request(
      'GET',
      contentPath,
      query: {'ref': config.branch},
      allow404: true,
    );
    if (r.status == 404) return null;
    final j = jsonBody(r.bytes), sha = j['sha'] as String?, size = j['size'];
    if (sha == null ||
        !RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(sha) ||
        size is! int ||
        size < 0 ||
        size > 24 * 1024 * 1024) {
      invalid('云端文件元数据无效');
    }
    Uint8List? data;
    if (j['encoding'] == 'base64' &&
        (j['content'] as String? ?? '').isNotEmpty) {
      data = base64Decode(
        (j['content'] as String).replaceAll(RegExp(r'\s'), ''),
      );
      if (data.length != size || SyncCodec.gitBlob(data) != sha) {
        invalid('云端文件摘要不匹配');
      }
    }
    return (sha: sha, size: size, data: data);
  }

  Future<Uint8List> download(
    ({String sha, int size, Uint8List? data}) meta,
  ) async {
    final bytes =
        meta.data ??
        (await request('GET', '$root/git/blobs/${meta.sha}', raw: true)).bytes;
    if (bytes.length != meta.size || SyncCodec.gitBlob(bytes) != meta.sha) {
      invalid('云端文件摘要不匹配');
    }
    return bytes;
  }

  Future<String> upload(Uint8List bytes, String? expected) async {
    final result = jsonBody(
      (await request(
        'PUT',
        contentPath,
        body: {
          'message': 'Encrypted Space database backup',
          'branch': config.branch,
          'content': base64Encode(bytes),
          'sha': ?expected,
        },
      )).bytes,
    );
    final sha = (result['content'] as Map)['sha'];
    if (sha != SyncCodec.gitBlob(bytes)) invalid('GitHub上传返回的摘要不一致');
    return sha as String;
  }

  /// 发票原件与附件放在快照同级的 files 目录，按内容摘要命名。
  String get filesDirectory {
    final slash = config.path.lastIndexOf('/');
    return slash < 0 ? 'files' : '${config.path.substring(0, slash)}/files';
  }

  String contentPathFor(String relative) =>
      '$root/contents/${relative.split('/').map(Uri.encodeComponent).join('/')}';

  /// 云端已有的附件文件名（`<sha256>.space`）。
  Future<Set<String>> remoteFiles() async {
    final response = await request(
      'GET',
      '$root/git/trees/${Uri.encodeComponent(config.branch)}',
      query: {'recursive': '1'},
      allow404: true,
    );
    if (response.status == 404) return {};
    final tree = jsonBody(response.bytes)['tree'];
    if (tree is! List) return {};
    final prefix = '$filesDirectory/';
    return {
      for (final entry in tree)
        if (entry is Map &&
            entry['type'] == 'blob' &&
            entry['path'] is String &&
            (entry['path'] as String).startsWith(prefix) &&
            !(entry['path'] as String).substring(prefix.length).contains('/'))
          (entry['path'] as String).substring(prefix.length),
    };
  }

  Future<void> uploadFile(String name, Uint8List bytes) async {
    final path = contentPathFor('$filesDirectory/$name');
    final existing = await request(
      'GET',
      path,
      query: {'ref': config.branch},
      allow404: true,
    );
    String? sha;
    if (existing.status != 404) {
      final value = jsonBody(existing.bytes)['sha'];
      if (value is String && RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(value)) {
        sha = value;
      }
    }
    final result = jsonBody(
      (await request(
        'PUT',
        path,
        body: {
          'message': 'Encrypted Space attachment',
          'branch': config.branch,
          'content': base64Encode(bytes),
          'sha': ?sha,
        },
      )).bytes,
    );
    final content = result['content'];
    if (content is! Map || content['sha'] != SyncCodec.gitBlob(bytes)) {
      invalid('附件上传返回的摘要不一致');
    }
  }

  Future<Uint8List> downloadFile(String name) async {
    final response = await request(
      'GET',
      contentPathFor('$filesDirectory/$name'),
      query: {'ref': config.branch},
      allow404: true,
    );
    if (response.status == 404) invalid('云端缺少附件文件');
    final body = jsonBody(response.bytes),
        sha = body['sha'],
        size = body['size'];
    if (sha is! String ||
        size is! int ||
        size <= 0 ||
        size > 40 * 1024 * 1024) {
      invalid('云端附件元数据无效');
    }
    final bytes = (await request(
      'GET',
      '$root/git/blobs/${Uri.encodeComponent(sha)}',
      raw: true,
    )).bytes;
    if (bytes.length != size || SyncCodec.gitBlob(bytes) != sha) {
      invalid('云端附件摘要不匹配');
    }
    return bytes;
  }
}

final _services = Expando<SyncService>();
SyncService syncFor(SpaceStore store) =>
    _services[store] ??= SyncService(store);

class PendingGitHub {
  final SpaceState backup;
  final String sha, local;

  /// 已校验的快照文件，恢复发票台账与附件时继续使用。
  final String snapshot;
  final InvoiceSnapshot invoices;
  PendingGitHub(
    this.backup,
    this.sha,
    this.local,
    this.snapshot,
    this.invoices,
  );
}

class SyncService extends ChangeNotifier {
  final SpaceStore store;
  final GitHubAPI Function(GitHubConfig, String) apiFactory;
  GitHubConfig config = const GitHubConfig();
  bool busy = false, hasToken = false, hasKey = false, initialized = false;
  DateTime? lastSyncedAt;
  String message = '填写仓库地址、Token和恢复密钥后即可同步';

  /// 附件传输进度，按“已完成/总数”显示，空闲时清空。
  String progress = '';
  int fileDone = 0, fileTotal = 0;
  PendingGitHub? pending;
  SyncService(
    this.store, {
    GitHubAPI Function(GitHubConfig, String)? apiFactory,
  }) : apiFactory = apiFactory ?? GitHubAPI.new;

  String get token => store.state.settings['github.token'] ?? '';
  String get recoveryKey => store.state.settings['github.key'] ?? '';
  bool get ready => hasToken && hasKey;
  void _readSettings() {
    final settings = store.state.settings;
    final saved = settings['github.configuration'];
    config = saved == null
        ? const GitHubConfig()
        : GitHubConfig.fromJson(Map<String, dynamic>.from(jsonDecode(saved)));
    config.validate();
    hasToken = token.isNotEmpty;
    hasKey = recoveryKey.isNotEmpty;
    lastSyncedAt = DateTime.tryParse(settings['github.lastSyncedAt'] ?? '');
  }

  Future<void> initialize() async {
    try {
      _readSettings();
      if (initialized) return;
      // One-time migration; never print credentials or overwrite existing SQLite settings.
      final legacy = File(
        '${store.repository.directory.path}/github-sync.json',
      );
      if (!store.state.settings.containsKey('github.configuration') &&
          legacy.existsSync()) {
        if (legacy.lengthSync() > 16 * 1024) invalid('GitHub本地配置超过限制');
        final j = jsonDecode(await legacy.readAsString());
        final next = GitHubConfig.fromJson(
          Map<String, dynamic>.from(j['configuration']),
        );
        next.validate();
        final oldToken =
            await DesktopHost.secret('${next.identity}:token') ?? '';
        final oldKey = await DesktopHost.secret('${next.identity}:key') ?? '';
        if (!await store.preferences({
          'github.configuration': jsonEncode(next.toJson()),
          'github.token': oldToken,
          'github.key': oldKey,
        })) {
          invalid(store.error ?? 'GitHub配置迁移失败');
        }
        _readSettings();
      }
      initialized = true;
      message = ready ? '连接配置已保存到本地SQLite' : '填写仓库地址、Token和恢复密钥后即可同步';
    } catch (e) {
      message = 'GitHub配置读取失败，请重新填写连接配置';
    }
    notifyListeners();
  }

  Future<bool> save(GitHubConfig next, String newToken, String newKey) async {
    if (busy) return false;
    try {
      next.validate();
      final identityChanged = next.identity != config.identity;
      final savedToken = newToken.trim().isNotEmpty
          ? newToken.trim()
          : identityChanged
          ? ''
          : token;
      final savedKey = newKey.trim().isNotEmpty
          ? newKey.trim()
          : identityChanged
          ? ''
          : recoveryKey;
      if (savedToken.isEmpty) invalid('请输入GitHub访问令牌');
      if (savedToken.length > 4096 || controls(savedToken)) {
        invalid('GitHub访问令牌格式无效');
      }
      if (savedKey.isEmpty) invalid('请设置恢复密钥，其他设备恢复时使用相同密钥');
      // Existing 32-byte Base64 keys stay compatible. User-set passphrases are also supported.
      SyncCodec.validateGitHubKey(savedKey);
      final keyChanged = savedKey != recoveryKey;
      if (!identityChanged &&
          !keyChanged &&
          savedToken == token &&
          store.state.settings['github.configuration'] ==
              jsonEncode(next.toJson())) {
        return true;
      }
      if (!await store.preferences({
        'github.configuration': jsonEncode(next.toJson()),
        'github.token': savedToken,
        'github.key': savedKey,
        if (identityChanged || keyChanged) 'github.lastSyncedAt': '',
      })) {
        invalid(store.error ?? '连接配置保存失败');
      }
      _readSettings();
      initialized = true;
      if (identityChanged || keyChanged) pending = null;
      message = '连接配置已保存到本地SQLite';
      notifyListeners();
      return true;
    } catch (e) {
      message = e is APIError ? e.message : SpaceStore.readable(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> _synced() async {
    final now = DateTime.now().toUtc();
    if (!await store.preferences({
      'github.lastSyncedAt': now.toIso8601String(),
    })) {
      invalid(store.error ?? '同步时间保存失败');
    }
    lastSyncedAt = now;
  }

  Future<void> transfer({required bool download}) async {
    if (busy || !store.loaded || store.busy) return;
    if (!ready) {
      message = '请先填写仓库地址、Token和恢复密钥';
      notifyListeners();
      return;
    }
    busy = true;
    fileDone = fileTotal = 0;
    progress = '';
    _discardPending();
    message = download ? '正在下载并校验云端数据…' : '正在同步数据到云端…';
    notifyListeners();
    try {
      _readSettings();
      final api = apiFactory(config, token);
      final key = recoveryKey;
      final invoices = InvoiceRepository(store.repository);
      await api.validate();
      final meta = await api.metadata();
      if (download) {
        if (meta == null) invalid('云端尚无备份');
        final local = SyncCodec.fingerprint(store.state);
        final bytes = await api.download(meta);
        final snapshot = _pendingSnapshotPath();
        late SpaceState incoming;
        if (SyncCodec.isDatabasePackage(bytes)) {
          final database = await SyncCodec.databaseOpen(bytes, key);
          await File(snapshot).writeAsBytes(database, flush: true);
          incoming = await store.repository.readExternal(snapshot);
        } else {
          // 旧版备份只含状态 JSON，没有发票台账与附件。
          incoming = await SyncCodec.githubOpen(bytes, key);
        }
        if (SyncCodec.fingerprint(store.state) != local) {
          invalid('下载期间本地数据发生变化，请重试');
        }
        final summary = await invoices.readSnapshot(snapshot);
        pending = PendingGitHub(incoming, meta.sha, local, snapshot, summary);
        message = summary.files.isEmpty
            ? '云端数据已校验，确认后恢复（该备份不含附件文件）'
            : '云端数据已校验：${summary.invoices} 张发票、${summary.files.length} 个文件';
      } else {
        // Verify the existing encryption key and use GitHub's SHA precondition to prevent races.
        if (meta != null) {
          final existing = await api.download(meta);
          if (SyncCodec.isDatabasePackage(existing)) {
            await SyncCodec.databaseOpen(existing, key);
          } else {
            await SyncCodec.githubOpen(existing, key);
          }
        }
        final fileKey = await SyncCodec.fileKey(key);
        final filesNote = await _uploadFiles(api, invoices, fileKey);
        final snapshotFile = File(
          '${store.repository.directory.path}/.github-snapshot-${uid()}.sqlite',
        );
        late SpaceState snapshot;
        late Uint8List database;
        try {
          await store.repository.exportSQLite(snapshotFile.path);
          database = await snapshotFile.readAsBytes();
          snapshot = await store.repository.readExternal(snapshotFile.path);
        } finally {
          if (snapshotFile.existsSync()) snapshotFile.deleteSync();
        }
        message = '正在上传任务与发票台账…';
        notifyListeners();
        await api.upload(
          await SyncCodec.databaseSeal(database, key),
          meta?.sha,
        );
        await _synced();
        fileDone = fileTotal = 0;
        progress = '';
        message =
            '${SyncCodec.fingerprint(store.state) == SyncCodec.fingerprint(snapshot) ? '数据已同步到云端' : '本次快照已上传，本地仍有后续更改待同步'}$filesNote';
      }
    } catch (e) {
      message = e is APIError ? e.message : SpaceStore.readable(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// 逐个上传缺失的发票文件，内容未变化时直接跳过。
  Future<String> _uploadFiles(
    GitHubAPI api,
    InvoiceRepository invoices,
    List<int> fileKey,
  ) async {
    final manifest = await invoices.syncManifest();
    if (manifest.isEmpty) return '';
    final remote = await api.remoteFiles();
    final missing = [
      for (final entry in manifest)
        if (!remote.contains('${entry.sha256}.space')) entry,
    ];
    if (missing.isEmpty) return '，${manifest.length} 个附件均已在云端';
    fileTotal = missing.length;
    fileDone = 0;
    for (final entry in missing) {
      final bytes = File(entry.file.path).readAsBytesSync();
      if (sha256.convert(bytes).toString() != entry.sha256) {
        invalid('${entry.file.name} 在同步过程中发生变化，请重试');
      }
      await api.uploadFile(
        '${entry.sha256}.space',
        await SyncCodec.fileSeal(bytes, fileKey),
      );
      fileDone++;
      progress = '正在上传附件 $fileDone/$fileTotal';
      message = progress;
      notifyListeners();
    }
    return '，已上传 $fileDone 个附件';
  }

  /// 下载本机缺失的发票文件，逐个校验摘要后写入数据目录。
  Future<String> _restoreFiles(
    GitHubAPI api,
    InvoiceRepository invoices,
    PendingGitHub value,
    List<int> fileKey,
  ) async {
    final refs = value.invoices.files;
    if (refs.isEmpty) return '';
    final local = await invoices.localFileDigests();
    final missing = [
      for (final ref in refs)
        if (local[ref.id] != ref.sha256) ref,
    ];
    if (missing.isEmpty) return '，${refs.length} 个附件已在本机';
    fileTotal = missing.length;
    fileDone = 0;
    for (final ref in missing) {
      final sealed = await api.downloadFile('${ref.sha256}.space');
      final bytes = await SyncCodec.fileOpen(sealed, fileKey);
      if (sha256.convert(bytes).toString() != ref.sha256) {
        invalid('${ref.name} 校验失败，已停止恢复');
      }
      await invoices.writeSyncedFile(ref.id, ref.extension, bytes);
      fileDone++;
      progress = '正在恢复附件 $fileDone/$fileTotal';
      message = progress;
      notifyListeners();
    }
    return '，并恢复 $fileDone 个附件';
  }

  String _pendingSnapshotPath() =>
      '${store.repository.directory.path}/.github-incoming-${uid()}.sqlite';

  void _discardPending() {
    final value = pending;
    pending = null;
    if (value == null) return;
    try {
      final file = File(value.snapshot);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // A leftover snapshot is harmless and gets replaced on the next restore.
    }
  }

  Future<void> restoreGitHub() async {
    final value = pending;
    if (value == null || busy) return;
    if (SyncCodec.fingerprint(store.state) != value.local) {
      _discardPending();
      message = '确认期间本地数据已变化，已停止恢复';
      notifyListeners();
      return;
    }
    busy = true;
    fileDone = fileTotal = 0;
    notifyListeners();
    try {
      final api = apiFactory(config, token);
      final fileKey = await SyncCodec.fileKey(recoveryKey);
      final invoices = InvoiceRepository(store.repository);
      final filesNote = await _restoreFiles(api, invoices, value, fileKey);
      message = '正在恢复任务与发票台账…';
      notifyListeners();
      if (await store.commit(
        value.backup.copy(
          settings: {
            ...store.state.settings,
            'taskCategories': jsonEncode(value.backup.taskCategories),
          },
          workspaceID: store.state.workspaceID,
        ),
        '云端数据已恢复',
      )) {
        final count = value.snapshot.isEmpty
            ? 0
            : await store.repository.importInvoiceLedger(value.snapshot);
        _discardPending();
        await _synced();
        fileDone = fileTotal = 0;
        progress = '';
        message =
            '已备份本地并恢复云端数据：${value.backup.tasks.length} 项任务、$count 张发票$filesNote';
      } else {
        message = store.error ?? '恢复失败，请重试';
      }
    } catch (e) {
      message = e is APIError ? e.message : SpaceStore.readable(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void cancelPending() {
    _discardPending();
    message = '已取消恢复，本地数据保持不变';
    notifyListeners();
  }
}

class ManualTransport {
  final String location, username, password;
  ManualTransport(this.location, this.username, this.password);
  Uri _uri(String filename) {
    if (path.isAbsolute(location)) {
      return File(path.join(location, filename)).uri;
    }
    final uri = Uri.tryParse(location);
    if (uri == null) invalid('请输入有效位置');
    if (uri.scheme == 'https') {
      if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
        invalid('HTTPS目录不能包含凭据、查询或片段');
      }
      return uri.replace(
        path: '${uri.path.replaceFirst(RegExp(r'/$'), '')}/$filename',
      );
    }
    if (uri.scheme == 'file') {
      return Uri.file('${Directory.fromUri(uri).path}/$filename');
    }
    invalid('仅支持HTTPS目录或已挂载的绝对文件夹路径');
  }

  Future<Uint8List> _request(
    String method,
    String name, {
    List<int>? body,
  }) async {
    final uri = _uri(name);
    if (uri.scheme == 'file') {
      final file = File.fromUri(uri);
      if (method == 'PUT') {
        file.parent.createSync(recursive: true);
        await file.create(exclusive: true);
        final handle = await file.open(mode: FileMode.writeOnly);
        try {
          await handle.writeFrom(body!);
          await handle.flush();
        } finally {
          await handle.close();
        }
        return Uint8List(0);
      }
      if (!file.existsSync() || file.lengthSync() > 64 * 1024 * 1024) {
        invalid('同步文件不存在或超过限制');
      }
      return file.readAsBytes();
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 45);
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 45));
      request.followRedirects = true;
      if (username.isNotEmpty || password.isNotEmpty) {
        request.headers.set(
          'Authorization',
          'Basic ${base64Encode(utf8.encode('$username:$password'))}',
        );
      }
      if (body != null) {
        request.headers.contentType = ContentType.binary;
        request.headers.set('If-None-Match', '*');
        request.add(body);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 45),
      );
      if (method == 'PUT' && ![200, 201, 204].contains(response.statusCode) ||
          method == 'GET' && response.statusCode != 200) {
        invalid('同步请求失败（HTTP ${response.statusCode}）');
      }
      final result = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 45))) {
        result.add(chunk);
        if (result.length > 64 * 1024 * 1024) invalid('同步包超过64 MB');
      }
      return result.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> put(String filename, List<int> bytes) async {
    await _request('PUT', filename, body: bytes);
  }

  Future<Uint8List> get(String filename) => _request('GET', filename);
}
