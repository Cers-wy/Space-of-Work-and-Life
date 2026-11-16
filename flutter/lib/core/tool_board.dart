import 'dart:convert';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

const toolBoardKey = 'toolBoard.v1';
const _uuid = Uuid();

String validateToolSvg(String value) {
  if (utf8.encode(value).length > 128 * 1024) {
    throw const FormatException('SVG 图标不能超过 128 KB');
  }
  final doc = XmlDocument.parse(value);
  if (doc.rootElement.name.local != 'svg') {
    throw const FormatException('请选择有效的 SVG 图标');
  }
  void references(String text) {
    if (text.toLowerCase().contains('@import')) {
      throw const FormatException('图标不能引用外部资源');
    }
    for (final m in RegExp(
      r'url\(([^)]+)\)',
      caseSensitive: false,
    ).allMatches(text)) {
      final target = m[1]!.trim().replaceAll(RegExp('["\x27]'), '');
      if (!target.startsWith('#')) throw const FormatException('图标不能引用外部资源');
    }
  }

  for (final node in doc.descendants) {
    if (node is XmlDoctype) throw const FormatException('请选择不含外部文档定义的 SVG');
    if (node is! XmlElement) continue;
    if (['script', 'foreignObject', 'image'].contains(node.name.local)) {
      throw const FormatException('请选择独立的矢量图标');
    }
    for (final a in node.attributes) {
      if (a.name.local.toLowerCase().startsWith('on') ||
          (a.name.local == 'href' && !a.value.startsWith('#'))) {
        throw const FormatException('图标不能包含脚本或外部资源');
      }
      references(a.value);
    }
    if (node.name.local == 'style') references(node.innerText);
  }
  return doc.toXmlString();
}

class ToolLink {
  final String id, name, kind, target, svg;
  const ToolLink({
    required this.id,
    required this.name,
    required this.kind,
    required this.target,
    this.svg = '',
  });
  factory ToolLink.create({
    required String name,
    required String kind,
    required String target,
    String svg = '',
  }) => ToolLink(
    id: _uuid.v4(),
    name: name.trim(),
    kind: kind,
    target: target.trim(),
    svg: svg,
  );
  void validate() {
    if (name.trim().isEmpty || name.length > 60) {
      throw const FormatException('工具名称为 1 至 60 个字');
    }
    if (!['local', 'web'].contains(kind) || target.trim().isEmpty) {
      throw const FormatException('请选择工具入口');
    }
    if (kind == 'web') {
      final uri = Uri.tryParse(target);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('请输入完整的 http:// 或 https:// 网页地址');
      }
    }
    if (svg.isNotEmpty) validateToolSvg(svg);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'target': target,
    'svg': svg,
  };
  factory ToolLink.fromJson(Map j) => ToolLink(
    id: '${j['id']}',
    name: '${j['name'] ?? ''}',
    kind: '${j['kind'] ?? 'web'}',
    target: '${j['target'] ?? ''}',
    svg: '${j['svg'] ?? ''}',
  );
}

class ToolModule {
  final String id, name, description, builtin, svg, defaultTool;
  final int span;
  final double height;
  final bool hidden;
  final List<ToolLink> tools;
  const ToolModule({
    required this.id,
    required this.name,
    this.description = '',
    this.builtin = '',
    this.svg = '',
    this.defaultTool = '',
    this.span = 6,
    this.height = 208,
    this.hidden = false,
    this.tools = const [],
  });
  factory ToolModule.create(
    String name,
    String description, {
    String builtin = '',
    String svg = '',
  }) => ToolModule(
    id: _uuid.v4(),
    name: name.trim(),
    description: description.trim(),
    builtin: builtin,
    svg: svg,
    height: builtin == 'merge' ? 312 : 208,
  );
  int get minSpan => builtin.isEmpty ? 3 : 6;
  double get minHeight => builtin == 'drive'
      ? (tools.isEmpty ? 208 : 320)
      : builtin == 'merge'
      ? (tools.isEmpty ? 248 : 360)
      : 144;
  ToolModule copy({
    String? name,
    String? description,
    String? svg,
    String? defaultTool,
    int? span,
    double? height,
    bool? hidden,
    List<ToolLink>? tools,
  }) => ToolModule(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    builtin: builtin,
    svg: svg ?? this.svg,
    defaultTool: defaultTool ?? this.defaultTool,
    span: span ?? this.span,
    height: height ?? this.height,
    hidden: hidden ?? this.hidden,
    tools: tools ?? this.tools,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'builtin': builtin,
    'svg': svg,
    'defaultTool': defaultTool,
    'span': span,
    'height': height,
    'hidden': hidden,
    'tools': tools.map((t) => t.toJson()).toList(),
  };
  factory ToolModule.fromJson(Map j) => ToolModule(
    id: '${j['id']}',
    name: '${j['name'] ?? ''}',
    description: '${j['description'] ?? ''}',
    builtin: '${j['builtin'] ?? ''}',
    svg: '${j['svg'] ?? ''}',
    defaultTool: '${j['defaultTool'] ?? ''}',
    span: ((j['span'] as num?)?.toInt() ?? 6).clamp(3, 12),
    height: ((j['height'] as num?)?.toDouble() ?? 208).clamp(144, 800),
    hidden: j['hidden'] == true,
    tools: [
      for (final t in j['tools'] as List? ?? []) ToolLink.fromJson(t as Map),
    ],
  );
}

