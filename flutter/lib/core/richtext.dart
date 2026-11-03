import 'dart:convert';
import 'dart:typed_data';
import 'models.dart';

class RichRun {
  final String text;
  final bool bold, underline;
  final Uint8List? image;
  RichRun({
    this.text = '',
    this.bold = false,
    this.underline = false,
    this.image,
  });
}

// Flat NSFileWrapper format, shared with the existing Space.Core codec.
class FlatRtfd {
  static Map<String, Uint8List> unpack(Uint8List bytes) {
    if (bytes.length > 24 * 1024 * 1024) invalid('富文本超过24 MB');
    if (latin1.decode(bytes.take(5).toList()) == r'{\rtf') {
      return {'TXT.rtf': bytes};
    }
    var offset = 0;
    int read() {
      if (offset + 4 > bytes.length) invalid('RTFD数据不完整');
      final n = ByteData.sublistView(
        bytes,
        offset,
        offset + 4,
      ).getInt32(0, Endian.little);
      offset += 4;
      return n;
    }

    Uint8List take(int n) {
      if (n < 0 || offset + n > bytes.length) invalid('RTFD长度无效');
      final b = Uint8List.sublistView(bytes, offset, offset + n);
      offset += n;
      return b;
    }

    if (latin1.decode(take(4)) != 'rtfd') invalid('富文本不是flat RTFD');
    read();
    read();
    final count = read();
    if (count < 1 || count > 200) invalid('RTFD文件数无效');
    final names = <String>[];
    for (var i = 0; i < count; i++) {
      final size = read();
      if (size < 1 || size > 1024) invalid('RTFD名称无效');
      names.add(utf8.decode(take(size)));
    }
    final sizes = List.generate(count, (_) => read());
    final files = <String, Uint8List>{};
    for (var i = 0; i < count; i++) {
      if (sizes[i] < 8) invalid('RTFD文件长度无效');
      final end = offset + sizes[i];
      if (end > bytes.length) invalid('RTFD文件不完整');
      final kind = read(), length = read();
      if (kind != 1 || length < 0 || offset + length > end) {
        invalid('RTFD文件类型无效');
      }
      final data = take(length);
      if (names[i] != '.') {
        if (files.containsKey(names[i])) invalid('RTFD文件重名');
        files[names[i]] = data;
      }
      offset = end;
    }
    return files;
  }

  static Uint8List pack(Map<String, Uint8List> files) {
    final b = BytesBuilder();
    void integer(int n) {
      final d = ByteData(4)..setInt32(0, n, Endian.little);
      b.add(d.buffer.asUint8List());
    }

    b.add(ascii.encode('rtfd'));
    integer(0);
    integer(3);
    integer(files.length);
    for (final name in files.keys) {
      final bytes = utf8.encode(name);
      integer(bytes.length);
      b.add(bytes);
    }
    for (final bytes in files.values) {
      integer(bytes.length + 8);
    }
    for (final bytes in files.values) {
      integer(1);
      integer(bytes.length);
      b.add(bytes);
    }
    final bytes = b.takeBytes();
    if (bytes.length > 24 * 1024 * 1024) invalid('富文本超过24 MB');
    return bytes;
  }

