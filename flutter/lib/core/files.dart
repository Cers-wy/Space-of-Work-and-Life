import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

final _chmod = DynamicLibrary.process()
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Uint32),
      int Function(Pointer<Utf8>, int)
    >('chmod');
void protectPath(String path, {bool directory = false}) {
  if (Platform.isWindows) return;
  final native = path.toNativeUtf8();
  try {
    if (_chmod(native, directory ? 448 : 384) != 0) {
      throw FileSystemException('无法设置本地数据权限', path);
    }
  } finally {
    malloc.free(native);
  }
}

String fileIdentity(String path) {
  final f = File(path);
  if (f.existsSync()) {
    final resolved = f.resolveSymbolicLinksSync();
    return Platform.isWindows ? resolved.toLowerCase() : resolved;
  }
  final parent = f.parent;
  final resolved = p.normalize(
    p.join(
      parent.existsSync()
          ? parent.resolveSymbolicLinksSync()
          : parent.absolute.path,
      p.basename(path),
    ),
  );
  return Platform.isWindows ? resolved.toLowerCase() : resolved;
}
