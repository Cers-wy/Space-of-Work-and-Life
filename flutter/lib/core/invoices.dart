import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'files.dart';
import 'repository.dart';

const _invoiceUuid = Uuid();
const invoiceFileExtensions = {'pdf', 'png', 'jpg', 'jpeg'};
const invoiceFileLimit = 32 * 1024 * 1024;

/// Only nonblank reimbursement fields are included in a batch update.
class InvoiceReimbursementPatch {
  final String month, project, purpose;
  const InvoiceReimbursementPatch({
    this.month = '',
    this.project = '',
    this.purpose = '',
  });

  Map<String, String> get values => {
    if (month.trim().isNotEmpty) 'month': month.trim(),
    if (project.trim().isNotEmpty) 'project': project.trim(),
    if (purpose.trim().isNotEmpty) 'purpose': purpose.trim(),
  };

  void validate() {
    final value = month.trim();
    if (value.isEmpty) return;
    final parsed = DateTime.tryParse('$value-01');
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(value) ||
        parsed == null ||
        parsed.year < 1 ||
        !parsed.toIso8601String().startsWith('$value-01')) {
      throw StateError('报销月份请输入有效的 YYYY-MM');
    }
  }
}

class InvoiceFile {
  final String id, name, path;
  const InvoiceFile(this.id, this.name, this.path);
  bool get isPdf => p.extension(path).toLowerCase() == '.pdf';
}

class InvoiceInfo {
  final String number, issued, seller, spent, purpose, month, project;
  final String buyer, sellerTax, buyerTax, title, recognition;
  final int? cents, taxCents, netCents;
  final bool reimbursed;

  const InvoiceInfo({
    this.title = '',
    this.recognition = '',
    this.number = '',
    this.issued = '',
    this.seller = '',
    this.spent = '',
    this.purpose = '',
    this.month = '',
    this.project = '',
    this.buyer = '',
    this.sellerTax = '',
    this.buyerTax = '',
    this.cents,
    this.taxCents,
    this.netCents,
    this.reimbursed = false,
  });

