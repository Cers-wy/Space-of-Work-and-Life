import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:space_flutter/core/invoices.dart';
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/core/sync.dart';
import 'package:space_flutter/core/sync_service.dart';
import 'package:space_flutter/store.dart';

/// 只保存加密包的内存仓库，用来验证附件增量上传与换机恢复。
class MemoryGitHubAPI extends GitHubAPI {
  MemoryGitHubAPI(super.config, super.token);
  Uint8List? cloud;
  final files = <String, Uint8List>{};
  int uploads = 0, fileUploads = 0;

  @override
  Future<void> validate() async {}

  @override
  Future<({String sha, int size, Uint8List? data})?> metadata() async {
    final bytes = cloud;
    if (bytes == null) return null;
    return (sha: SyncCodec.gitBlob(bytes), size: bytes.length, data: bytes);
  }

  @override
  Future<Uint8List> download(
    ({String sha, int size, Uint8List? data}) meta,
  ) async => meta.data!;

  @override
  Future<String> upload(Uint8List bytes, String? expected) async {
    uploads++;
    cloud = bytes;
    return SyncCodec.gitBlob(bytes);
  }

  @override
  Future<Set<String>> remoteFiles() async => files.keys.toSet();

  @override
  Future<void> uploadFile(String name, Uint8List bytes) async {
    fileUploads++;
    files[name] = bytes;
  }

  @override
  Future<Uint8List> downloadFile(String name) async => files[name]!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = '这是一条恢复密钥2026';
  const token = 'token-value';
  final url = GitHubConfig.fromUrl('https://github.com/cers/space-sync-data');

  test('单个附件加密包可正确解封，错误密钥与篡改都会拒绝', () async {
    final plain = Uint8List.fromList(List.generate(2048, (i) => i % 251));
    final fileKey = await SyncCodec.fileKey(key);
    final sealed = await SyncCodec.fileSeal(plain, fileKey);
    expect(
      sealed.sublist(0, SyncCodec.fileHeader.length),
      SyncCodec.fileHeader,
    );
    expect(
      await SyncCodec.fileOpen(sealed, await SyncCodec.fileKey(key)),
      plain,
    );
    await expectLater(
      SyncCodec.fileOpen(sealed, await SyncCodec.fileKey('另一条完全不同的恢复密钥2026')),
      throwsFormatException,
    );
    final changed = Uint8List.fromList(sealed)..[20] ^= 1;
    await expectLater(
      SyncCodec.fileOpen(changed, await SyncCodec.fileKey(key)),
      throwsFormatException,
    );
    await expectLater(
      SyncCodec.fileSeal(Uint8List(0), fileKey),
      throwsFormatException,
    );
  });

  test('发票文件按摘要增量上传，换机恢复后台账与附件保持一致', () async {
    final root = await Directory.systemTemp.createTemp('space-sync-files-');
    addTearDown(() => root.delete(recursive: true));
    final api = MemoryGitHubAPI(url, token);

    // 机器 A：创建任务与一张带附件的发票。
    final repoA = SpaceRepository(Directory('${root.path}/a'));
    final stateA = await repoA.load();
    await repoA.save(
      stateA.copy(
        tasks: [
          SpaceTask.create().patch({'title': '出差报销'}),
        ],
        projects: [Project('p-1', '客户差旅')],
      ),
    );
    final invoicesA = InvoiceRepository(repoA);
    final pdf = File('${root.path}/票.pdf')..writeAsStringSync('%PDF-1.7\n测试');
    final receipt = File('${root.path}/行程单.pdf')
      ..writeAsStringSync('%PDF-1.7\n附件');
    await invoicesA.importFiles([pdf.path]);
    final entry = (await invoicesA.load()).entries.single;
    await invoicesA.importFiles([receipt.path], attachmentTo: entry.id);
    final manifest = await invoicesA.syncManifest();
    expect(manifest.length, 2);
    expect(manifest.every((file) => file.sha256.length == 64), isTrue);

    final storeA = SpaceStore(repoA);
    await storeA.initialize();
    addTearDown(storeA.dispose);
    final syncA = SyncService(storeA, apiFactory: (_, _) => api);
    await syncA.save(url, token, key);
    await syncA.transfer(download: false);
    expect(api.uploads, 1, reason: 'A同步结果：${syncA.message}');
    expect(api.fileUploads, 2, reason: syncA.message);
    expect(api.files.keys.toSet(), {
      for (final file in manifest) '${file.sha256}.space',
    });
    expect(syncA.message, contains('已上传'));
    // 再同步一次不应重复上传文件。
    await syncA.transfer(download: false);
    expect(api.fileUploads, 2);
    expect(syncA.message, contains('均已在云端'));

    // 机器 B：空库恢复同一仓库。
    final repoB = SpaceRepository(Directory('${root.path}/b'));
    await repoB.load();
    final storeB = SpaceStore(repoB);
    await storeB.initialize();
    addTearDown(storeB.dispose);
    // A 导出的快照应当包含发票台账。
    final checkDir = Directory('${root.path}/check')
      ..createSync(recursive: true);
    final checkFile = '${checkDir.path}/s.sqlite';
    await repoA.exportSQLite(checkFile);
    final check = await invoicesA.readSnapshot(checkFile);
    expect(check.invoices, 1, reason: 'A 导出的快照中应有 1 张发票');
    final syncB = SyncService(storeB, apiFactory: (_, _) => api);
    await syncB.save(url, token, key);
    await syncB.transfer(download: true);
    expect(syncB.pending, isNotNull);
    expect(syncB.pending!.invoices.invoices, 1);
    expect(syncB.pending!.invoices.files.length, 2);
    await syncB.restoreGitHub();
    expect(syncB.message, contains('1 张发票'));
    expect(syncB.message, contains('2 个附件'));
    expect(storeB.state.tasks.single.title, '出差报销');

    final ledgerB = await InvoiceRepository(repoB).load();
    expect(ledgerB.entries.length, 1);
    final restored = ledgerB.entries.single;
    expect(File(restored.original.path).readAsStringSync(), contains('%PDF'));
    expect(restored.attachments.length, 1);
    expect(
      File(restored.attachments.single.path).readAsStringSync(),
      contains('附件'),
    );
    expect(ledgerB.projects, isNotEmpty);
    final digests = await InvoiceRepository(repoB).localFileDigests();
    expect(digests[restored.original.id], manifest.first.sha256);

    // 再次恢复时文件已在本机，不再重复下载。
    await syncB.transfer(download: true);
    await syncB.restoreGitHub();
    expect(syncB.message, contains('已在本机'));
  });

