import 'package:flutter/material.dart';

import '../core/invoices.dart';
import '../store.dart';
import 'controls.dart';
import 'dialogs.dart';
import 'invoice_details.dart' show invoiceModal;
import 'invoice_workspace.dart' show InvoiceSession;
import 'theme.dart';

Future<void> showInvoiceBatchUpdate(
  BuildContext context,
  SpaceStore store,
  InvoiceSession session,
  List<String> ids,
) async {
  final selected = ids.toSet().toList(growable: false);
  if (selected.isEmpty || session.busy) return;
  await invoiceModal(
    store,
    () => sheet<void>(
      context,
      _InvoiceBatchUpdate(store: store, session: session, ids: selected),
      width: 560,
      height: 420,
    ),
  );
}

class _InvoiceBatchUpdate extends StatefulWidget {
  final SpaceStore store;
  final InvoiceSession session;
  final List<String> ids;
  const _InvoiceBatchUpdate({
    required this.store,
    required this.session,
    required this.ids,
  });
  @override
  State<_InvoiceBatchUpdate> createState() => _InvoiceBatchUpdateState();
}

class _InvoiceBatchUpdateState extends State<_InvoiceBatchUpdate> {
  final month = TextEditingController(), purpose = TextEditingController();
  String project = '';
  String? error;
  bool saving = false;
  InvoiceReimbursementPatch get patch => InvoiceReimbursementPatch(
    month: month.text,
    project: project,
    purpose: purpose.text,
  );
  @override
  void dispose() {
    month.dispose();
    purpose.dispose();
    super.dispose();
  }

  void close() {
    if (!saving) Navigator.of(context).pop();
  }

  void changed() => setState(() => error = null);
  Future<void> save() async {
    if (saving || patch.values.isEmpty) return;
    setState(() {
      saving = true;
      error = null;
    });
    final result = await widget.session.updateReimbursement(widget.ids, patch);
    if (!mounted) return;
    if (result) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        saving = false;
        error = widget.session.error ?? '当前操作尚未完成，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fields = [
      field(
        context,
        '报销月份',
        SpaceInput(
          key: const ValueKey('invoice-batch-month'),
          controller: month,
          label: '批量设置报销月份',
          hint: 'YYYY-MM，留空不更新',
          autofocus: true,
          onChanged: (_) => changed(),
        ),
      ),
      field(
        context,
        '报销项目',
        SpaceSelect(
          key: const ValueKey('invoice-batch-project'),
          value: project,
          label: '批量设置报销项目',
          options: {
            '': '不更新',
            for (final entry in projectChoices(widget.store.state).entries)
              if (entry.key.isNotEmpty) entry.key: entry.value,
          },
          onChanged: (value) => setState(() {
            project = value;
            error = null;
          }),
        ),
      ),
    ];
    return PopScope(
      canPop: !saving,
      child: sheetFrame(
        context,
        title: '批量更新发票',
        close: close,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '已选择 ${widget.ids.length} 张发票，留空的字段保持原值。',
                style: textStyle(p, size: 12, color: p.muted),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (_, box) => box.maxWidth < 380
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          fields[0],
                          const SizedBox(height: 16),
                          fields[1],
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: fields[0]),
                          const SizedBox(width: 16),
                          Expanded(child: fields[1]),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              field(
                context,
                '备注',
                SpaceInput(
                  key: const ValueKey('invoice-batch-purpose'),
                  controller: purpose,
                  label: '批量设置备注',
                  hint: '留空不更新',
                  lines: 2,
                  onChanged: (_) => changed(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: textStyle(p, size: 12, color: p.red)),
              ],
            ],
          ),
        ),
        footer: [
          const Spacer(),
          SpaceButton.form('取消', onPressed: saving ? null : close),
          const SizedBox(width: 8),
          SpaceButton.form(
            saving ? '更新中…' : '更新',
            key: const ValueKey('invoice-batch-submit'),
            primary: true,
            onPressed: saving || patch.values.isEmpty ? null : save,
          ),
        ],
      ),
    );
  }
}
