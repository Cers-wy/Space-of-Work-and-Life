import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'files.dart';
import 'package:sqlite3/sqlite3.dart';
import 'models.dart';

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
    final lock = File(
      '${directory.path}/.sqlite-write-lock',
    ).openSync(mode: FileMode.append);
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

  SpaceState readFile(String file) {
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
      if (v < 1 || v > 3) invalid('不支持数据库格式版本 $v');
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
      return s;
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
        final s = readFile(path);
        expectedRevision = s.revision;
        loaded = true;
        return s;
      }
      final s = SpaceState(workspaceID: uid());
      return await _locked(() async {
        if (File(path).existsSync()) {
          final existing = readFile(path);
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
