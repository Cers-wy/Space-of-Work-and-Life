import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'drive.dart';

const driveFileTypes = <String, String>{
  'word': 'Word',
  'excel': 'Excel',
  'ppt': 'PPT',
  'pdf': 'PDF',
  'archive': '压缩包',
  'video': '视频',
  'image': '图片',
  'text': '文本',
  'app': '应用程序',
  'other': '其他',
};
const _extensions = <String, Set<String>>{
  'word': {
    'doc',
    'docx',
    'docm',
    'dot',
    'dotx',
    'dotm',
    'rtf',
    'wps',
    'wpt',
    'odt',
    'ott',
  },
  'excel': {
    'xls',
    'xlsx',
    'xlsm',
    'xlsb',
    'xlt',
    'xltx',
    'xltm',
    'et',
    'ett',
    'ods',
    'ots',
  },
  'ppt': {
    'ppt',
    'pptx',
    'pptm',
    'pot',
    'potx',
    'potm',
    'pps',
    'ppsx',
    'ppsm',
    'dps',
    'dpt',
    'odp',
    'otp',
  },
  'pdf': {'pdf'},
  'archive': {
    'zip',
    'rar',
    '7z',
    'tar',
    'gz',
    'bz2',
    'xz',
    'tgz',
    'tbz2',
    'txz',
    'cab',
    'zst',
  },
  'video': {
    'mp4',
    'mov',
    'mkv',
    'avi',
    'wmv',
    'flv',
    'webm',
    'm4v',
    'mpg',
    'mpeg',
    '3gp',
    'mts',
    'm2ts',
  },
  'image': {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'webp',
    'heic',
    'heif',
    'tif',
    'tiff',
    'svg',
    'ico',
    'avif',
    'raw',
    'dng',
  },
  'text': {
    'txt',
    'text',
    'md',
    'markdown',
    'csv',
    'tsv',
    'log',
    'json',
    'xml',
    'yaml',
    'yml',
    'toml',
    'ini',
    'conf',
    'config',
    'sql',
    'html',
    'htm',
    'css',
    'js',
    'ts',
    'py',
    'java',
    'c',
    'cpp',
    'sh',
    'bat',
    'ps1',
  },
  'app': {
    'app',
    'exe',
    'msi',
    'msix',
    'appx',
    'appxbundle',
    'msixbundle',
    'dmg',
    'pkg',
    'apk',
    'aab',
    'deb',
    'rpm',
  },
};
String driveFileType(String name) {
  final extension = path.extension(name).replaceFirst('.', '').toLowerCase();
  return _extensions.entries
          .where((e) => e.value.contains(extension))
          .firstOrNull
          ?.key ??
      'other';
}

class DriveFileFilter extends ChangeNotifier {
  String query = '', date = '';
  final types = <String>{};
  bool get active =>
      query.trim().isNotEmpty || date.isNotEmpty || types.isNotEmpty;
  void changed() => notifyListeners();
  void clear() {
    query = date = '';
    types.clear();
    changed();
  }

  bool matches(DriveFile file) {
    final name = file.name.isEmpty
        ? file.path.split('/').where((p) => p.isNotEmpty).last
        : file.name;
    if (!name.toLowerCase().contains(query.trim().toLowerCase())) return false;
    if (types.isNotEmpty &&
        ((file.folder && !name.toLowerCase().endsWith('.app')) ||
            !types.contains(driveFileType(name)))) {
      return false;
    }
    if (date.isNotEmpty) {
      final d = file.created?.toLocal();
      if (d == null ||
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}' !=
              date) {
        return false;
      }
    }
    return true;
  }
}

/// 先限定直接子项，再做筛选；不会把别的目录文件误当作当前目录结果。
List<DriveFile> driveDirectoryFiles(
  List<DriveFile> files,
  String folder,
  DriveFileFilter filter,
) {
  final result = <DriveFile>[];
  final seen = <String>{};
  for (final f in files) {
    if (!f.path.startsWith(folder)) continue;
    final relative = f.path.substring(folder.length);
    if (relative.isEmpty) continue;
    if (relative.contains('/')) {
      final part = relative.split('/').first;
      if (seen.add(part)) {
        final directory = DriveFile('$folder$part/', '', 0, folder: true);
        if (filter.matches(directory)) result.add(directory);
      }
    } else if (filter.matches(f)) {
      result.add(f);
    }
  }
  return result;
}