List<ToolModule> defaultToolModules() => const [
  ToolModule(id: 'merge', name: '发票处理', builtin: 'merge', span: 7, height: 312),
  ToolModule(id: 'documents', name: '文档处理', span: 5, height: 150),
  ToolModule(id: 'images', name: '图片处理', span: 5, height: 150),
  ToolModule(id: 'drive', name: '文件管理', builtin: 'drive'),
  ToolModule(id: 'data', name: '数据处理'),
  ToolModule(id: 'text', name: '文本处理', height: 160),
  ToolModule(id: 'other', name: '其他工具', height: 160),
];

/// ASCII chunks fit the existing 8 KiB per-setting limit. SVG bytes stay in the
/// same SQLite settings and existing backup/sync format, never temporary files.
Map<String, String> encodeToolBoard(
  List<ToolModule> modules,
  Map<String, String> settings,
) {
  final encoded = base64Encode(
    utf8.encode(
      jsonEncode({
        'version': 1,
        'modules': modules.map((m) => m.toJson()).toList(),
      }),
    ),
  );
  final count = (encoded.length / 6400).ceil();
  final old = (int.tryParse(settings['$toolBoardKey.parts'] ?? '') ?? 0).clamp(0, 64);
  if (count > 64 ||
      settings.keys.where((k) => !k.startsWith('$toolBoardKey.')).length +
              count +
              1 >
          256) {
    throw const FormatException('工具配置过大，请精简 SVG 图标');
  }
  return {
    '$toolBoardKey.parts': '$count',
    for (var i = 0; i < math.max(count, old); i++)
      '$toolBoardKey.$i': i < count
          ? encoded.substring(
              i * 6400,
              math.min((i + 1) * 6400, encoded.length),
            )
          : '',
  };
}

List<ToolModule> decodeToolBoard(Map<String, String> settings) {
  final raw = settings['$toolBoardKey.parts'];
  if (raw == null) return defaultToolModules();
  final count = int.parse(raw);
  if (count < 1 || count > 64) throw const FormatException('工具配置无法读取');
  final data = jsonDecode(
    utf8.decode(
      base64Decode(
        [for (var i = 0; i < count; i++) settings['$toolBoardKey.$i'] ?? '']
            .join(),
      ),
    ),
  ) as Map;
  if (data['version'] != 1) throw const FormatException('工具配置版本暂不支持');
  return [
    for (final m in data['modules'] as List) ToolModule.fromJson(m as Map),
  ];
}

List<({double x, double y, double width, double height})> toolBoardLayout(
  List<ToolModule> modules,
  double width,
) {
  final columns = width < 640 ? 1 : 12;
  final unit = (width + 12) / columns;
  final bottom = List<double>.filled(columns, 0);
  return [
    for (final m in modules)
      (() {
        final span = columns == 1 ? 1 : math.max(m.minSpan, m.span);
        var x = 0, y = double.infinity;
        for (var i = 0; i <= columns - span; i++) {
          final top = bottom.skip(i).take(span).reduce(math.max);
          if (top < y) {
            x = i;
            y = top;
          }
        }
        final height = math.max(m.height, m.minHeight);
        for (var i = x; i < x + span; i++) {
          bottom[i] = y + height + 12;
        }
        return (x: x * unit, y: y, width: span * unit - 12, height: height);
      })(),
  ];
}