  static List<RichRun> decode(Uint8List data) {
    final files = unpack(data);
    final raw = filesMissing(files);
    final rtf = latin1.decode(raw), fonts = <int, bool>{};
    for (final m in RegExp(
      r'\\f(\d+)(?:\\[a-z]+-?\d*\s*)+([^;{}]+);',
    ).allMatches(rtf)) {
      fonts[int.parse(m[1]!)] = RegExp(
        'Bold|Semibold',
        caseSensitive: false,
      ).hasMatch(m[2]!);
    }
    final stack = <_RtfState>[];
    var state = _RtfState(), skip = 0, afterImage = false;
    final runs = <RichRun>[];
    void add(String text) {
      if (state.skip || text.isEmpty) return;
      if (skip > 0) {
        final n = skip.clamp(0, text.length);
        skip -= n;
        text = text.substring(n);
      }
      if (afterImage) {
        text = text.replaceFirst(RegExp(r'^[¬\uFFFC]+'), '');
        afterImage = false;
      }
      if (text.isEmpty) return;
      final bold = state.bold || (fonts[state.font] ?? false);
      if (runs.isNotEmpty &&
          runs.last.image == null &&
          runs.last.bold == bold &&
          runs.last.underline == state.underline) {
        final old = runs.removeLast();
        runs.add(
          RichRun(
            text: old.text + text,
            bold: bold,
            underline: state.underline,
          ),
        );
      } else {
        runs.add(RichRun(text: text, bold: bold, underline: state.underline));
      }
    }

    var i = 0;
    while (i < rtf.length) {
      var ch = rtf[i++];
      if (ch == '{') {
        stack.add(state.copy());
        continue;
      }
      if (ch == '}') {
        if (stack.isNotEmpty) state = stack.removeLast();
        continue;
      }
      if (ch != '\\') {
        if (ch != '\r' && ch != '\n') add(ch);
        continue;
      }
      if (i >= rtf.length) break;
      ch = rtf[i++];
      if (ch == '\\' || ch == '{' || ch == '}') {
        add(ch);
        continue;
      }
      if (ch == "'") {
        final bytes = <int>[];
        i -= 2;
        while (i + 3 < rtf.length && rtf[i] == '\\' && rtf[i + 1] == "'") {
          final n = int.tryParse(rtf.substring(i + 2, i + 4), radix: 16);
          if (n == null) invalid('RTF转义无效');
          bytes.add(n);
          i += 4;
        }
        add(latin1.decode(bytes));
        continue;
      }
      if (ch == '\n' || ch == '\r') {
        add('\n');
        continue;
      }
      if (ch == '*') {
        state.skip = true;
        continue;
      }
      if (ch == '~') {
        add('\u00a0');
        continue;
      }
      if (!RegExp('[a-zA-Z]').hasMatch(ch)) continue;
      final start = i - 1;
      while (i < rtf.length && RegExp('[a-zA-Z]').hasMatch(rtf[i])) {
        i++;
      }
      final word = rtf.substring(start, i), argStart = i;
      if (i < rtf.length && rtf[i] == '-') i++;
      while (i < rtf.length && RegExp('[0-9]').hasMatch(rtf[i])) {
        i++;
      }
      final arg = int.tryParse(rtf.substring(argStart, i));
      if (i < rtf.length && rtf[i] == ' ') i++;
      switch (word) {
        case 'fonttbl':
        case 'colortbl':
        case 'stylesheet':
        case 'info':
        case 'pict':
        case 'object':
        case 'filetbl':
          state.skip = true;
        case 'b':
          state.bold = arg == null || arg != 0;
        case 'ul':
          state.underline = arg == null || arg != 0;
        case 'ulnone':
          state.underline = false;
        case 'f':
          state.font = arg ?? 0;
        case 'plain':
          state.bold = false;
          state.underline = false;
          state.font = 0;
        case 'uc':
          state.uc = arg ?? 1;
        case 'u':
          if (!state.skip) {
            skip = 0;
            add(String.fromCharCode((arg ?? 0) & 0xffff));
            skip = state.uc;
          }
        case 'par':
        case 'line':
          add('\n');
        case 'tab':
          add('\t');
        case 'emdash':
          add('—');
        case 'endash':
          add('–');
        case 'bullet':
          add('•');
        case 'NeXTGraphic':
          var end = i;
          while (end < rtf.length && rtf[end] != '\\' && rtf[end] != '}') {
            end++;
          }
          var name = rtf.substring(i, end).trim();
          if (!files.containsKey(name)) {
            name = utf8.decode(latin1.encode(name), allowMalformed: true);
          }
          if (!state.skip && files[name] != null) {
            runs.add(RichRun(image: files[name]));
          }
          state.skip = true;
          afterImage = true;
          i = end;
        case 'bin':
          i = (i + (arg ?? 0)).clamp(i, rtf.length);
      }
    }
    return runs;
  }

