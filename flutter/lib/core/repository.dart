import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'files.dart';

import 'package:sqlite3/sqlite3.dart';

import 'models.dart';

/// 解包后的备份：临时目录中的数据库快照，以及其中的附件数量。
class UnpackedBackup {
  final String directory, database;
  final int files;
  const UnpackedBackup(this.directory, this.database, this.files);
  String get attachments => p.join(directory, 'invoices', 'files');
}

class SpaceRepository {
  final Directory directory;
  SpaceRepository(this.directory);
  String get path => '${directory.path}/space.sqlite';
  String get previous => '${directory.path}/space.previous.sqlite';
  String? expectedRevision;
  bool loaded = false;
  Future<T> _locked<T>(Future<T> Function() work) async {
    directory.createSync(recursive: true);
    protectPath(directory.path, directory: true);
    final lock = File('${directory.path}/.sqlite-write-lock')
        .openSync(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      return await work();
    } finally {
      await lock.unlock();
      await lock.close();
    }
  }

  Database _open(String file, {bool readOnly = false}) {
    final db = sqlite3.open(
      file,
      mode: readOnly ? OpenMode.readOnly : OpenMode.readWriteCreate,
      mutex: true,
    );
    db.execute(
      'PRAGMA foreign_keys=ON; PRAGMA trusted_schema=OFF; PRAGMA busy_timeout=5000;',
    );
    return db;
  }

