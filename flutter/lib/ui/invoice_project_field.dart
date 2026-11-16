import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../store.dart';
import 'controls.dart';
import 'theme.dart';

/// Same select-or-create semantics as the task editor: a new name is committed
/// only when the invoice is saved, so cancelling never creates an empty project.
class InvoiceProjectField extends StatefulWidget {
  final SpaceStore store;
  final String name;
  final ValueChanged<String> onChanged;
  const InvoiceProjectField({
    super.key,
    required this.store,
    required this.name,
    required this.onChanged,
  });
  @override
  State<InvoiceProjectField> createState() => _InvoiceProjectFieldState();
}

class _InvoiceProjectFieldState extends State<InvoiceProjectField> {
  late final controller = TextEditingController(text: widget.name);
  final focus = FocusNode();
  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (c, box) => RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focus,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        final projects = widget.store.state.projects
            .where((p) => !p.disabled)
            .map((p) => p.name)
            .toList();
        return [
          for (final name
              in projects.where((n) => n.toLowerCase().contains(query)).take(6))
            name,
          if (query.isNotEmpty &&
              !widget.store.state.projects.any(
                (p) => p.name.toLowerCase() == query,
              ))
            '+ 新建项目：${value.text.trim()}',
        ];
      },
      onSelected: (selected) {
        final name = selected.startsWith('+ 新建项目：')
            ? selected.substring(7)
            : selected;
        controller.text = name;
        widget.onChanged(name);
        focus.unfocus();
      },
      fieldViewBuilder: (c, text, node, submit) => CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.enter): submit},
        child: SpaceInput(
          controller: text,
          focusNode: node,
          hint: '搜索或输入新项目',
          label: '报销项目',
          onChanged: widget.onChanged,
        ),
      ),
      optionsViewBuilder: (c, select, options) => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: box.maxWidth,
          child: PopupSurface(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final option in options)
                  SpaceButton(
                    height: 40,
                    onPressed: () => select(option),
                    child: Text(
                      option,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
