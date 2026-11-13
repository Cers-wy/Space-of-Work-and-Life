import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/invoice_export.dart';
import '../core/invoice_pdf.dart';
import '../core/invoices.dart';
import '../core/invoice_recognition.dart';
import '../host.dart';
import '../store.dart';
import 'controls.dart';
import 'dialogs.dart';
import 'invoice_workspace.dart';
import 'theme.dart';

Future<T?> invoiceModal<T>(SpaceStore store, Future<T?> Function() open) async {
  if (store.modal) return null;
  store.modal = true;
  store.refreshQuery();
  try {
    return await open();
  } finally {
    store.modal = false;
    store.refreshQuery();
  }
}

/// 2026-11-12：左侧空白点击关闭的请求由详情面板注册，面板自己判断
/// 是否有未保存修改，避免把 dirty 状态提升到弹窗层。
class _InvoiceDetailsDismiss {
  Future<bool> Function()? request;
}

/// 未保存修改时的三选确认，沿用 confirm 的 PopupSurface / SpaceButton.form 风格。
Future<String?> confirmInvoiceClose(BuildContext context) => showDialog<String>(
  context: context,
  builder: (c) {
    final p = Palette.of(c);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: 420,
        child: PopupSurface(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('保存修改？', style: textStyle(p, size: 16, bold: true)),
              const SizedBox(height: 16),
              Text('发票信息有尚未保存的修改，是否保存后关闭？', style: textStyle(p)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SpaceButton.form('取消', onPressed: () => Navigator.pop(c)),
                  const SizedBox(width: 8),
                  SpaceButton.form(
                    '不保存',
                    danger: true,
                    onPressed: () => Navigator.pop(c, 'discard'),
                  ),
                  const SizedBox(width: 8),
                  SpaceButton.form(
                    '保存',
                    primary: true,
                    onPressed: () => Navigator.pop(c, 'save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  },
);

Future<void> showInvoiceDetails(
  BuildContext context,
  SpaceStore store,
  InvoiceSession session,
  String id,
) {
  final dismiss = _InvoiceDetailsDismiss();
  return invoiceModal(
    store,
    () => showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '发票详情',
      barrierColor: Colors.black.withValues(alpha: .18),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 210),
      transitionBuilder: (context, animation, secondary, child) =>
          SlideTransition(
            position: Tween(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).chain(CurveTween(curve: spaceCurve)).animate(animation),
            child: child,
          ),
      pageBuilder: (context, a, b) => LayoutBuilder(
        builder: (c, box) {
          // 面板宽度演进：780 → 390（收窄一半）→ 520（在 390 上再增加 1/3），
          // 窄窗口仍按可用宽度自适应。
          const targetWidth = 520.0;
          final inset = box.maxWidth >= 760 ? 32.0 : 16.0;
          final width = math.min(targetWidth, box.maxWidth - inset);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左侧空白：无修改直接关闭，有修改由面板弹出保存询问。
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('invoice-details-dismiss-area'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => dismiss.request?.call(),
                  child: const SizedBox.expand(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  key: const ValueKey('invoice-details-sheet'),
                  width: width,
                  height: double.infinity,
                  child: Material(
                    type: MaterialType.transparency,
                    child: _InvoiceDetails(
                      store: store,
                      session: session,
                      id: id,
                      dismiss: dismiss,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _InvoiceDetails extends StatefulWidget {
  final SpaceStore store;
  final InvoiceSession session;
  final String id;
  final _InvoiceDetailsDismiss dismiss;
  const _InvoiceDetails({
    required this.store,
    required this.session,
    required this.id,
    required this.dismiss,
  });

  @override
  State<_InvoiceDetails> createState() => _InvoiceDetailsState();
}

class _InvoiceDetailsState extends State<_InvoiceDetails> {
  late InvoiceEntry entry = session.ledger!.entries.firstWhere(
    (e) => e.id == widget.id,
  );
  late final inputs = {
    '发票名称': TextEditingController(text: entry.info.title),
    '票号': TextEditingController(text: entry.info.number),
    '开票日期': TextEditingController(text: entry.info.issued),
    '销售方': TextEditingController(text: entry.info.seller),
    '销售方税号': TextEditingController(text: entry.info.sellerTax),
    '购买方': TextEditingController(text: entry.info.buyer),
    '购买方税号': TextEditingController(text: entry.info.buyerTax),
    '金额': TextEditingController(text: entry.info.amount),
    '税额': TextEditingController(text: entry.info.tax),
    '未税金额': TextEditingController(text: entry.info.net),
    '消费日期': TextEditingController(text: entry.info.spent),
    '备注': TextEditingController(text: entry.info.purpose),
    '报销月份': TextEditingController(text: entry.info.month),
  };
  late String project = entry.info.project;
  late bool reimbursed = entry.info.reimbursed;
  late bool monthAuto =
      entry.info.month.isEmpty ||
      (entry.info.spent.length >= 7 &&
          entry.info.month == entry.info.spent.substring(0, 7));
  bool busy = false, dirty = false;
  String? error, notice;

  /// 当前预览的文件；为空表示发票原件。
  String? selectedId;
  InvoiceSession get session => widget.session;

  /// 原件在前、附件在后的展示顺序。
  List<InvoiceFile> get files => [entry.original, ...entry.attachments];
  int get fileIndex {
    final index = files.indexWhere((f) => f.id == selectedId);
    return index < 0 ? 0 : index;
  }

  InvoiceFile get displayed {
    final index = fileIndex;
    return index == 0 ? entry.original : entry.attachments[index - 1];
  }

  bool get attachmentSelected => displayed.id != entry.original.id;

  @override
  void initState() {
    super.initState();
    if (entry.info.recognitionNotice.isNotEmpty) {
      notice = entry.info.recognitionNotice;
    }
    // 左侧空白、标题栏关闭按钮、Esc 走同一套「有修改则先问保存」流程。
    widget.dismiss.request = requestClose;
  }

  @override
  void dispose() {
    widget.dismiss.request = null;
    for (final input in inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  Future<void> close() async {
    await requestClose();
  }

  Future<bool> requestClose() async {
    if (busy) return false;
    if (!dirty) {
      if (mounted) Navigator.pop(context);
      return true;
    }
    final choice = await confirmInvoiceClose(context);
    if (!mounted) return false;
    if (choice == 'save') {
      await save();
      return true;
    }
    if (choice == 'discard') {
      Navigator.pop(context);
      return true;
    }
    return false;
  }

  Future<void> act(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = notice = null;
    });
    try {
      await work();
    } catch (e) {
      error = invoiceError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reload() async {
    await session.refresh();
    session.update(() {});
    entry = session.ledger!.entries.firstWhere((e) => e.id == widget.id);
    if (selectedId != null &&
        !entry.attachments.any((f) => f.id == selectedId)) {
      selectedId = null;
    }
  }

  String value(String key) => inputs[key]!.text.trim();

  String date(String key, {bool month = false}) {
    final v = value(key);
    if (v.isEmpty) return v;
    final format = month
        ? RegExp(r'^\d{4}-\d{2}$')
        : RegExp(r'^\d{4}-\d{2}-\d{2}$');
    final full = month ? '$v-01' : v;
    final parsed = DateTime.tryParse(full);
    if (!format.hasMatch(v) ||
        parsed == null ||
        !parsed.toIso8601String().startsWith(full)) {
      throw StateError('$key 请输入${month ? ' YYYY-MM' : ' YYYY-MM-DD'}');
    }
    return v;
  }

  int? amountCents(String key) {
    final text = value(key);
    if (text.isEmpty) return null;
    final amount = double.tryParse(text);
    if (!RegExp(r'^-?\d{1,12}(\.\d{1,2})?$').hasMatch(text) || amount == null) {
      throw StateError('请输入有效$key，最多保留两位小数');
    }
    return (amount * 100).round();
  }

  Future<void> save() => act(() async {
    await session.repo.save(
      widget.id,
      InvoiceInfo(
        title: value('发票名称'),
        number: value('票号'),
        issued: date('开票日期'),
        seller: value('销售方'),
        sellerTax: value('销售方税号'),
        buyer: value('购买方'),
        buyerTax: value('购买方税号'),
        cents: amountCents('金额'),
        taxCents: amountCents('税额'),
        netCents: amountCents('未税金额'),
        spent: date('消费日期'),
        purpose: value('备注'),
        month: date('报销月份', month: true),
        project: project,
        reimbursed: reimbursed,
      ),
      baseline: entry.info,
    );
    await reload();
    dirty = false;
    notice = '发票信息已保存';
    session.update(() => session.notice = notice);
    if (mounted) Navigator.pop(context);
  });

  static const recognitionLabels = {
    'title': '发票名称',
    'number': '票号',
    'issued': '开票日期',
    'seller': '销售方',
    'buyer': '购买方',
    'seller_tax': '销售方税号',
    'buyer_tax': '购买方税号',
    'cents': '金额',
    'tax_cents': '税额',
    'net_cents': '未税金额',
  };

  Map<String, String> formValues(InvoiceInfo info) => {
    '发票名称': info.title,
    '票号': info.number,
    '开票日期': info.issued,
    '销售方': info.seller,
    '销售方税号': info.sellerTax,
    '购买方': info.buyer,
    '购买方税号': info.buyerTax,
    '金额': info.amount,
    '税额': info.tax,
    '未税金额': info.net,
    '消费日期': info.spent,
    '备注': info.purpose,
    '报销月份': info.month,
  };

  void fillRecognized(InvoiceRecognition result, {bool saved = true}) {
    final stored = formValues(entry.info);
    for (final item in result.fields.entries) {
      final label = recognitionLabels[item.key];
      if (label == null || item.value == null || item.value == '') continue;
      inputs[label]!.text = saved
          ? stored[label]!
          : item.value is int
          ? ((item.value as int) / 100).toStringAsFixed(2)
          : item.value.toString();
    }
    // 仅本次已落库的识别字段更新基准；未命中的手工输入保留为待保存。
    dirty =
        inputs.entries.any((i) => i.value.text.trim() != stored[i.key]) ||
        project != entry.info.project ||
        reimbursed != entry.info.reimbursed;
  }

  Future<void> recognize() => act(() async {
    try {
      final before = entry.info;
      final result = await session.recognizeEntry(widget.id);
      final baseline = formValues(before);
      final untouched = inputs.entries
          .where((i) => i.value.text.trim() == baseline[i.key])
          .map((i) => i.key)
          .toSet();
      await reload();
      final stored = formValues(entry.info);
      for (final label in untouched) {
        inputs[label]!.text = stored[label]!;
      }
      if (project == before.project) project = entry.info.project;
      if (reimbursed == before.reimbursed) reimbursed = entry.info.reimbursed;
      fillRecognized(result);
      // 不增加常驻“已自动保存”提示条；异常/缺失信息仍在原有页脚反馈。
      notice = result.fields.isEmpty
          ? '未识别到可用字段，请核对原件或调整识别方式'
          : result.message.isEmpty
          ? null
          : result.message;
      session.update(() {
        session.notice = result.fields.isEmpty ? '未识别到可用字段' : '票面信息已更新';
        session.error = null;
      });
    } on InvoiceRecognitionSaveError catch (e) {
      fillRecognized(e.result, saved: false);
      rethrow;
    }
  });

  Future<void> remove() async {
    if (!await confirm(
      context,
      '删除发票？',
      '将移除台账记录、原件和关联附件。',
      '删除发票',
      destructive: true,
    )) {
      return;
    }
    if (!mounted) return;
    await act(() async {
      await session.deleteEntry(widget.id);
      await session.refresh();
      session.update(() => session.notice = '已删除发票');
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> addAttachments() => act(() async {
    final paths = await DesktopHost.openFiles(
      title: '添加行程单或附件',
      extensions: invoiceFileExtensions.toList(),
    );
    if (paths.isEmpty) return;
    final result = await session.repo.importFiles(
      paths,
      attachmentTo: widget.id,
    );
    await reload();
    notice = '已添加 ${result.count} 个附件';
    if (result.errors.isNotEmpty) error = result.errors.join('\n');
  });

  Future<void> removeAttachment(InvoiceFile f) async {
    if (!await confirm(context, '删除附件？', f.name, '删除附件', destructive: true) ||
        !mounted) {
      return;
    }
    await act(() async {
      await session.repo.removeAttachment(widget.id, f.id);
      await reload();
      selectedId = null;
      notice = '已删除附件';
    });
  }

  void selectFile(String id) => setState(() => selectedId = id);

  Future<void> download(InvoiceFile f) => act(() async {
    final target = await DesktopHost.saveFile(
      f.name,
      title: '下载${f.id == entry.original.id ? '发票' : '附件'}',
    );
    if (target == null) return;
    await session.repo.saveCopy(f, target);
    notice = '文件已保存';
  });

  Future<void> openPreview(InvoiceFile f) =>
      act(() => DesktopHost.preview(f.path));

  /// 触控板与惯性滚轮会连发信号，节流避免一次滚动跳过多个文件。
  DateTime? lastWheel;

  void wheelFiles(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || files.length < 2) return;
    final now = DateTime.now();
    final last = lastWheel;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 160)) {
      return;
    }
    final next = fileIndex + (event.scrollDelta.dy > 0 ? 1 : -1);
    if (next < 0 || next >= files.length) return;
    lastWheel = now;
    selectFile(files[next].id);
  }

  /// 原件与附件共用一个入口，数量合计显示在标题旁，不逐个展开标签页。
  Widget _fileHeader(Palette p, List<InvoiceFile> files) => Row(
    children: [
      SpaceIcon('invoice', size: 15, color: p.accent),
      const SizedBox(width: 8),
      Text(
        '发票与附件',
        style: textStyle(p, size: 12.5, bold: true, color: p.secondary),
      ),
      const SizedBox(width: 8),
      _fileCount(p, files.length),
      const Spacer(),
      if (files.length > 1) ...[
        IconButtonS(
          'left',
          '上一个文件（预览区滚轮也可切换）',
          size: 28,
          iconSize: 14,
          onPressed: busy || fileIndex == 0
              ? null
              : () => selectFile(files[fileIndex - 1].id),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${fileIndex + 1} / ${files.length}',
            style: textStyle(p, size: 11, color: p.muted),
          ),
        ),
        IconButtonS(
          'right',
          '下一个文件（预览区滚轮也可切换）',
          size: 28,
          iconSize: 14,
          onPressed: busy || fileIndex >= files.length - 1
              ? null
              : () => selectFile(files[fileIndex + 1].id),
        ),
        const SizedBox(width: 4),
      ],
      IconButtonS('plus', '添加附件', onPressed: busy ? null : addAttachments),
    ],
  );

  Widget _fileCount(Palette p, int count) => Tooltip(
    message: '1 张发票原件 · ${count - 1} 个附件，共 $count 个文件',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: p.card.withValues(alpha: p.dark ? .28 : .50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      child: Text(
        '共 $count 个',
        style: textStyle(p, size: 10.5, color: p.muted),
      ),
    ),
  );

  Widget _previewCard(Palette p, InvoiceFile file, {required double height}) =>
      Tooltip(
        message: files.length > 1
            ? '滚轮切换文件 · 点击在${Platform.isWindows ? '系统应用中' : '速览中'}打开'
            : '点击在${Platform.isWindows ? '系统应用中' : '速览中'}预览',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: busy ? null : () => openPreview(file),
            child: Listener(
              onPointerSignal: wheelFiles,
              child: Container(
                key: const ValueKey('invoice-file-preview'),
                height: height,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: p.card.withValues(alpha: p.dark ? .28 : .38),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: _FilePreview(
                    key: ValueKey('invoice-preview-${file.id}'),
                    file: file,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _previewActions(Palette p, InvoiceFile file) => Row(
    children: [
      IconButtonS(
        'preview',
        Platform.isWindows ? '在系统应用中打开' : '在速览中打开',
        onPressed: busy ? null : () => openPreview(file),
      ),
      const SizedBox(width: 8),
      IconButtonS(
        'save',
        attachmentSelected ? '下载附件' : '下载原件',
        onPressed: busy ? null : () => download(file),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          files.length > 1
              ? '${fileIndex + 1} / ${files.length} · ${file.name}'
              : file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle(p, size: 11, color: p.muted),
        ),
      ),
      if (attachmentSelected)
        IconButtonS(
          'trash',
          '删除附件',
          danger: true,
          onPressed: busy ? null : () => removeAttachment(file),
        ),
    ],
  );

  /// 字段标签统一放在控件上方。
  Widget _field(Palette p, String label, Widget child, {String? note}) =>
      Column(
        key: ValueKey('invoice-field-$label'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle(p, size: 11, color: p.muted),
                ),
              ),
              if (note != null) ...[
                const SizedBox(width: 4),
                Text(note, style: textStyle(p, size: 10, color: p.muted)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      );

  /// 一行两个字段，窄窗口由调用方改为逐行排列。
  Widget _fieldRow(List<Widget> fields) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < fields.length; i++) ...[
        if (i > 0) const SizedBox(width: 12),
        Expanded(child: fields[i]),
      ],
    ],
  );

  Widget _heading(Palette p, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: textStyle(p, size: 11, bold: true, color: p.muted),
    ),
  );

  Widget _amountCell(
    Palette p,
    String label,
    String value, {
    bool strong = false,
  }) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: textStyle(p, size: 11, color: p.muted)),
        const SizedBox(height: 2),
        Text(
          value.isEmpty ? '—' : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle(
            p,
            size: strong ? 15 : 13,
            bold: strong,
            color: value.isEmpty ? p.muted : (strong ? p.text : p.secondary),
          ),
        ),
      ],
    ),
  );

  Widget _amounts(Palette p) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
    decoration: BoxDecoration(
      color: p.card.withValues(alpha: p.dark ? .30 : .42),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: p.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('金额', style: textStyle(p, size: 11, color: p.muted)),
        const SizedBox(height: 6),
        Row(
          children: [
            _amountCell(p, '总金额', value('金额'), strong: true),
            const SizedBox(width: 12),
            _amountCell(p, '税额', value('税额')),
            const SizedBox(width: 12),
            _amountCell(p, '未税金额', value('未税金额')),
          ],
        ),
      ],
    ),
  );

  Widget _formPane(Palette p, {required bool twoColumns}) {
    Widget field(String label, Widget child, {String? note}) =>
        _field(p, label, child, note: note);
    Widget row(List<Widget> cells) => twoColumns
        ? _fieldRow(cells)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cells[i],
              ],
            ],
          );
    Widget gap(double height) => SizedBox(height: height);

    Widget projectField() => Row(
      children: [
        Expanded(
          child: SpaceSelect(
            value: project,
            label: '选择报销项目',
            options: projectChoices(widget.store.state, selected: project),
            onChanged: (v) => setState(() {
              project = v;
              dirty = true;
            }),
          ),
        ),
        const SizedBox(width: 8),
        IconButtonS(
          'project',
          '管理共用项目',
          size: spaceFormControlHeight,
          onPressed: busy
              ? null
              : () => act(() async {
                  await openProjectEditor(context, widget.store);
                  if (!mounted) return;
                  await reload();
                  if (!session.projects.containsKey(project)) {
                    project = '';
                  }
                }),
        ),
      ],
    );

    /// 标记已报销只用圆形复选框与文字标签，不加输入框式底色描边；
    /// 项目选择框高 40，紧凑勾选控件高 32；同高区域内居中，避免中线偏上。
    Widget reimbursedField() => SizedBox(
      height: spaceFormControlHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SpaceCheckbox(
          key: const ValueKey('invoice-reimbursed-control'),
          label: '已报销',
          value: reimbursed,
          dense: true,
          onPressed: busy
              ? null
              : () => setState(() {
                  reimbursed = !reimbursed;
                  dirty = true;
                }),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(p, '票面信息'),
        // 2026-11-12 本轮调整：票面信息恢复两列排布，保留 2.3.2 新增的
        // 「发票名称」与「更多票面字段」折叠区；row() 在窄窗口自动逐行排列。
        row([field('发票名称', input('发票名称')), field('发票号码', input('票号'))]),
        gap(12),
        row([field('销售方名称', input('销售方')), field('开票日期', input('开票日期'))]),
        // 透明 Material 给 ListTile 提供直接祖先，避免被外层带底色的
        // DecoratedBox 遮住展开时的水波纹反馈（Debug 断言）。
        Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              '更多票面字段',
              style: textStyle(p, size: 12, color: p.muted),
            ),
            children: [
              row([
                field('销售方社会信用代码', input('销售方税号')),
                field('购买方', input('购买方')),
              ]),
              gap(12),
              // 奇数个字段：宽窗口只占左半列，右列留空保持两列节奏。
              twoColumns
                  ? row([
                      field('购买方社会信用代码', input('购买方税号')),
                      const SizedBox.shrink(),
                    ])
                  : field('购买方社会信用代码', input('购买方税号')),
            ],
          ),
        ),
        gap(12),
        _amounts(p),
        gap(16),
        _heading(p, '报销信息'),
        // 报销月份随消费日期推导，两个日期字段放在报销项目上方。
        row([
          field('报销月份', input('报销月份'), note: monthAuto ? '随消费日期' : null),
          field('消费日期', input('消费日期')),
        ]),
        gap(12),
        // 报销项目与报销月份同为半宽，右侧是标记已报销的复选框。
        row([field('报销项目', projectField()), field('是否报销', reimbursedField())]),
        gap(12),
        // 最后一行是占满整行的个人备注（两行输入）。
        row([field('备注', input('备注'))]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final current = files;
    final file = displayed;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          close();
          return KeyEventResult.handled;
        }
        if (current.length > 1 &&
            (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowRight)) {
          final next =
              fileIndex +
              (event.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : -1);
          if (next >= 0 && next < current.length) {
            selectFile(current[next].id);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (c, box) {
          final twoColumns = box.maxWidth >= 340;
          // 预览高度随窗口自适应；表单单独滚动，滚轮落在预览区只切换文件。
          final wanted = math.min(268.0, math.max(180.0, box.maxHeight * .38));
          final previewHeight = (wanted / 4).round() * 4.0;
          return sheetFrame(
            context,
            title: '发票详情',
            titleActions: [
              IconButtonS.toolbar(
                'scan',
                '识别 / 重新识别',
                onPressed: busy ? null : recognize,
              ),
            ],
            close: close,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _fileHeader(p, current),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _previewCard(p, file, height: previewHeight),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _previewActions(p, file),
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: p.border),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    child: _formPane(p, twoColumns: twoColumns),
                  ),
                ),
              ],
            ),
            footer: [
              IconButtonS(
                'trash',
                '删除发票',
                danger: true,
                onPressed: busy ? null : remove,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: error ?? notice ?? '',
                  child: Text(
                    busy ? '正在处理…' : error ?? notice ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(
                      p,
                      size: 12,
                      color: error == null ? p.muted : p.red,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SpaceTextButton('取消', onPressed: busy ? null : close),
              const SizedBox(width: 8),
              SpaceTextButton(
                '保存更改',
                primary: true,
                onPressed: busy || !dirty ? null : save,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget input(String key) => key == '备注'
      ? TextField(
          controller: inputs[key],
          minLines: 2,
          maxLines: 2,
          style: textStyle(Palette.of(context), size: 12),
          decoration: InputDecoration(
            hintText: '填写自己的备注',
            filled: true,
            fillColor: Palette.of(context).hover,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (_) {
            if (!dirty) setState(() => dirty = true);
          },
        )
      : SpaceInput(
          controller: inputs[key]!,
          label: key,
          height: 32,
          fontSize: 12,
          hint: key.endsWith('日期') || key.endsWith('时间')
              ? 'YYYY-MM-DD'
              : key.endsWith('月份')
              ? 'YYYY-MM'
              : '',
          onChanged: (v) {
            if (key == '消费日期' && monthAuto && v.length >= 7) {
              inputs['报销月份']!.text = v.substring(0, 7);
            }
            if (key == '报销月份') monthAuto = false;
            if (!dirty) setState(() => dirty = true);
          },
        );
}

class _FilePreview extends StatefulWidget {
  final InvoiceFile file;
  const _FilePreview({super.key, required this.file});

  @override
  State<_FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<_FilePreview> {
  int page = 1;
  // Decode from memory so Windows can delete or replace the previewed file.
  late final imageBytes = File(widget.file.path).readAsBytes();
  late Future<InvoicePreview> preview = InvoicePdf.preview(
    widget.file.path,
    page,
  );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (!widget.file.isPdf) {
      return FutureBuilder(
        future: imageBytes,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) {
            return const Center(child: Text('正在加载图片…'));
          }
          if (!state.hasData) return const Center(child: Text('无法打开图片'));
          return SizedBox.expand(
            child: Image.memory(
              state.data!,
              cacheWidth: 900,
              fit: BoxFit.contain,
              errorBuilder: (_, error, stack) =>
                  const Center(child: Text('无法打开图片')),
            ),
          );
        },
      );
    }
    return FutureBuilder<InvoicePreview>(
      future: preview,
      builder: (context, state) {
        final result = state.data;
        return Column(
          children: [
            Expanded(
              child: state.connectionState != ConnectionState.done
                  ? const Center(child: CircularProgressIndicator())
                  : result == null
                  ? Center(
                      child: Text(
                        invoiceError(state.error ?? StateError('无法预览文件')),
                      ),
                    )
                  : Image.memory(result.bytes, fit: BoxFit.contain),
            ),
            if (result != null && result.pages > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButtonS(
                    'left',
                    '上一页',
                    size: 28,
                    onPressed: page > 1 ? () => turn(-1) : null,
                  ),
                  Text(
                    '$page / ${result.pages}',
                    style: textStyle(p, size: 12),
                  ),
                  IconButtonS(
                    'right',
                    '下一页',
                    size: 28,
                    onPressed: page < result.pages ? () => turn(1) : null,
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  void turn(int delta) => setState(() {
    page += delta;
    preview = InvoicePdf.preview(widget.file.path, page);
  });
}

Future<void> showInvoiceExport(
  BuildContext context,
  SpaceStore store,
  InvoiceSession session,
  List<InvoiceEntry> filtered,
  List<InvoiceEntry> selected,
) async {
  final plan = await invoiceModal(
    store,
    () => sheet<({List<InvoiceColumn> columns, bool selected})>(
      context,
      _ExportOptions(filtered.length, selected.length),
      width: 450,
      height: 396,
    ),
  );
  if (plan == null || !context.mounted) return;
  await session.run(() async {
    final path = await DesktopHost.saveFile('发票台账.xlsx', title: '导出发票台账');
    if (path == null) return null;
    final rows = plan.selected ? selected : filtered;
    await exportInvoiceSheet(
      session.repo,
      path,
      rows,
      session.projects,
      plan.columns,
    );
    return '已导出 ${rows.length} 张发票';
  }, reload: false);
}

class _ExportOptions extends StatefulWidget {
  final int filteredCount, selectedCount;
  const _ExportOptions(this.filteredCount, this.selectedCount);
  @override
  State<_ExportOptions> createState() => _ExportOptionsState();
}

class _ExportOptionsState extends State<_ExportOptions> {
  final columns = InvoiceColumn.values.toSet();
  late bool selected = widget.selectedCount > 0;

  @override
  Widget build(BuildContext context) => sheetFrame(
    context,
    title: '按字段导出台账',
    close: () => Navigator.pop(context),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SpaceSelect(
          value: selected ? 'selected' : 'filtered',
          label: '导出范围',
          options: {
            'filtered': '当前筛选结果（${widget.filteredCount} 张）',
            if (widget.selectedCount > 0)
              'selected': '已勾选（${widget.selectedCount} 张）',
          },
          onChanged: (v) => setState(() => selected = v == 'selected'),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 8,
            children: [
              for (final c in InvoiceColumn.values)
                SizedBox(
                  width: box.maxWidth < 320
                      ? box.maxWidth
                      : (box.maxWidth - 8) / 2,
                  child: SpaceCheckbox(
                    label: c.title,
                    value: columns.contains(c),
                    onPressed: () => setState(() {
                      if (!columns.remove(c)) columns.add(c);
                    }),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
    footer: [
      const Spacer(),
      IconButtonS(
        'save',
        '导出 Excel',
        primary: true,
        onPressed: columns.isEmpty
            ? null
            : () => Navigator.pop(context, (
                columns: InvoiceColumn.values.where(columns.contains).toList(),
                selected: selected,
              )),
      ),
    ],
  );
}
