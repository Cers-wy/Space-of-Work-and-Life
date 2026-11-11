import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'files.dart';
import 'repository.dart';

const _invoiceUuid = Uuid();
const invoiceFileExtensions = {'pdf', 'png', 'jpg', 'jpeg'};
const invoiceFileLimit = 32 * 1024 * 1024;

class InvoiceFile {
  final String id, name, path;
  const InvoiceFile(this.id, this.name, this.path);
  bool get isPdf => p.extension(path).toLowerCase() == '.pdf';
}

class InvoiceInfo {
  final String number, issued, seller, spent, purpose, month, project;
  final String buyer, sellerTax, buyerTax;
  final int? cents, taxCents, netCents;
  final bool reimbursed;

  const InvoiceInfo({
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
  String get tax =>
      taxCents == null ? '' : (taxCents! / 100).toStringAsFixed(2);
  String get net =>
      netCents == null ? '' : (netCents! / 100).toStringAsFixed(2);

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

class InvoiceImportResult {
  final int count;
  final List<String> errors;
  const InvoiceImportResult(this.count, this.errors);
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

  Future<InvoiceLedger> load() => Isolate.run(
    () => _database((db) {
      final originals = <String, InvoiceFile>{};
      final attachments = <String, List<InvoiceFile>>{};
      for (final row in db.select(
        'SELECT * FROM invoice_files ORDER BY rowid',
      )) {
        final invoice = row['invoice'] as String;
        if (row['original'] == 1) {
          originals[invoice] = _file(row);
        } else {
          (attachments[invoice] ??= []).add(_file(row));
        }
      }
      return InvoiceLedger(
        [
          for (final row in db.select(
            'SELECT * FROM invoices ORDER BY rowid DESC',
          ))
            InvoiceEntry(
              row['id'] as String,
              originals[row['id']]!,
              attachments[row['id']] ?? const [],
              InvoiceInfo(
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
    }),
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

  Future<void> save(String id, InvoiceInfo info) => Isolate.run(
    () => _database((db) {
      final values = info.values;
      if (info.project.isEmpty) values[6] = null;
      db.execute(
        '''
      UPDATE invoices SET number=?,issued=?,seller=?,spent=?,purpose=?,month=?,project=?,cents=?,reimbursed=?,
        buyer=?,seller_tax=?,buyer_tax=?,tax_cents=?,net_cents=?
      WHERE id=?
    ''',
        [...values, id],
      );
      if (db.updatedRows != 1) throw StateError('这张发票已从台账移除');
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