  Database openInvoiceDatabase() {
    if (!loaded || !File(path).existsSync()) {
      throw StateError('Space 数据库尚未载入');
    }
    final db = _open(path);
    try {
      if (db.userVersion < 1 || db.userVersion > 8) {
        throw StateError('不支持此 Space 数据库版本');
      }
      _upgradeInvoiceSchema(db);
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  /// v5 起发票使用共用项目表；v6 补充购销方与税额；v7 记录附件摘要与大小。
  void _upgradeInvoiceSchema(Database db) {
    if (db.userVersion >= 8 || db.userVersion < 1) return;
    db.execute('BEGIN IMMEDIATE');
    try {
      final from = db.userVersion;
      if (from < 4) {
        _createInvoiceTables(db);
      } else if (from == 4) {
        _migrateInvoiceProjects(db);
      }
      _addInvoiceFields(db);
      _addInvoiceFileColumns(db);
      _addInvoiceRecognitionColumns(db);
      db.userVersion = 8;
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _addInvoiceRecognitionColumns(Database db) {
    final columns = {
      for (final row in db.select('PRAGMA table_info(invoices)'))
        row['name'] as String,
    };
    for (final name in ['title', 'recognition']) {
      if (!columns.contains(name)) {
        db.execute(
          "ALTER TABLE invoices ADD COLUMN $name TEXT NOT NULL DEFAULT ''",
        );
      }
    }
  }

  /// v7 只缓存内容摘要与字节数，便于云端同步增量比对，不影响票面字段。
  void _addInvoiceFileColumns(Database db) {
    final columns = {
      for (final row in db.select('PRAGMA table_info(invoice_files)'))
        row['name'] as String,
    };
    if (!columns.contains('sha256')) {
      db.execute('ALTER TABLE invoice_files ADD COLUMN sha256 TEXT');
    }
    if (!columns.contains('bytes')) {
      db.execute('ALTER TABLE invoice_files ADD COLUMN bytes INTEGER');
    }
  }

  /// v6 补充购销方、税号与税额字段，旧记录保持空值。
  void _addInvoiceFields(Database db) {
    final columns = {
      for (final row in db.select('PRAGMA table_info(invoices)'))
        row['name'] as String,
    };
    void add(String name, String definition) {
      if (!columns.contains(name)) {
        db.execute('ALTER TABLE invoices ADD COLUMN $name $definition');
      }
    }

    add('buyer', "TEXT NOT NULL DEFAULT ''");
    add('seller_tax', "TEXT NOT NULL DEFAULT ''");
    add('buyer_tax', "TEXT NOT NULL DEFAULT ''");
    add('tax_cents', 'INTEGER');
    add('net_cents', 'INTEGER');
  }

  void _createInvoiceTables(Database db) {
    db.execute('''
CREATE TABLE invoices (
id TEXT PRIMARY KEY, number TEXT NOT NULL DEFAULT '', issued TEXT NOT NULL DEFAULT '',
seller TEXT NOT NULL DEFAULT '', spent TEXT NOT NULL DEFAULT '', purpose TEXT NOT NULL DEFAULT '',
month TEXT NOT NULL DEFAULT '', project TEXT REFERENCES projects(id) DEFERRABLE INITIALLY DEFERRED,
cents INTEGER, reimbursed INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE invoice_files (
id TEXT PRIMARY KEY, invoice TEXT NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
name TEXT NOT NULL, extension TEXT NOT NULL, original INTEGER NOT NULL
);
CREATE INDEX invoice_files_parent ON invoice_files(invoice);
CREATE UNIQUE INDEX invoice_original ON invoice_files(invoice) WHERE original=1;
CREATE INDEX invoice_project ON invoices(project);
''');
  }

  void _migrateInvoiceProjects(Database db) {
    final byName = {
      for (final row in db.select('SELECT id,name FROM projects'))
        normalizedName(row['name'] as String).toLowerCase():
            row['id'] as String,
    };
    db.execute('''
CREATE TEMP TABLE invoice_project_map (old_id TEXT PRIMARY KEY, project_id TEXT NOT NULL);
DROP INDEX invoice_files_parent;
DROP INDEX invoice_original;
ALTER TABLE invoices RENAME TO old_invoices;
ALTER TABLE invoice_files RENAME TO old_invoice_files;
''');
    var fallback = 1;
    for (final row in db.select(
      'SELECT id,name FROM invoice_projects ORDER BY rowid',
    )) {
      final oldID = row['id'] as String;
      var name = normalizedName(row['name'] as String);
      if (controls(name) || name.isEmpty || name.length > 60) {
        do {
          name = '旧报销项目 ${fallback++}';
        } while (byName.containsKey(name.toLowerCase()));
      }
      final project = byName.putIfAbsent(name.toLowerCase(), () {
        if (byName.length >= 10000) invalid('合并报销项目后项目数量超过限制');
        final id = uid();
        db.execute('INSERT INTO projects VALUES (?,?)', [id, name]);
        return id;
      });
      db.execute('INSERT INTO invoice_project_map VALUES (?,?)', [
        oldID,
        project,
      ]);
    }
    _createInvoiceTables(db);
    db.execute('''
INSERT INTO invoices
SELECT i.id,i.number,i.issued,i.seller,i.spent,i.purpose,i.month,m.project_id,i.cents,i.reimbursed
FROM old_invoices i LEFT JOIN invoice_project_map m ON i.project=m.old_id ORDER BY i.rowid;
INSERT INTO invoice_files SELECT * FROM old_invoice_files ORDER BY rowid;
DROP TABLE old_invoice_files;
DROP TABLE old_invoices;
DROP TABLE invoice_projects;
DROP TABLE invoice_project_map;
''');
    db.execute("INSERT OR REPLACE INTO metadata VALUES('revision',?)", [uid()]);
  }

  SpaceState readFile(String file) => _readFile(file).$1;

  (SpaceState, int) _readFile(String file) {
    if (!File(file).existsSync() ||
        File(file).lengthSync() > 64 * 1024 * 1024) {
      invalid('数据库不存在或超过64 MB');
    }
    final handle = File(file).openSync();
    try {
      if (ascii.decode(handle.readSync(16), allowInvalid: true) !=
          'SQLite format 3\x00') {
        invalid('请选择SQLite数据库备份文件');
      }
    } finally {
      handle.closeSync();
    }
    final db = _open(file, readOnly: true);
    try {
      final v = db.userVersion;
      if (v < 1 || v > 8) invalid('不支持数据库格式版本 $v');
      if (db.select('PRAGMA quick_check').first.values.first != 'ok') {
        invalid('数据库校验失败，原文件已保留');
      }
      final meta = {
        for (final r in db.select('SELECT key,value FROM metadata'))
          r['key'] as String: r['value'] as String,
      };
      final disabledProjects = Set<String>.from(
        jsonDecode(meta['disabledProjects'] ?? '[]') as List,
      );
      final s = SpaceState(
        tasks: db
            .select(
              'SELECT payload,status_id,project_id FROM tasks ORDER BY rowid',
            )
            .map((r) {
              final t = SpaceTask.fromJson(jsonDecode(r['payload'] as String));
              if (t.status != r['status_id'] ||
                  t.projectID != r['project_id']) {
                invalid('任务索引与内容不一致');
              }
              return t;
            })
            .toList(),
        statuses: db
            .select('SELECT id FROM statuses ORDER BY position')
            .map((r) => r['id'] as String)
            .toList(),
        disabledStatuses: db
            .select('SELECT id FROM statuses WHERE active=0 ORDER BY position')
            .map((r) => r['id'] as String)
            .toList(),
        projects: db
            .select('SELECT id,name FROM projects ORDER BY rowid')
            .map(
              (r) => Project(
                r['id'] as String,
                r['name'] as String,
                disabled: disabledProjects.contains(r['id']),
              ),
            )
            .toList(),
        settings: {
          for (final r in db.select('SELECT key,value FROM settings'))
            r['key'] as String: r['value'] as String,
        },
        workspaceID: meta['workspaceID'],
        revision: meta['revision'],
      );
      s.validate();
      if (v < 2 && s.tasks.any((t) => t.startDate != null) ||
          v < 3 && s.tasks.any((t) => t.richDescription != null)) {
        invalid('数据库版本与内容不一致');
      }
      return (s, v);
    } finally {
      db.close();
    }
  }

  Future<SpaceState> load() async {
    final directoryPath = directory.path;
    try {
      final state = await Isolate.run(
        () => SpaceRepository(Directory(directoryPath))._loadDirect(),
      );
      expectedRevision = state.revision;
      loaded = true;
      return state;
    } catch (_) {
      loaded = false;
      rethrow;
    }
  }

  Future<SpaceState> readExternal(String file) async {
    final directoryPath = directory.path;
    return Isolate.run(
      () => SpaceRepository(Directory(directoryPath)).readFile(file),
    );
  }

  Future<SpaceState> _loadDirect() async {
    try {
      if (File(path).existsSync()) {
        final s = _readLocal();
        expectedRevision = s.revision;
        loaded = true;
        return s;
      }
      final s = SpaceState(workspaceID: uid());
      return await _locked(() async {
        if (File(path).existsSync()) {
          final existing = _readLocal();
          expectedRevision = existing.revision;
          loaded = true;
          return existing;
        }
        return _write(s, initialize: true);
      });
    } catch (_) {
      loaded = false;
      rethrow;
    }
  }

  SpaceState _readLocal() {
    final (state, version) = _readFile(path);
    if (version != 4) return state;
    loaded = true;
    openInvoiceDatabase().close();
    return readFile(path);
  }

  String? _revision(Database db) =>
      db
              .select("SELECT value FROM metadata WHERE key='revision'")
              .firstOrNull?['value']
          as String?;
  void _check(Database db) {
    if (_revision(db) != expectedRevision) {
      throw StateError('本地数据已被其他窗口修改，请重新载入后再试');
    }
  }

  Future<void> _snapshot(Database db, String target) async {
    if (fileIdentity(target) == fileIdentity(path)) invalid('不能覆盖活动数据库');
    final temp = '$target.${uid()}.tmp';
    final dest = _open(temp);
    try {
      await db.backup(dest, nPage: -1).drain<void>();
    } finally {
      dest.close();
    }
    try {
      File(temp).renameSync(target);
      protectPath(target);
    } catch (_) {
      if (File(temp).existsSync()) File(temp).deleteSync();
      rethrow;
    }
  }

  Future<SpaceState> save(
    SpaceState state, {
    bool preferencesOnly = false,
  }) async {
    if (!loaded) throw StateError('数据库未载入，禁止普通写入');
    final directoryPath = directory.path, revision = expectedRevision;
    final result = await Isolate.run(() async {
      final worker = SpaceRepository(Directory(directoryPath))
        ..loaded = true
        ..expectedRevision = revision;
      state.validate();
      return worker._locked(
        () => worker._write(state, preferencesOnly: preferencesOnly),
      );
    });
    expectedRevision = result.revision;
    return result;
  }

  Future<SpaceState> _write(
    SpaceState state, {
    bool initialize = false,
    bool preferencesOnly = false,
  }) async {
    state.validate();
    final writePath = initialize ? '$path.${uid()}.initializing' : path;
    final db = _open(writePath);
    var committed = false;
    final revision = uid();
    try {
      if (initialize) {
        db.execute('''
CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
CREATE TABLE statuses(id TEXT PRIMARY KEY,position INTEGER NOT NULL,active INTEGER NOT NULL CHECK(active IN(0,1)));
CREATE TABLE projects(id TEXT PRIMARY KEY,name TEXT NOT NULL UNIQUE COLLATE NOCASE);
CREATE TABLE tasks(id TEXT PRIMARY KEY,status_id TEXT NOT NULL REFERENCES statuses(id),project_id TEXT REFERENCES projects(id),payload TEXT NOT NULL);
CREATE INDEX task_status ON tasks(status_id);
CREATE INDEX task_project ON tasks(project_id);
CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
PRAGMA application_id=1397768515;
PRAGMA user_version=1;
''');
      } else {
        _check(db);
        if (!preferencesOnly) await _snapshot(db, previous);
      }
      db.execute('BEGIN IMMEDIATE');
      try {
        if (!initialize) _check(db);
        if (!preferencesOnly) {
          db.execute(
            'DELETE FROM tasks; DELETE FROM projects; DELETE FROM statuses;',
          );
          for (var i = 0; i < state.statuses.length; i++) {
            final s = state.statuses[i];
            db.execute('INSERT INTO statuses VALUES(?,?,?)', [
              s,
              i,
              state.disabledStatuses.contains(s) ? 0 : 1,
            ]);
          }
          db.execute(
            "INSERT OR REPLACE INTO metadata VALUES('disabledProjects',?)",
            [
              jsonEncode(
                state.projects
                    .where((p) => p.disabled)
                    .map((p) => p.id)
                    .toList(),
              ),
            ],
          );
          for (final p in state.projects) {
            db.execute('INSERT INTO projects VALUES(?,?)', [p.id, p.name]);
          }
          if (db.userVersion >= 5) {
            // Retained project IDs have already been reinserted in this transaction.
            db.execute(
              'UPDATE invoices SET project=NULL WHERE project IS NOT NULL '
              'AND NOT EXISTS (SELECT 1 FROM projects WHERE id=invoices.project)',
            );
          }
          final insert = db.prepare('INSERT INTO tasks VALUES(?,?,?,?)');
          try {
            for (final t in state.tasks) {
              insert.execute([
                t.id,
                t.status,
                t.projectID,
                jsonEncode(t.toJson()),
              ]);
            }
          } finally {
            insert.close();
          }
          final needed = state.tasks.any((t) => t.richDescription != null)
              ? 3
              : state.tasks.any((t) => t.startDate != null)
              ? 2
              : 1;
          if (needed > db.userVersion) db.userVersion = needed;
          db.execute(
            "INSERT OR REPLACE INTO metadata VALUES('workspaceID',?)",
            [state.workspaceID ?? uid()],
          );
        }
        db.execute('DELETE FROM settings');
        for (final e in state.settings.entries) {
          db.execute('INSERT INTO settings VALUES(?,?)', [e.key, e.value]);
        }
        db.execute("INSERT OR REPLACE INTO metadata VALUES('revision',?)", [
          revision,
        ]);
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
      protectPath(writePath);
      committed = true;
      expectedRevision = revision;
      loaded = true;
      return state.copy(revision: revision);
    } finally {
      db.close();
      if (initialize) {
        if (committed) {
          if (File(path).existsSync()) {
            File(writePath).deleteSync();
            throw StateError('初始化期间出现其他数据库，已停止覆盖');
          }
          File(writePath).renameSync(path);
        } else if (File(writePath).existsSync()) {
          File(writePath).deleteSync();
        }
      }
    }
  }

  Future<void> exportSQLite(String target) async {
    final directoryPath = directory.path, revision = expectedRevision;
    await Isolate.run(() {
      final worker = SpaceRepository(Directory(directoryPath))
        ..loaded = true
        ..expectedRevision = revision;
      return worker._exportDirect(target);
    });
  }

  Future<void> _exportDirect(String target) async {
    final absolute = fileIdentity(target);
    if (absolute == fileIdentity(path) || absolute == fileIdentity(previous)) {
      invalid('不能覆盖活动库或上一份备份');
    }
    await _locked(() async {
      final db = _open(path, readOnly: true);
      try {
        _check(db);
        await _snapshot(db, target);
      } finally {
        db.close();
      }
    });
  }

  /// 用云端快照中的发票表替换本地台账，返回替换的发票数量。
  /// 附件文件本身由调用方按摘要另行恢复。
  Future<int> importInvoiceLedger(String snapshot) async {
    final directoryPath = directory.path;
    final result = await Isolate.run<({int rows, String revision})>(
      () => SpaceRepository(Directory(directoryPath))._importLedger(snapshot),
    );
    expectedRevision = result.revision;
    loaded = true;
    return result.rows;
  }

  ({int rows, String revision}) _importLedger(String snapshot) {
    if (!File(snapshot).existsSync()) invalid('云端备份文件不存在');
    final Database source;
    try {
      source = _open(snapshot);
    } on SqliteException {
      // 早期备份只包含任务数据，不含发票台账。
      return (rows: 0, revision: expectedRevision ?? '');
    }
    Database? target;
    try {
      if (source.userVersion < 4) {
        return (rows: 0, revision: expectedRevision ?? '');
      }
      _upgradeInvoiceSchema(source);
      final rows = source
          .select('SELECT * FROM invoices ORDER BY rowid')
          .toList();
      final files = source
          .select('SELECT * FROM invoice_files ORDER BY rowid')
          .toList();
      target = _open(path);
      _upgradeInvoiceSchema(target);
      final projects = {
        for (final row in target.select('SELECT id FROM projects'))
          row['id'] as String,
      };
      final revision = uid();
      target.execute('BEGIN IMMEDIATE');
      try {
        target.execute('DELETE FROM invoice_files; DELETE FROM invoices;');
        for (final row in rows) {
          final project = row['project'] as String?;
          target.execute(
            'INSERT INTO invoices(id,number,issued,seller,spent,purpose,month,'
            'project,cents,reimbursed,buyer,seller_tax,buyer_tax,tax_cents,net_cents,title,recognition) '
            'VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
            [
              row['id'],
              row['number'] ?? '',
              row['issued'] ?? '',
              row['seller'] ?? '',
              row['spent'] ?? '',
              row['purpose'] ?? '',
              row['month'] ?? '',
              project != null && projects.contains(project) ? project : null,
              row['cents'],
              row['reimbursed'] ?? 0,
              row['buyer'] ?? '',
              row['seller_tax'] ?? '',
              row['buyer_tax'] ?? '',
              row['tax_cents'],
              row['net_cents'],
              row['title'] ?? '',
              row['recognition'] ?? '',
            ],
          );
        }
        for (final row in files) {
          target.execute(
            'INSERT INTO invoice_files(id,invoice,name,extension,original,sha256,bytes) '
            'VALUES(?,?,?,?,?,?,?)',
            [
              row['id'],
              row['invoice'],
              row['name'],
              row['extension'],
              row['original'],
              row['sha256'],
              row['bytes'],
            ],
          );
        }
        target.execute("INSERT OR REPLACE INTO metadata VALUES('revision',?)", [
          revision,
        ]);
        target.execute('COMMIT');
      } catch (_) {
        target.execute('ROLLBACK');
        rethrow;
      }
      return (rows: rows.length, revision: revision);
    } finally {
      source.close();
      target?.close();
    }
  }

  /// 导出备份包：数据库 + 发票原件与附件，按 zip 结构写成 .spacepack。
  Future<void> exportPack(String target) async {
    final directoryPath = directory.path, revision = expectedRevision;
    await Isolate.run(() async {
      final worker = SpaceRepository(Directory(directoryPath))
        ..loaded = true
        ..expectedRevision = revision;
      await worker._exportPackDirect(target);
    });
  }

  Future<void> _exportPackDirect(String target) async {
    final absolute = fileIdentity(target);
    if (absolute == fileIdentity(path) || absolute == fileIdentity(previous)) {
      invalid('不能覆盖活动库或上一份备份');
    }
    final temp = Directory.systemTemp.createTempSync('space-pack-');
    try {
      final database = p.join(temp.path, 'space.sqlite');
      await exportSQLite(database);
      final encoder = ZipFileEncoder()..create(target);
      try {
        encoder.addFileSync(File(database), 'space.sqlite');
        final files = Directory(p.join(directory.path, 'invoices', 'files'));
        if (files.existsSync()) {
          for (final entity in files.listSync(followLinks: false)) {
            if (entity is! File) continue;
            final name = p.basename(entity.path);
            if (name.startsWith('.')) continue;
            encoder.addFileSync(entity, 'invoices/files/$name');
          }
        }
      } finally {
        encoder.closeSync();
      }
      protectPath(target);
    } catch (_) {
      if (File(target).existsSync()) File(target).deleteSync();
      rethrow;
    } finally {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    }
  }

  /// 解包备份到临时目录。旧版 .sqlite 备份同样可用，只是不含附件。
  Future<UnpackedBackup> unpackBackup(String source) => Isolate.run(() {
    final file = File(source);
    if (!file.existsSync()) invalid('备份文件不存在');
    if (file.lengthSync() > 8 * 1024 * 1024 * 1024) invalid('备份文件过大');
    final temp = Directory.systemTemp.createTempSync('space-unpack-');
    final database = p.join(temp.path, 'space.sqlite');
    var files = 0;
    try {
      final handle = file.openSync();
      final Uint8List header;
      try {
        header = handle.readSync(4);
      } finally {
        handle.closeSync();
      }
      final zip = header.length >= 2 && header[0] == 0x50 && header[1] == 0x4B;
      if (!zip) {
        file.copySync(database);
        return UnpackedBackup(temp.path, database, 0);
      }
      final archive = ZipDecoder().decodeStream(InputFileStream(source));
      for (final entry in archive) {
        final name = entry.name.replaceAll('\\', '/');
        if (name != 'space.sqlite' && !name.startsWith('invoices/files/')) {
          continue;
        }
        if (name.split('/').contains('..')) continue;
        final target = File(p.join(temp.path, name));
        target.parent.createSync(recursive: true);
        final output = OutputFileStream(target.path);
        try {
          entry.writeContent(output);
        } finally {
          output.close();
        }
        if (name != 'space.sqlite') files++;
      }
      if (!File(database).existsSync()) invalid('备份包缺少数据库');
      return UnpackedBackup(temp.path, database, files);
    } catch (_) {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
      rethrow;
    }
  });

  /// 把备份包中的附件写回数据目录，已存在同名文件直接覆盖为备份内容。
  Future<int> restorePackFiles(UnpackedBackup pack) => Isolate.run(() {
    final source = Directory(pack.attachments);
    if (!source.existsSync()) return 0;
    final target = Directory(p.join(directory.path, 'invoices', 'files'));
    target.createSync(recursive: true);
    protectPath(directory.path, directory: true);
    protectPath(target.path, directory: true);
    var count = 0;
    for (final entity in source.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.') || name.contains('/') || name.contains('\\')) {
        continue;
      }
      final staged = p.join(target.path, '.$name.restore');
      entity.copySync(staged);
      File(staged).renameSync(p.join(target.path, name));
      protectPath(p.join(target.path, name));
      count++;
    }
    return count;
  });

  Future<void> cleanupBackup(UnpackedBackup pack) async {
    final directory = Directory(pack.directory);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  Future<SpaceState> recover(SpaceState state) async {
    state.validate();
    if (loaded) return save(state);
    return _locked(() async {
      final bad = '$path.damaged.${DateTime.now().millisecondsSinceEpoch}';
      if (File(path).existsSync()) File(path).renameSync(bad);
      try {
        return await _write(state, initialize: true);
      } catch (_) {
        if (File(path).existsSync()) File(path).deleteSync();
        if (File(bad).existsSync()) File(bad).renameSync(path);
        rethrow;
      }
    });
  }
}