  static Uint8List filesMissing(Map<String, Uint8List> files) =>
      files['TXT.rtf'] ?? invalid('RTFD缺少TXT.rtf');
  static Uint8List encode(List<RichRun> runs) {
    final out = StringBuffer(
          r'{\rtf1\ansi\ansicpg1252\cocoartf2908{\fonttbl\f0\fnil PingFangSC-Regular;\f1\fnil PingFangSC-Semibold;}\f0\fs28 ',
        ),
        files = <String, Uint8List>{};
    for (final run in runs) {
      if (run.image != null) {
        final bytes = run.image!;
        final ext = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50
            ? 'png'
            : bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8
            ? 'jpg'
            : 'tiff';
        final name = 'image-${files.length}.$ext';
        files[name] = bytes;
        final dimensions = imageSize(bytes);
        final scale = (480 / dimensions.$1).clamp(0.0, 1.0);
        final fit = (240 / dimensions.$2).clamp(0.0, scale);
        out.write(
          '{{\\NeXTGraphic $name \\width${(dimensions.$1 * fit * 20).round()} \\height${(dimensions.$2 * fit * 20).round()} \\appleattachmentpadding0 \\appleembedtype0 \\appleaqc}¬}',
        );
        continue;
      }
      out.write(run.bold ? r'\f1\b ' : r'\f0\b0 ');
      out.write(run.underline ? r'\ul ' : r'\ulnone ');
      for (final ch in run.text.codeUnits) {
        if (ch == 92 || ch == 123 || ch == 125) {
          out.write('\\${String.fromCharCode(ch)}');
        } else if (ch == 10) {
          out.write(r'\par ');
        } else if (ch == 13) {
          continue;
        } else if (ch == 9) {
          out.write(r'\tab ');
        } else if (ch < 128) {
          out.writeCharCode(ch);
        } else {
          out.write('\\u${ch > 32767 ? ch - 65536 : ch}?');
        }
      }
    }
    out.write('}');
    files['TXT.rtf'] = Uint8List.fromList(latin1.encode(out.toString()));
    return pack(files);
  }
}

class _RtfState {
  bool bold = false, underline = false, skip = false;
  int font = 0, uc = 1;
  _RtfState copy() => _RtfState()
    ..bold = bold
    ..underline = underline
    ..skip = skip
    ..font = font
    ..uc = uc;
}

(int, int) imageSize(Uint8List bytes) {
  if (bytes.length >= 24 && bytes[0] == 0x89 && bytes[1] == 0x50) {
    final data = ByteData.sublistView(bytes);
    return (data.getUint32(16), data.getUint32(20));
  }
  if (bytes.length >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    var i = 2;
    while (i + 8 < bytes.length) {
      if (bytes[i++] != 0xff) continue;
      final marker = bytes[i++];
      if (marker == 0xd8 || marker == 0xd9) continue;
      if (i + 2 > bytes.length) break;
      final length = (bytes[i] << 8) | bytes[i + 1];
      if (length < 2 || i + length > bytes.length) break;
      if ([
        0xc0,
        0xc1,
        0xc2,
        0xc3,
        0xc5,
        0xc6,
        0xc7,
        0xc9,
        0xca,
        0xcb,
        0xcd,
        0xce,
        0xcf,
      ].contains(marker)) {
        return (
          (bytes[i + 5] << 8) | bytes[i + 6],
          (bytes[i + 3] << 8) | bytes[i + 4],
        );
      }
      i += length;
    }
  }
  if (bytes.length > 8 &&
      ((bytes[0] == 0x49 && bytes[1] == 0x49) ||
          (bytes[0] == 0x4d && bytes[1] == 0x4d))) {
    final endian = bytes[0] == 0x49 ? Endian.little : Endian.big;
    final data = ByteData.sublistView(bytes);
    final offset = data.getUint32(4, endian);
    int? width, height;
    if (offset + 2 <= bytes.length) {
      final count = data.getUint16(offset, endian);
      for (
        var i = 0;
        i < count && offset + 2 + (i + 1) * 12 <= bytes.length;
        i++
      ) {
        final pos = offset + 2 + i * 12;
        final tag = data.getUint16(pos, endian),
            type = data.getUint16(pos + 2, endian);
        if ((tag == 256 || tag == 257) &&
            data.getUint32(pos + 4, endian) == 1) {
          final n = type == 3
              ? data.getUint16(pos + 8, endian)
              : data.getUint32(pos + 8, endian);
          if (tag == 256) {
            width = n;
          } else {
            height = n;
          }
        }
      }
    }
    if (width != null && height != null && width > 0 && height > 0) {
      return (width, height);
    }
  }
  invalid('无法读取内嵌图片尺寸，原内容保持不变');
}
