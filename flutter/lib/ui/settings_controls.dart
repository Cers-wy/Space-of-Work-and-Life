import 'package:flutter/material.dart';

import 'theme.dart';

class SettingsIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  const SettingsIcon(this.name, {super.key, this.size = 18, this.color});
  static const glyphs = <String, IconData>{
    'all': IconData(0xe464, fontFamily: 'PhosphorSettings'),
    'appearance': IconData(0xe434, fontFamily: 'PhosphorSettings'),
    'backup': IconData(0xe1a0, fontFamily: 'PhosphorSettings'),
    'cloud': IconData(0xe1ae, fontFamily: 'PhosphorSettings'),
    'data': IconData(0xe1de, fontFamily: 'PhosphorSettings'),
    'info': IconData(0xe2ce, fontFamily: 'PhosphorSettings'),
    'sun': IconData(0xe472, fontFamily: 'PhosphorSettings'),
    'moon': IconData(0xe330, fontFamily: 'PhosphorSettings'),
    'system': IconData(0xe560, fontFamily: 'PhosphorSettings'),
    'close': IconData(0xe4f6, fontFamily: 'PhosphorSettings'),
    'right': IconData(0xe13a, fontFamily: 'PhosphorSettings'),
    'folder': IconData(0xe256, fontFamily: 'PhosphorSettings'),
    'up': IconData(0xe4c0, fontFamily: 'PhosphorSettings'),
    'down': IconData(0xe20c, fontFamily: 'PhosphorSettings'),
    'eye': IconData(0xe220, fontFamily: 'PhosphorSettings'),
    'eye-off': IconData(0xe224, fontFamily: 'PhosphorSettings'),
    'refresh': IconData(0xe036, fontFamily: 'PhosphorSettings'),
    'external': IconData(0xe092, fontFamily: 'PhosphorSettings'),
    'trash': IconData(0xe4a6, fontFamily: 'PhosphorSettings'),
  };
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Icon(
      glyphs[name] ?? glyphs['info'],
      size: size,
      color: color ?? Palette.of(context).secondary,
    ),
  );
}

class SettingsAction extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool quiet, selected, navigation, danger;
  final double height;
  final EdgeInsetsGeometry padding;
  const SettingsAction({
    super.key,
    required this.child,
    required this.onPressed,
    this.tooltip,
    this.quiet = false,
    this.selected = false,
    this.navigation = false,
    this.danger = false,
    this.height = 32,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
  });
  @override
  State<SettingsAction> createState() => _SettingsActionState();
}

class _SettingsActionState extends State<SettingsAction> {
  bool hover = false, focus = false, pressed = false;
  final buttonFocus = FocusNode();
  @override
  void dispose() {
    buttonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget, p = Palette.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final selection = p.selectedButtonBackground(
      Colors.white.withValues(alpha: .075),
    );
    final surface = w.selected
        ? selection
        : hover
        ? p.hover
        : w.quiet
        ? Colors.transparent
        : p.blend(Colors.white, const Color(0xff272727));
    final outline = p.blend(const Color(0xffc4ccd7), const Color(0xff454545));
    Widget button = FocusableActionDetector(
      focusNode: buttonFocus,
      includeFocusSemantics: false,
      onFocusChange: (_) => setState(() {}),
      enabled: w.onPressed != null,
      mouseCursor: w.onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onShowFocusHighlight: (v) => setState(() => focus = v),
      onShowHoverHighlight: (v) => setState(() => hover = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            w.onPressed?.call();
            return null;
          },
        ),
      },
      child: Semantics(
        container: true,
        focusable: w.onPressed != null,
        focused: buttonFocus.hasFocus,
        onFocus: buttonFocus.requestFocus,
        label: w.tooltip,
        onTap: w.onPressed,
        button: true,
        enabled: w.onPressed != null,
        selected: w.navigation ? w.selected : null,
        child: GestureDetector(
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTap: w.onPressed,
          onTapDown: w.onPressed == null
              ? null
              : (_) => setState(() => pressed = true),
          onTapUp: (_) => setState(() => pressed = false),
          onTapCancel: () => setState(() => pressed = false),
          child: AnimatedScale(
            scale: pressed && !w.navigation ? .98 : 1,
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: spaceCurve,
            child: Opacity(
              opacity: w.onPressed == null ? .4 : 1,
              child: Container(
                height: w.height,
                padding: w.padding,
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(6),
                  border: focus
                      ? Border.all(
                          color: w.selected
                              ? p.selectedButtonForeground()
                              : p.accent,
                          width: 2,
                        )
                      : w.quiet
                      ? null
                      : Border.all(color: outline),
                ),
                child: DefaultTextStyle(
                  style: textStyle(
                    p,
                    color: w.selected
                        ? p.selectedButtonForeground(p.secondary)
                        : w.danger
                        ? p.red
                        : w.navigation || w.quiet
                        ? p.secondary
                        : p.text,
                  ),
                  child: Center(widthFactor: 1, child: w.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (w.tooltip != null)
      button = Tooltip(
        message: w.tooltip!,
        excludeFromSemantics: true,
        child: button,
      );
    return button;
  }
}