  String get amount => cents == null ? '' : (cents! / 100).toStringAsFixed(2);
  String get recognitionNotice {
    try {
      final value = jsonDecode(recognition) as Map;
      return value['message'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 2026-11-12：PDF/OCR 解析出的结构化票面数据（明细、合计、人员、校验），
  /// 随 recognition 一起保存在发票记录中，供详情核对与后续扩展使用。
  Map<String, Object?> get recognitionStructure {
    try {
      final value = jsonDecode(recognition) as Map;
      final structure = value['structured'];
      return structure is Map
          ? Map<String, Object?>.from(structure)
          : const <String, Object?>{};
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  String get tax =>
      taxCents == null ? '' : (taxCents! / 100).toStringAsFixed(2);
  String get net =>
      netCents == null ? '' : (netCents! / 100).toStringAsFixed(2);

  Map<String, Object?> get ticketFields => {
    'title': title,
    'number': number,
    'issued': issued,
    'seller': seller,
    'buyer': buyer,
    'seller_tax': sellerTax,
    'buyer_tax': buyerTax,
    'cents': cents,
    'tax_cents': taxCents,
    'net_cents': netCents,
  };

  List<Object?> get values => [
    number,
    issued,
    seller,
    spent,
    purpose,
    month,
    project,
    cents,
    reimbursed ? 1 : 0,
    buyer,
    sellerTax,
    buyerTax,
    taxCents,
    netCents,
    title,
  ];
}

class InvoiceEntry {
  final String id;
  final InvoiceFile original;
  final List<InvoiceFile> attachments;
  final InvoiceInfo info;

  const InvoiceEntry(this.id, this.original, this.attachments, this.info);
}

class InvoiceLedger {
  final List<InvoiceEntry> entries;
  final Map<String, String> projects;
  const InvoiceLedger(this.entries, this.projects);
}

/// SQL-backed list conditions, shared by macOS and Windows.
class InvoiceQuery {
  final String text, month, project, status;
  const InvoiceQuery({
    this.text = '',
    this.month = '',
    this.project = '',
    this.status = '',
  });
}

class InvoicePage {
  final InvoiceLedger ledger;
  final int page, total, totalAll;
  final List<String> months;
  const InvoicePage(
    this.ledger,
    this.page,
    this.total,
    this.totalAll,
    this.months,
  );
}

class InvoiceImportResult {
  final int count;
  final List<String> errors;
  const InvoiceImportResult(this.count, this.errors);
}

/// 云端同步用的一条附件记录：文件、内容摘要与字节数。
class InvoiceSyncFile {
  final InvoiceFile file;
  final String sha256;
  final int bytes;
  const InvoiceSyncFile(this.file, this.sha256, this.bytes);
  String get extension =>
      p.extension(file.path).toLowerCase().replaceFirst('.', '');
}

/// 备份或云端快照中的附件记录，只保留恢复所需的元数据。
class InvoiceSnapshotFile {
  final String id, name, extension, sha256;
  final int bytes;
  const InvoiceSnapshotFile(
    this.id,
    this.name,
    this.extension,
    this.sha256,
    this.bytes,
  );
}

class InvoiceSnapshot {
  final int invoices;
  final List<InvoiceSnapshotFile> files;
  const InvoiceSnapshot(this.invoices, this.files);
  static const empty = InvoiceSnapshot(0, []);
}

/// Invoice records use the existing Space database. The original files are
/// archived alongside it, with projects shared with the task workspace.
class InvoiceRepository {
  final SpaceRepository space;
  InvoiceRepository(this.space);

  String get root => p.join(space.directory.path, 'invoices');
  String get _files => p.join(root, 'files');

  T _database<T>(T Function(Database db) work) {
    final db = space.openInvoiceDatabase();
    try {
      return work(db);
    } finally {
      db.close();
    }
  }

  T _transaction<T>(Database db, T Function() work) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final value = work();
      db.execute('COMMIT');
      return value;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  InvoiceFile _file(Row row) => InvoiceFile(
    row['id'] as String,
    row['name'] as String,
    p.join(_files, '${row['id']}.${row['extension']}'),
  );

  InvoiceLedger _readEntries(Database db, List<Row> rows) {
    final originals = <String, InvoiceFile>{};
    final attachments = <String, List<InvoiceFile>>{};
    // A page loads only its own original/attachment metadata, including OCR data.
    // Chunking also keeps explicit full exports below SQLite's parameter limit.
    for (var offset = 0; offset < rows.length; offset += 400) {
      final ids = rows.skip(offset).take(400).map((r) => r['id']).toList();
      for (final row in db.select(
        'SELECT * FROM invoice_files WHERE invoice IN (${List.filled(ids.length, '?').join(',')}) ORDER BY rowid',
        ids,
      )) {
        final invoice = row['invoice'] as String;
        if (row['original'] == 1) {
          originals[invoice] = _file(row);
        } else {
          (attachments[invoice] ??= []).add(_file(row));
        }
      }
    }
    return InvoiceLedger(
      [
        for (final row in rows)
          InvoiceEntry(
            row['id'] as String,
            originals[row['id']]!,
            attachments[row['id']] ?? const [],
            InvoiceInfo(
              title: row['title'] as String? ?? '',
              recognition: row['recognition'] as String? ?? '',
              number: row['number'] as String,
              issued: row['issued'] as String,
              seller: row['seller'] as String,
              spent: row['spent'] as String,
              purpose: row['purpose'] as String,
              month: row['month'] as String,
              project: row['project'] as String? ?? '',
              cents: row['cents'] as int?,
              reimbursed: row['reimbursed'] == 1,
              buyer: row['buyer'] as String? ?? '',
              sellerTax: row['seller_tax'] as String? ?? '',
              buyerTax: row['buyer_tax'] as String? ?? '',
              taxCents: row['tax_cents'] as int?,
              netCents: row['net_cents'] as int?,
            ),
          ),
      ],
      {
        for (final row in db.select(
          'SELECT id,name FROM projects ORDER BY name',
        ))
          row['id'] as String: row['name'] as String,
      },
    );
  }

  Future<InvoiceLedger> load() => Isolate.run(
    () => _database(
      (db) => _readEntries(
        db,
        db.select('SELECT * FROM invoices ORDER BY rowid DESC'),
      ),
    ),
  );

  ({String sql, List<Object?> args}) _conditions(
    Database db,
    InvoiceQuery query,
  ) {
    final conditions = <String>[];
    final args = <Object?>[];
    for (final filter in {
      'month': query.month,
      'project': query.project,
    }.entries) {
      if (filter.value.isNotEmpty) {
        conditions.add('i.${filter.key} = ?');
        args.add(filter.value);
      }
    }
    if (query.status.isNotEmpty) {
      conditions.add('i.reimbursed = ?');
      args.add(query.status == 'yes' ? 1 : 0);
    }
    final terms = query.text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((v) => v.isNotEmpty);
    if (terms.isNotEmpty) {
      // SQLite's built-in lower() is ASCII-only; preserve Unicode search behavior.
      db.createFunction(
        functionName: 'invoice_fold',
        argumentCount: const AllowedArgumentCount(1),
        function: (args) => (args.first as String).toLowerCase(),
      );
      const content =
          "COALESCE((SELECT group_concat(name, ' ') FROM invoice_files WHERE invoice=i.id), '') || ' ' || i.title || ' ' || i.number || ' ' || i.seller || ' ' || i.spent || ' ' || i.issued || ' ' || i.purpose || ' ' || i.month || ' ' || CASE WHEN i.cents IS NULL THEN '' ELSE printf('%.2f', i.cents / 100.0) END || ' ' || COALESCE((SELECT name FROM projects WHERE id=i.project), '')";
      for (final term in terms) {
        conditions.add('instr(invoice_fold($content), ?) > 0');
        args.add(term);
      }
    }
    return (
      sql: conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}',
      args: args,
    );
  }

  Future<InvoicePage> loadPage({
    InvoiceQuery query = const InvoiceQuery(),
    int page = 0,
    int pageSize = 50,
  }) {
    if (page < 0 || pageSize < 1 || pageSize > 200) {
      throw ArgumentError('Invalid invoice page');
    }
    return Isolate.run(
      () => _database((db) {
        db.execute('BEGIN');
        try {
          final filter = _conditions(db, query);
          final total =
              db
                      .select(
                        'SELECT count(*) AS n FROM invoices i ${filter.sql}',
                        filter.args,
                      )
                      .single['n']
                  as int;
          final actual = total == 0
              ? 0
              : page.clamp(0, (total - 1) ~/ pageSize);
          final rows = db.select(
            'SELECT i.* FROM invoices i ${filter.sql} ORDER BY i.rowid DESC LIMIT ? OFFSET ?',
            [...filter.args, pageSize, actual * pageSize],
          );
          return InvoicePage(
            _readEntries(db, rows),
            actual,
            total,
            db.select('SELECT count(*) AS n FROM invoices').single['n'] as int,
            [
              for (final row in db.select(
                "SELECT DISTINCT month FROM invoices WHERE month != '' ORDER BY month DESC",
              ))
                row['month'] as String,
            ],
          );
        } finally {
          db.execute('ROLLBACK');
        }
      }),
    );
  }

  /// Full matching results are loaded only for an explicit export.
  Future<InvoiceLedger> matching(InvoiceQuery query) => Isolate.run(
    () => _database((db) {
      final filter = _conditions(db, query);
      return _readEntries(
        db,
        db.select(
          'SELECT i.* FROM invoices i ${filter.sql} ORDER BY i.rowid DESC',
          filter.args,
        ),
      );
    }),
  );

  Future<InvoiceEntry?> find(String id) => Isolate.run(
    () => _database(
      (db) => _readEntries(
        db,
        db.select('SELECT * FROM invoices WHERE id=?', [id]),
      ).entries.firstOrNull,
    ),
  );

  Future<Set<String>> existingIds(Iterable<String> ids) {
    final requested = ids.toSet().toList();
    return Isolate.run(
      () => _database((db) {
        final result = <String>{};
        for (var offset = 0; offset < requested.length; offset += 400) {
          final chunk = requested.skip(offset).take(400).toList();
          result.addAll(
            db
                .select(
                  'SELECT id FROM invoices WHERE id IN (${List.filled(chunk.length, '?').join(',')})',
                  chunk,
                )
                .map((r) => r['id'] as String),
          );
        }
        return result;
      }),
    );
  }

  Future<List<String>> pendingRecognitionIds() => Isolate.run(
    () => _database(
      (db) => [
        for (final row in db.select(
          "SELECT id FROM invoices WHERE recognition='' ORDER BY rowid DESC",
        ))
          row['id'] as String,
      ],
    ),
  );

  Future<InvoiceImportResult> importFiles(
    List<String> paths, {
    String? attachmentTo,
  }) => Isolate.run(
    () => _database((db) {
      Directory(_files).createSync(recursive: true);
      protectPath(root, directory: true);
      protectPath(_files, directory: true);
      var count = 0;
      final errors = <String>[];
      for (final path in paths) {
        String? stored;
        try {
          final extension = validateInvoiceFile(path);
          final invoice = attachmentTo ?? _invoiceUuid.v4();
          final fileID = _invoiceUuid.v4();
          final destination = p.join(_files, '$fileID.$extension');
          stored = destination;
          File(path).copySync(destination);
          protectPath(destination);
          _transaction(db, () {
            if (attachmentTo == null) {
              db.execute('INSERT INTO invoices (id) VALUES (?)', [invoice]);
            }
            db.execute(
              'INSERT INTO invoice_files (id,invoice,name,extension,original) VALUES (?,?,?,?,?)',
              [
                fileID,
                invoice,
                p.basename(path),
                extension,
                attachmentTo == null ? 1 : 0,
              ],
            );
          });
          count++;
        } catch (error) {
          if (stored != null) _deleteFile(stored);
          errors.add('${p.basename(path)}：${invoiceError(error)}');
        }
      }
      return InvoiceImportResult(count, errors);
    }),
  );

  Future<void> save(String id, InvoiceInfo info, {InvoiceInfo? baseline}) =>
      Isolate.run(
        () => _database((db) {
          final values = info.values;
          if (info.project.isEmpty) values[6] = null;
          if (baseline != null) {
            final rows = db.select('SELECT * FROM invoices WHERE id=?', [id]);
            if (rows.isEmpty) throw StateError('这张发票已从台账移除');
            const columns = [
              'number',
              'issued',
              'seller',
              'spent',
              'purpose',
              'month',
              'project',
              'cents',
              'reimbursed',
              'buyer',
              'seller_tax',
              'buyer_tax',
              'tax_cents',
              'net_cents',
              'title',
            ];
            final before = baseline.values;
            if (baseline.project.isEmpty) before[6] = null;
            for (var i = 0; i < values.length; i++) {
              if (values[i] == before[i]) values[i] = rows.single[columns[i]];
            }
          }
          db.execute(
            '''
      UPDATE invoices SET number=?,issued=?,seller=?,spent=?,purpose=?,month=?,project=?,cents=?,reimbursed=?,
        buyer=?,seller_tax=?,buyer_tax=?,tax_cents=?,net_cents=?,title=?
      WHERE id=?
    ''',
            [...values, id],
          );
          if (db.updatedRows != 1) throw StateError('这张发票已从台账移除');
        }),
      );

  /// One transaction and one prepared statement, without rewriting ticket fields.
  /// IDs removed while the dialog was open are skipped and excluded from the count.
  Future<int> updateReimbursement(
    List<String> ids,
    InvoiceReimbursementPatch patch,
  ) => Isolate.run(() {
    patch.validate();
    final values = patch.values;
    if (values.isEmpty || ids.isEmpty) return 0;
    return _database(
      (db) => _transaction(db, () {
        if (values.containsKey('project') &&
            db.select('SELECT 1 FROM projects WHERE id=?', [
              values['project'],
            ]).isEmpty) {
          throw StateError('该报销项目已被移除，请重新选择');
        }
        final statement = db.prepare(
          'UPDATE invoices SET ${values.keys.map((key) => '$key=?').join(',')} WHERE id=?',
        );
        var changed = 0;
        try {
          for (final id in ids.toSet()) {
            statement.execute([...values.values, id]);
            changed += db.updatedRows;
          }
        } finally {
          statement.close();
        }
        return changed;
      }),
    );
  });

  Future<void> recognitionError(String id, String message) => Isolate.run(
    () => _database((db) {
      db.execute(
        'UPDATE invoices SET recognition=? WHERE id=? AND recognition=?',
        [
          jsonEncode({'status': 'error', 'message': message, 'automatic': {}}),
          id,
          '',
        ],
      );
    }),
  );

  /// 导入时保护手工票面值；用户主动识别可覆盖有效票面字段。
  /// 个人备注与报销字段始终不进入票面更新，主动识别也不推导消费日期。
  Future<void> applyRecognition(
    String id,
    Map<String, Object?> fields,
    String message, {
    Map<String, Object?>? structured,
    bool replaceExisting = false,
    Map<String, Object?>? expectedFields,
  }) => Isolate.run(
    () => _database((db) {
      _transaction(db, () {
        final rows = db.select('SELECT * FROM invoices WHERE id=?', [id]);
        if (rows.isEmpty) throw StateError('这张发票已从台账移除');
        final row = rows.single;
        Map<String, dynamic> previous = {};
        Map<String, Object?> previousStructure = const {};
        try {
          final stored = Map<String, dynamic>.from(
            jsonDecode(row['recognition'] as String) as Map,
          );
          previous = Map<String, dynamic>.from(
            stored['automatic'] as Map? ?? const {},
          );
          final structure = stored['structured'];
          if (structure is Map) {
            previousStructure = Map<String, Object?>.from(structure);
          }
        } catch (_) {}
        final automatic = <String, Object?>{...previous};
        final updates = <String, Object?>{};
        const allowed = {
          'title',
          'number',
          'issued',
          'seller',
          'buyer',
          'seller_tax',
          'buyer_tax',
          'cents',
          'tax_cents',
          'net_cents',
        };
        for (final item in fields.entries) {
          if (!allowed.contains(item.key) ||
              item.value == null ||
              item.value == '') {
            continue;
          }
          final writable = replaceExisting
              ? expectedFields == null ||
                    row[item.key] == expectedFields[item.key]
              : row[item.key] == null ||
                    row[item.key] == '' ||
                    row[item.key] == previous[item.key];
          if (writable) {
            updates[item.key] = item.value;
            automatic[item.key] = item.value;
          }
        }
        if (!replaceExisting &&
            (row['spent'] as String).isEmpty &&
            fields['issued'] is String) {
          updates['spent'] = fields['issued'];
          if ((row['month'] as String).isEmpty) {
            updates['month'] = (fields['issued'] as String).substring(0, 7);
          }
        }
        updates['recognition'] = jsonEncode({
          'status': message.isEmpty ? 'complete' : 'review',
          'message': message,
          'automatic': automatic,
          // 结构化数据保留最近一次有明细的结果，避免不完整识别清空历史结构。
          'structured':
              structured == null ||
                  (structured['items'] as List? ?? const []).isEmpty
              ? previousStructure
              : structured,
        });
        db.execute(
          'UPDATE invoices SET ${updates.keys.map((k) => '$k=?').join(',')} WHERE id=?',
          [...updates.values, id],
        );
      });
    }),
  );

  Future<void> delete(String id) => Isolate.run(
    () => _database((db) {
      final removed = _transaction(db, () {
        final files = db
            .select('SELECT * FROM invoice_files WHERE invoice=?', [id])
            .map(_file)
            .toList();
        db.execute('DELETE FROM invoices WHERE id=?', [id]);
        return files;
      });
      for (final file in removed) {
        _deleteFile(file.path);
      }
    }),
  );

  Future<void> removeAttachment(String invoice, String fileID) => Isolate.run(
    () => _database((db) {
      final file = _transaction(db, () {
        final rows = db.select(
          'SELECT * FROM invoice_files WHERE id=? AND invoice=? AND original=0',
          [fileID, invoice],
        );
        if (rows.isEmpty) return null;
        db.execute('DELETE FROM invoice_files WHERE id=?', [fileID]);
        return _file(rows.single);
      });
      if (file != null) _deleteFile(file.path);
    }),
  );

  void _deleteFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Record deletion has committed. A later cleanup can remove this orphan.
    }
  }

  Future<void> saveCopy(InvoiceFile file, String destination) =>
      Isolate.run(() {
        checkDestination(destination);
        writeInvoiceOutput(
          destination,
          (staged) => File(file.path).copySync(staged),
        );
      });

  /// 同步清单：补齐缺失的内容摘要与字节数，只统计实际存在的文件。
  Future<List<InvoiceSyncFile>> syncManifest() => Isolate.run(
    () => _database((db) {
      final entries = <InvoiceSyncFile>[];
      for (final row in db.select(
        'SELECT * FROM invoice_files ORDER BY rowid',
      )) {
        final file = _file(row);
        final handle = File(file.path);
        if (!handle.existsSync()) continue;
        final length = handle.lengthSync();
        var digest = row['sha256'] as String?;
        if (digest == null || digest.length != 64 || row['bytes'] != length) {
          digest = _fileDigest(handle);
          db.execute('UPDATE invoice_files SET sha256=?,bytes=? WHERE id=?', [
            digest,
            length,
            file.id,
          ]);
        }
        entries.add(InvoiceSyncFile(file, digest, length));
      }
      return entries;
    }),
  );

  /// 本地附件已有的摘要，恢复时只下载缺失或内容不同的文件。
  Future<Map<String, String>> localFileDigests() => Isolate.run(
    () => _database(
      (db) => {
        for (final row in db.select('SELECT id,sha256 FROM invoice_files'))
          row['id'] as String: (row['sha256'] as String?) ?? '',
      },
    ),
  );

  /// 写入从云端恢复的附件：先写临时文件再改名，避免留下半截文件。
  Future<void> writeSyncedFile(String id, String extension, List<int> bytes) =>
      Isolate.run(() {
        Directory(_files).createSync(recursive: true);
        protectPath(root, directory: true);
        protectPath(_files, directory: true);
        final target = p.join(_files, '$id.$extension');
        final staged = p.join(_files, '.$id.sync');
        File(staged).writeAsBytesSync(bytes, flush: true);
        File(staged).renameSync(target);
        protectPath(target);
      });

  /// 读取备份包或云端快照中的发票数量与附件清单。
  Future<InvoiceSnapshot> readSnapshot(String snapshot) => Isolate.run(() {
    final source = File(snapshot);
    if (!source.existsSync()) return InvoiceSnapshot.empty;
    try {
      final handle = source.openSync();
      final List<int> header;
      try {
        header = handle.readSync(16);
      } finally {
        handle.closeSync();
      }
      if (String.fromCharCodes(header) != 'SQLite format 3\u0000') {
        return InvoiceSnapshot.empty;
      }
    } on FileSystemException {
      return InvoiceSnapshot.empty;
    }
    final db = sqlite3.open(snapshot, mode: OpenMode.readOnly);
    try {
      if (db.userVersion < 4) return InvoiceSnapshot.empty;
      final invoices =
          db.select('SELECT COUNT(*) AS n FROM invoices').first['n'] as int;
      if (db.userVersion < 7) return InvoiceSnapshot(invoices, const []);
      return InvoiceSnapshot(invoices, [
        for (final row in db.select(
          'SELECT id,name,extension,sha256,bytes FROM invoice_files ORDER BY rowid',
        ))
          if ((row['sha256'] as String?)?.isNotEmpty == true)
            InvoiceSnapshotFile(
              row['id'] as String,
              row['name'] as String,
              row['extension'] as String,
              row['sha256'] as String,
              (row['bytes'] as int?) ?? 0,
            ),
      ]);
    } finally {
      db.close();
    }
  });

  void checkDestination(String destination) {
    final data = fileIdentity(space.directory.path);
    final target = fileIdentity(destination);
    if (p.equals(data, target) || p.isWithin(data, target)) {
      throw StateError('请选择 Space 数据目录之外的保存位置');
    }
  }
}

String invoiceError(Object error) => switch (error) {
  StateError() => error.message,
  FileSystemException() => error.message,
  _ => error.toString(),
};

/// 流式计算文件摘要，避免把 32 MB 的发票整块读进内存。
String _fileDigest(File file) {
  final sink = _DigestSink();
  final input = sha256.startChunkedConversion(sink);
  final stream = file.openSync();
  try {
    while (true) {
      final chunk = stream.readSync(256 * 1024);
      if (chunk.isEmpty) break;
      input.add(chunk);
    }
  } finally {
    stream.closeSync();
  }
  input.close();
  final digest = sink.value;
  if (digest == null) throw StateError('无法计算文件摘要');
  return digest.toString();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

String validateInvoiceFile(String path, {bool pdfOnly = false}) {
  final extension = p.extension(path).toLowerCase().replaceFirst('.', '');
  if (!invoiceFileExtensions.contains(extension) ||
      (pdfOnly && extension != 'pdf')) {
    throw StateError(pdfOnly ? '请选择 PDF 发票' : '支持 PDF、JPG、PNG 文件');
  }
  final file = File(path);
  final length = file.lengthSync();
  if (length == 0 || length > invoiceFileLimit) {
    throw StateError('文件为空或超过 32 MB');
  }
  final stream = file.openSync();
  final Uint8List header;
  try {
    header = stream.readSync(1024);
  } finally {
    stream.closeSync();
  }
  final valid = switch (extension) {
    'pdf' => String.fromCharCodes(header).contains('%PDF-'),
    'png' =>
      header.length >= 8 &&
          header[0] == 137 &&
          header[1] == 80 &&
          header[2] == 78 &&
          header[3] == 71,
    _ =>
      header.length >= 3 &&
          header[0] == 255 &&
          header[1] == 216 &&
          header[2] == 255,
  };
  if (!valid) throw StateError('文件内容与格式不符或已损坏');
  return extension;
}

String invoiceOutputStage(String destination) =>
    p.join(p.dirname(destination), '.space-${_invoiceUuid.v4()}.tmp');

void writeInvoiceOutput(
  String destination,
  void Function(String staged) write,
) {
  final staged = File(invoiceOutputStage(destination));
  try {
    write(staged.path);
    staged.renameSync(destination);
  } finally {
    if (staged.existsSync()) staged.deleteSync();
  }
}