  test('本地备份包包含数据库与附件，可在新数据目录完整还原', () async {
    final root = await Directory.systemTemp.createTemp('space-pack-');
    addTearDown(() => root.delete(recursive: true));
    final repoA = SpaceRepository(Directory('${root.path}/a'));
    await repoA.load();
    final invoices = InvoiceRepository(repoA);
    final pdf = File('${root.path}/票.pdf')..writeAsStringSync('%PDF-1.7\n备份');
    await invoices.importFiles([pdf.path]);
    final manifest = await invoices.syncManifest();

    final pack = '${root.path}/Space备份.spacepack';
    await repoA.exportPack(pack);
    expect(File(pack).existsSync(), isTrue);

    final unpacked = await repoA.unpackBackup(pack);
    try {
      final moved = File(pack).renameSync('$pack.checked');
      expect(moved.existsSync(), isTrue, reason: '解包完成必须立即释放备份包句柄');
      expect(unpacked.files, 1);
      final snapshot = await invoices.readSnapshot(unpacked.database);
      expect(snapshot.invoices, 1);
      expect(snapshot.files.single.sha256, manifest.single.sha256);

      final repoB = SpaceRepository(Directory('${root.path}/b'));
      await repoB.load();
      final storeB = SpaceStore(repoB);
      await storeB.initialize();
      addTearDown(storeB.dispose);
      final incoming = await storeB.readBackup(unpacked.database);
      expect(await storeB.applyBackup(incoming), isTrue);
      expect(await repoB.importInvoiceLedger(unpacked.database), 1);
      expect(await repoB.restorePackFiles(unpacked), 1);
      final ledger = await InvoiceRepository(repoB).load();
      expect(ledger.entries.single.info, isNotNull);
      final file = File(ledger.entries.single.original.path);
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('备份'));
    } finally {
      await repoA.cleanupBackup(unpacked);
    }
    expect(Directory(unpacked.directory).existsSync(), isFalse);
  });

  test('旧版 SQLite 备份仍可导入，只是不含附件', () async {
    final root = await Directory.systemTemp.createTemp('space-legacy-');
    addTearDown(() => root.delete(recursive: true));
    final repo = SpaceRepository(Directory('${root.path}/a'));
    await repo.load();
    final legacy = '${root.path}/Space备份.sqlite';
    await repo.exportSQLite(legacy);
    final unpacked = await repo.unpackBackup(legacy);
    try {
      expect(unpacked.files, 0);
      expect(unpacked.database, endsWith('space.sqlite'));
      expect(
        (await InvoiceRepository(repo).readSnapshot(unpacked.database)).files,
        isEmpty,
      );
    } finally {
      await repo.cleanupBackup(unpacked);
    }
  });
}
