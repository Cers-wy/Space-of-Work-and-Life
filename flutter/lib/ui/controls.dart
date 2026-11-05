import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import '../core/models.dart';
import 'theme.dart';

class SpaceIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  const SpaceIcon(this.name, {super.key, this.size = 14, this.color});
  @override
  Widget build(BuildContext c) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _IconPainter(name, color ?? Palette.of(c).secondary),
    ),
  );
}

class _IconPainter extends CustomPainter {
  final String name;
  final Color color;
  _IconPainter(this.name, this.color);
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 20, s.height / 20);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x, double y, double x2, double y2) =>
        c.drawLine(Offset(x, y), Offset(x2, y2), p);
    void rect(double x, double y, double w, double h, [double r = 1.5]) =>
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h),
            Radius.circular(r),
          ),
          p,
        );
    void path(List<Offset> points) {
      final a = Path()..moveTo(points.first.dx, points.first.dy);
      for (final pt in points.skip(1)) {
        a.lineTo(pt.dx, pt.dy);
      }
      c.drawPath(a, p);
    }

    switch (name) {
      case 'plus':
        line(10, 3, 10, 17);
        line(3, 10, 17, 10);
      case 'x':
        line(5, 5, 15, 15);
        line(15, 5, 5, 15);
      case 'left':
        path(const [Offset(12, 4), Offset(6, 10), Offset(12, 16)]);
      case 'right':
        path(const [Offset(8, 4), Offset(14, 10), Offset(8, 16)]);
      case 'down':
        path(const [Offset(4, 7), Offset(10, 13), Offset(16, 7)]);
      case 'up':
        path(const [Offset(4, 13), Offset(10, 7), Offset(16, 13)]);
      case 'expand-all':
        p.strokeWidth = 1.5;
        path(const [Offset(5, 5), Offset(10, 10), Offset(15, 5)]);
        path(const [Offset(5, 11), Offset(10, 16), Offset(15, 11)]);
      case 'collapse-all':
        p.strokeWidth = 1.5;
        path(const [Offset(5, 9), Offset(10, 4), Offset(15, 9)]);
        path(const [Offset(5, 15), Offset(10, 10), Offset(15, 15)]);
      case 'check':
        path(const [Offset(4, 10), Offset(8, 14), Offset(16, 5)]);
      case 'circle':
        c.drawCircle(const Offset(10, 10), 9.5, p..strokeWidth = .65);
      case 'done':
        c.drawCircle(const Offset(10, 10), 9.5, p..style = PaintingStyle.fill);
        c.drawPath(
          Path()
            ..moveTo(5.5, 10)
            ..lineTo(9, 13)
            ..lineTo(14.5, 6),
          Paint()
            ..color = const Color(0xff174938)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.round,
        );
      case 'board':
        rect(1, 3, 18, 14);
        line(7, 3, 7, 17);
        line(13, 3, 13, 17);
      case 'grid':
        for (final x in [3.0, 11.0]) {
          for (final y in [3.0, 11.0]) {
            rect(x, y, 6, 6, 1);
          }
        }
      case 'list':
        for (final y in [4.0, 10.0, 16.0]) {
          c.drawCircle(Offset(2, y), .8, p..style = PaintingStyle.fill);
          p.style = PaintingStyle.stroke;
          line(6, y, 18, y);
        }
      case 'gantt':
        p.strokeWidth = 2.1;
        line(3, 4.5, 11, 4.5);
        line(8, 10, 17, 10);
        line(5, 15.5, 12, 15.5);
      case 'calendar':
        rect(2, 4, 16, 14, 2);
        line(2, 8, 18, 8);
        line(6, 2, 6, 6);
        line(14, 2, 14, 6);
        for (final y in [11.0, 14.0]) {
          for (final x in [6.0, 10.0, 14.0]) {
            c.drawCircle(Offset(x, y), .55, p..style = PaintingStyle.fill);
          }
        }
      case 'search':
        c.drawCircle(const Offset(8.5, 8.5), 5.5, p);
        line(12.5, 12.5, 17.5, 17.5);
      case 'filter':
        line(2, 4, 18, 4);
        line(4, 10, 16, 10);
        line(7, 16, 13, 16);
      case 'menu':
        for (final y in [6.0, 10.0, 14.0]) {
          line(2, y, 18, y);
        }
      case 'dots':
        for (final x in [4.0, 10.0, 16.0]) {
          c.drawCircle(Offset(x, 10), 1.3, p..style = PaintingStyle.fill);
        }
      case 'edit':
        path(const [
          Offset(4, 13),
          Offset(13, 4),
          Offset(16, 7),
          Offset(7, 16),
          Offset(3, 17),
          Offset(4, 13),
        ]);
        line(11, 6, 14, 9);
      case 'folder':
        c.drawPath(
          Path()
            ..moveTo(2, 6)
            ..lineTo(2, 16)
            ..quadraticBezierTo(2, 18, 4, 18)
            ..lineTo(17, 18)
            ..quadraticBezierTo(19, 18, 19, 16)
            ..lineTo(19, 7)
            ..quadraticBezierTo(19, 5, 17, 5)
            ..lineTo(10, 5)
            ..lineTo(8, 2)
            ..lineTo(4, 2)
            ..quadraticBezierTo(2, 2, 2, 4)
            ..close(),
          p,
        );
      case 'flag':
        line(4, 18, 4, 2);
        c.drawPath(
          Path()
            ..moveTo(4, 3)
            ..cubicTo(8, 0, 12, 6, 17, 3)
            ..lineTo(17, 12)
            ..cubicTo(12, 15, 8, 9, 4, 12),
          p,
        );
      case 'help':
        c.drawCircle(const Offset(10, 10), 8, p);
        c.drawPath(
          Path()
            ..moveTo(7.2, 7)
            ..cubicTo(7.2, 3.5, 14, 3.5, 12.5, 8)
            ..cubicTo(12, 9.5, 10, 9.5, 10, 12),
          p,
        );
        c.drawCircle(const Offset(10, 15), .7, p..style = PaintingStyle.fill);
      case 'sun':
        c.drawCircle(const Offset(10, 10), 4, p);
        p.style = PaintingStyle.stroke;
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          line(
            10 + math.cos(a) * 6.5,
            10 + math.sin(a) * 6.5,
            10 + math.cos(a) * 8.5,
            10 + math.sin(a) * 8.5,
          );
        }
      case 'moon':
        c.drawPath(
          Path()
            ..moveTo(15.5, 15.5)
            ..cubicTo(4, 20, -1, 7, 8, 2)
            ..cubicTo(4, 12, 12, 15, 17, 12)
            ..quadraticBezierTo(17, 14, 15.5, 15.5)
            ..close(),
          p..style = PaintingStyle.fill,
        );
      case 'undo':
        path(const [Offset(7, 3), Offset(2, 8), Offset(7, 12)]);
        c.drawPath(
          Path()
            ..moveTo(2, 8)
            ..lineTo(12, 8)
            ..cubicTo(20, 8, 20, 18, 12, 18),
          p,
        );
      case 'project':
        c.drawPath(
          Path()
            ..moveTo(2.5, 7)
            ..lineTo(2.5, 5)
            ..quadraticBezierTo(2.5, 3, 4.5, 3)
            ..lineTo(8, 3)
            ..lineTo(10.5, 5.5)
            ..lineTo(16, 5.5)
            ..quadraticBezierTo(18, 5.5, 18, 7.5)
            ..lineTo(18, 16)
            ..quadraticBezierTo(18, 18, 16, 18)
            ..lineTo(4.5, 18)
            ..quadraticBezierTo(2.5, 18, 2.5, 16)
            ..close(),
          p,
        );
        line(7, 9.5, 14, 9.5);
        line(7, 13, 11.5, 13);
      case 'status':
        for (final y in [4.0, 10.0, 16.0]) {
          c.drawCircle(Offset(4, y), 1.7, p);
        }
        line(9, 4, 18, 4);
        line(9, 10, 15.5, 10);
        line(9, 16, 18, 16);
      case 'sidebar-open':
      case 'sidebar-close':
        rect(2.5, 3.5, 15, 13, 2.5);
        line(7.5, 3.5, 7.5, 16.5);
        path(
          name == 'sidebar-open'
              ? const [Offset(11, 7), Offset(14, 10), Offset(11, 13)]
              : const [Offset(14, 7), Offset(11, 10), Offset(14, 13)],
        );
      case 'gear':
        final path = Path();
        for (var i = 0; i < 32; i++) {
          final a = i * math.pi / 16;
          final radius = i % 4 == 0 || i % 4 == 3 ? 8.7 : 7;
          final pt = Offset(
            10 + math.cos(a) * radius,
            10 + math.sin(a) * radius,
          );
          if (i == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        path.close();
        c.drawPath(path, p);
        c.drawCircle(const Offset(10, 10), 3, p);
      case 'clip':
        c.drawPath(
          Path()
            ..moveTo(6, 12)
            ..lineTo(12, 6)
            ..cubicTo(15, 3, 18, 6, 15, 9)
            ..lineTo(8, 16)
            ..cubicTo(3, 21, -1, 15, 4, 10)
            ..lineTo(11, 3),
          p,
        );
      case 'save':
        path(const [Offset(10, 2), Offset(10, 13), Offset(6, 9)]);
        line(10, 13, 14, 9);
        path(const [
          Offset(3, 11),
          Offset(3, 18),
          Offset(17, 18),
          Offset(17, 11),
        ]);
      case 'trash':
        line(3, 5, 17, 5);
        line(7, 2, 13, 2);
        path(const [
          Offset(5, 5),
          Offset(6, 18),
          Offset(14, 18),
          Offset(15, 5),
        ]);
        line(9, 8, 9, 15);
        line(12, 8, 12, 15);
      case 'file':
        path(const [
          Offset(4, 2),
          Offset(12, 2),
          Offset(17, 7),
          Offset(17, 18),
          Offset(4, 18),
          Offset(4, 2),
        ]);
        path(const [Offset(12, 2), Offset(12, 7), Offset(17, 7)]);
      case 'tray':
        path(const [
          Offset(2, 12),
          Offset(6, 5),
          Offset(14, 5),
          Offset(18, 12),
          Offset(18, 18),
          Offset(2, 18),
          Offset(2, 12),
          Offset(7, 12),
          Offset(8, 15),
          Offset(12, 15),
          Offset(13, 12),
          Offset(18, 12),
        ]);
      case 'mark':
        c.drawPath(
          Path()
            ..moveTo(13.5, 5.5)
            ..lineTo(8.5, 5.5)
            ..cubicTo(4, 5.5, 4, 10, 8.5, 10)
            ..lineTo(11.5, 10)
            ..cubicTo(16, 10, 16, 14.5, 11.5, 14.5)
            ..lineTo(6.5, 14.5),
          p..strokeWidth = 1.7,
        );
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(14.2, 3.6, 2, 2),
            const Radius.circular(.5),
          ),
          Paint()..color = const Color(0xffb8d2ff),
        );
      default:
        rect(3, 3, 14, 14);
    }
  }

  @override
  bool shouldRepaint(_IconPainter o) => o.name != name || o.color != color;
}

class SpaceButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool primary, selected, danger;
  final double height;
  final EdgeInsetsGeometry padding;
  const SpaceButton({
    super.key,
    required this.child,
    this.onPressed,
    this.tooltip,
    this.primary = false,
    this.selected = false,
    this.danger = false,
    this.height = 40,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
  });
  @override
  State<SpaceButton> createState() => _SpaceButtonState();
}

class _SpaceButtonState extends State<SpaceButton> {
  bool hover = false, focus = false, pressed = false;
  @override
  Widget build(BuildContext context) {
    final w = widget, p = Palette.of(context);
    final color = w.primary
        ? Colors.white
        : w.danger
        ? p.red
        : w.selected
        ? p.accent
        : p.secondary;
    Widget result = FocusableActionDetector(
      enabled: w.onPressed != null,
      onShowFocusHighlight: (v) => setState(() => focus = v),
      onShowHoverHighlight: (v) => setState(() => hover = v),
      mouseCursor: w.onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            w.onPressed?.call();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        label: w.tooltip,
        enabled: w.onPressed != null,
        selected: w.selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: w.onPressed,
          onTapDown: (_) => setState(() => pressed = true),
          onTapUp: (_) => setState(() => pressed = false),
          onTapCancel: () => setState(() => pressed = false),
          child: Opacity(
            opacity: w.onPressed == null
                ? 0.4
                : pressed
                ? 0.8
                : 1,
            child: Container(
              height: w.height,
              padding: w.padding,
              decoration: BoxDecoration(
                color: w.primary
                    ? p.primary
                    : w.selected || hover
                    ? p.hover
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: focus ? Border.all(color: p.accent, width: 2) : null,
              ),
              child: DefaultTextStyle(
                style: textStyle(p, bold: true, color: color),
                child: IconTheme(
                  data: IconThemeData(color: color, size: 14),
                  child: Center(widthFactor: 1, child: w.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (w.tooltip != null) result = Tooltip(message: w.tooltip!, child: result);
    return result;
  }
}

class IconButtonS extends StatelessWidget {
  final String icon, label;
  final VoidCallback? onPressed;
  final bool primary, selected;
  final double size, iconSize;
  const IconButtonS(
    this.icon,
    this.label, {
    super.key,
    this.onPressed,
    this.primary = false,
    this.selected = false,
    this.size = 36,
    this.iconSize = 14,
  });
  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    return SizedBox(
      width: size,
      height: size,
      child: SpaceButton(
        tooltip: label,
        onPressed: onPressed,
        primary: primary,
        selected: selected,
        height: size,
        padding: EdgeInsets.zero,
        child: SpaceIcon(
          icon,
          size: iconSize,
          color: onPressed == null
              ? p.muted.withValues(alpha: .35)
              : primary
              ? Colors.white
              : selected
              ? p.accent
              : icon == 'done'
              ? p.green
              : icon == 'circle'
              ? p.muted.withValues(alpha: .65)
              : p.secondary,
        ),
      ),
    );
  }
}

class Mark extends StatelessWidget {
  final double size;
  const Mark({super.key, this.size = 32});
  @override
  Widget build(BuildContext c) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Palette.of(c).primary,
      borderRadius: BorderRadius.circular(8),
    ),
    child: SpaceIcon('mark', size: size, color: Colors.white),
  );
}

class CategoryLabel extends StatelessWidget {
  final String category;
  final String? name;
  final int? count;
  const CategoryLabel(this.category, {super.key, this.count, this.name});
  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.category(category),
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${name ?? categories[category] ?? category}${count == null ? '' : ' $count'}',
            style: textStyle(p, size: 12, color: p.secondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class ThemeToggle extends StatelessWidget {
  final bool dark;
  final VoidCallback onToggle;
  const ThemeToggle({super.key, required this.dark, required this.onToggle});
  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    return Semantics(
      button: true,
      label: dark ? '切换到明亮主题' : '切换到暗色主题',
      child: Tooltip(
        message: dark ? '切换到明亮主题' : '切换到暗色主题',
        child: GestureDetector(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: p.hover.withValues(alpha: p.dark ? 0.104 : .052),
              borderRadius: BorderRadius.circular(20),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: p.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final v in [false, true])
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dark == v ? p.card : Colors.transparent,
                    ),
                    alignment: Alignment.center,
                    child: SpaceIcon(
                      v ? 'moon' : 'sun',
                      size: 13,
                      color: dark == v ? p.accent : p.secondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SpaceInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint, label;
  final String? icon;
  final bool autofocus, obscure, invalid;
  final double fontSize;
  final int lines;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final Color? borderColor;
  const SpaceInput({
    super.key,
    required this.controller,
    this.hint = '',
    this.label = '',
    this.icon,
    this.autofocus = false,
    this.obscure = false,
    this.invalid = false,
    this.fontSize = 14,
    this.lines = 1,
    this.onChanged,
    this.focusNode,
    this.borderColor,
  });
  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    return SizedBox(
      height: lines == 1 ? 40 : null,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        obscureText: obscure,
        maxLines: lines,
        style: textStyle(p, size: fontSize),
        textAlignVertical: TextAlignVertical.center,
        strutStyle: StrutStyle(fontSize: fontSize, height: 1.4),
        cursorColor: p.accent,
        onChanged: onChanged,
        decoration: InputDecoration(
          isCollapsed: false,
          isDense: lines != 1,
          constraints: lines == 1
              ? const BoxConstraints(minHeight: 40, maxHeight: 40)
              : null,
          hintText: hint,
          prefixIcon: icon == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: Center(
                    widthFactor: 1,
                    child: SpaceIcon(icon!, size: 14, color: p.muted),
                  ),
                ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 40,
          ),
          labelText: null,
          semanticCounterText: label,
          hintStyle: textStyle(p, size: fontSize, color: p.muted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 0,
          ),
          filled: true,
          fillColor: p.card.withValues(alpha: p.dark ? 0.46 : .50),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: invalid ? p.red : borderColor ?? p.border,
              width: invalid ? 2 : 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: invalid ? p.red : p.accent, width: 2),
          ),
        ),
      ),
    );
  }
}

class SpaceSelect extends StatefulWidget {
  final String value, label;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final double? width;
  final bool active;
  const SpaceSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.label,
    this.width,
    this.active = false,
  });
  @override
  State<SpaceSelect> createState() => _SpaceSelectState();
}

class _SpaceSelectState extends State<SpaceSelect> {
  bool expanded = false;
  Future<void> open() async {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    setState(() => expanded = true);
    final value = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭${widget.label}',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (c, a, b) => _Options(
        anchor: origin & box.size,
        options: widget.options,
        value: widget.value,
      ),
    );
    if (!mounted) return;
    setState(() => expanded = false);
    if (value != null) widget.onChanged(value);
  }

  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    return SizedBox(
      width: widget.width,
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.active
              ? p.hover
              : p.card.withValues(alpha: p.dark ? 0.46 : .5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: expanded ? p.accent : p.border,
            width: expanded ? 2 : 1,
          ),
        ),
        child: SpaceButton(
          tooltip: widget.label,
          onPressed: open,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.options[widget.value] ?? widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle(
                    p,
                    size: 12,
                    color: widget.active ? p.accent : p.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SpaceIcon('down', size: 10, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _Options extends StatefulWidget {
  final Rect anchor;
  final Map<String, String> options;
  final String value;
  const _Options({
    required this.anchor,
    required this.options,
    required this.value,
  });
  @override
  State<_Options> createState() => _OptionsState();
}

class _OptionsState extends State<_Options> {
  late int index;
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    index = math.max(0, widget.options.keys.toList().indexOf(widget.value));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.jumpTo((index * 40.0).clamp(0, scroll.position.maxScrollExtent));
      }
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c), screen = MediaQuery.sizeOf(c);
    final h = math.min(widget.options.length * 40.0 + 12, 320.0);
    final top = widget.anchor.bottom + 6 + h > screen.height
        ? math.max(8.0, widget.anchor.top - h - 6)
        : widget.anchor.bottom + 6;
    return Stack(
      children: [
        Positioned(
          left: widget.anchor.left.clamp(
            8,
            math.max(8, screen.width - widget.anchor.width - 8),
          ),
          top: top,
          width: widget.anchor.width,
          height: h,
          child: Material(
            type: MaterialType.transparency,
            child: Focus(
              autofocus: true,
              onKeyEvent: (n, e) {
                if (e is! KeyDownEvent) return KeyEventResult.ignored;
                if (e.logicalKey == LogicalKeyboardKey.escape) {
                  Navigator.pop(c);
                  return KeyEventResult.handled;
                }
                if (e.logicalKey == LogicalKeyboardKey.enter) {
                  Navigator.pop(c, widget.options.keys.elementAt(index));
                  return KeyEventResult.handled;
                }
                final delta = e.logicalKey == LogicalKeyboardKey.arrowDown
                    ? 1
                    : e.logicalKey == LogicalKeyboardKey.arrowUp
                    ? -1
                    : 0;
                if (delta == 0) return KeyEventResult.ignored;
                setState(
                  () => index = (index + delta).clamp(
                    0,
                    widget.options.length - 1,
                  ),
                );
                scroll.animateTo(
                  (index * 40.0).clamp(0, scroll.position.maxScrollExtent),
                  duration: const Duration(milliseconds: 80),
                  curve: Curves.easeOut,
                );
                return KeyEventResult.handled;
              },
              child: PopupSurface(
                child: ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.all(8),
                  itemCount: widget.options.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 4),
                  itemBuilder: (c, i) {
                    final key = widget.options.keys.elementAt(i);
                    return MouseRegion(
                      onEnter: (_) => setState(() => index = i),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: index == i ? p.hover : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SpaceButton(
                          height: 36,
                          onPressed: () => Navigator.pop(c, key),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                child: key == widget.value
                                    ? SpaceIcon(
                                        'check',
                                        size: 11,
                                        color: p.accent,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.options[key]!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textStyle(
                                    p,
                                    size: 12,
                                    color: key == widget.value
                                        ? p.accent
                                        : p.text,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DateField extends StatelessWidget {
  final String value, label;
  final ValueChanged<String> onChanged;
  final bool allowsClear;
  const DateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = '截止日期',
    this.allowsClear = true,
  });
  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c);
    return Glass(
      blur: false,
      child: SpaceButton(
        tooltip: label,
        onPressed: () async {
          final d = await anchoredPopup<String>(
            c,
            DatePopover(value: value, allowsClear: allowsClear),
            width: 304,
            height: 376,
          );
          if (d != null) onChanged(d);
        },
        child: Row(
          children: [
            SpaceIcon('calendar', color: p.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value.isEmpty ? '未设置$label' : value,
                style: textStyle(
                  p,
                  size: 14,
                  color: value.isEmpty ? p.muted : p.text,
                ),
              ),
            ),
            const SpaceIcon('down', size: 10),
          ],
        ),
      ),
    );
  }
}

class DatePopover extends StatefulWidget {
  final String value;
  final bool allowsClear;
  const DatePopover({super.key, required this.value, this.allowsClear = true});
  @override
  State<DatePopover> createState() => _DatePopoverState();
}

class _DatePopoverState extends State<DatePopover> {
  late DateTime month;
  @override
  void initState() {
    super.initState();
    final d = parseDay(widget.value) ?? beijingDay();
    month = DateTime.utc(d.year, d.month);
  }

  @override
  Widget build(BuildContext c) {
    final p = Palette.of(c),
        first = month.subtract(Duration(days: month.weekday % 7));
    return PopupSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButtonS(
                'left',
                '上一个月',
                size: 40,
                onPressed: () => setState(
                  () => month = DateTime.utc(month.year, month.month - 1),
                ),
              ),
              const Spacer(),
              Text(
                '${month.year}年${month.month}月',
                style: textStyle(p, size: 16, bold: true),
              ),
              const Spacer(),
              IconButtonS(
                'right',
                '下一个月',
                size: 40,
                onPressed: () => setState(
                  () => month = DateTime.utc(month.year, month.month + 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (i, d) in [
                '日',
                '一',
                '二',
                '三',
                '四',
                '五',
                '六',
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: SizedBox(
                    height: 24,
                    child: Center(
                      child: Text(
                        d,
                        style: textStyle(p, size: 12, color: p.muted),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          for (var row = 0; row < 6; row++) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                for (var col = 0; col < 7; col++) ...[
                  if (col > 0) const SizedBox(width: 4),
                  Expanded(
                    child: Builder(
                      builder: (c) {
                        final d = first.add(Duration(days: row * 7 + col)),
                            key = dayString(d);
                        final selected = key == widget.value,
                            today = key == dayString(beijingDay());
                        return Container(
                          foregroundDecoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: today && !selected
                                ? Border.all(color: p.accent)
                                : null,
                          ),
                          decoration: BoxDecoration(
                            color: today && !selected
                                ? p.hover
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SpaceButton(
                            height: 32,
                            padding: EdgeInsets.zero,
                            primary: selected,
                            tooltip: '选择$key',
                            onPressed: () => Navigator.pop(c, key),
                            child: Text(
                              '${d.day}',
                              style: textStyle(
                                p,
                                size: 12,
                                bold: selected,
                                color: selected
                                    ? Colors.white
                                    : p.text.withValues(
                                        alpha: d.month == month.month ? 1 : .35,
                                      ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              SpaceButton(
                onPressed: () => Navigator.pop(c, dayString(beijingDay())),
                child: const Text('今天'),
              ),
              const SizedBox(width: 8),
              SpaceButton(
                onPressed: () => Navigator.pop(
                  c,
                  dayString(beijingDay().add(const Duration(days: 1))),
                ),
                child: const Text('明天'),
              ),
              const Spacer(),
              if (widget.allowsClear)
                SpaceButton(
                  onPressed: () => Navigator.pop(c, ''),
                  child: const Text('清除'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<T?> anchoredPopup<T>(
  BuildContext context,
  Widget child, {
  required double width,
  required double height,
  Color barrierColor = Colors.transparent,
}) {
  final box = context.findRenderObject() as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  final screen = MediaQuery.sizeOf(context);
  final left = anchor.left.clamp(8.0, math.max(8.0, screen.width - width - 8));
  final top = anchor.bottom + height + 6 <= screen.height - 8
      ? anchor.bottom + 6
      : math.max(8.0, anchor.top - height - 6);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭浮层',
    barrierColor: barrierColor,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (c, a, b) => Stack(
      children: [
        Positioned(
          left: left.toDouble(),
          top: top,
          width: width,
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ],
    ),
  );
}

class BoardResizeHandle extends StatefulWidget {
  final double ratio;
  final VoidCallback onStart, onEnd, onReset, onCancel;
  final ValueChanged<double> onUpdate;
  const BoardResizeHandle({
    super.key,
    required this.ratio,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onReset,
    required this.onCancel,
  });
  @override
  State<BoardResizeHandle> createState() => _BoardResizeHandleState();
}

class _BoardResizeHandleState extends State<BoardResizeHandle> {
  bool hover = false, dragging = false;
  String get label => widget.ratio == .5
      ? '1/2'
      : widget.ratio == 2 / 3
      ? '2/3'
      : widget.ratio == .75
      ? '3/4'
      : widget.ratio == 1
      ? '1/1'
      : '${(widget.ratio * 100).round()}%';
  @override
  Widget build(BuildContext c) => MouseRegion(
    cursor: SystemMouseCursors.resizeLeftRight,
    onEnter: (_) => setState(() => hover = true),
    onExit: (_) => setState(() => hover = false),
    child: Tooltip(
      message: '拖动调整列宽 · $label · 双击恢复1/1',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onDoubleTap: widget.onReset,
        onHorizontalDragStart: (_) {
          setState(() => dragging = true);
          widget.onStart();
        },
        onHorizontalDragUpdate: (d) => widget.onUpdate(d.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => dragging = false);
          widget.onEnd();
        },
        onHorizontalDragCancel: () {
          setState(() => dragging = false);
          widget.onCancel();
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Container(
                width: 2,
                color: hover || dragging
                    ? Palette.of(c).accent
                    : Colors.transparent,
              ),
            ),
            if (dragging)
              Positioned(
                right: 8,
                top: 48,
                child: Material(
                  color: Palette.of(c).canvas,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      label,
                      style: textStyle(Palette.of(c), size: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class SpaceMultiSelect extends StatelessWidget {
  final Set<String> values;
  final Map<String, String> options;
  final String label;
  final double? width;
  final VoidCallback onChanged;
  const SpaceMultiSelect({
    super.key,
    required this.values,
    required this.options,
    required this.label,
    required this.onChanged,
    this.width,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Builder(
      builder: (anchor) => SpaceButton(
        tooltip: label,
        selected: values.isNotEmpty,
        onPressed: () => anchoredPopup(
          anchor,
          StatefulBuilder(
            builder: (c, set) => Glass(
              padding: const EdgeInsets.all(8),
              child: Focus(
                autofocus: true,
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    Navigator.pop(c);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Material(
                  type: MaterialType.transparency,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 344),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        SpaceButton(
                          onPressed: () {
                            values.clear();
                            onChanged();
                            set(() {});
                          },
                          child: Text('全部$label'),
                        ),
                        for (final e in options.entries)
                          CheckboxListTile(
                            dense: true,
                            title: Text(e.value),
                            value: values.contains(e.key),
                            onChanged: (_) {
                              if (!values.remove(e.key)) {
                                values.add(e.key);
                              }
                              onChanged();
                              set(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          width: 280,
          height: (options.length * 48.0 + 64).clamp(112, 360),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                values.isEmpty
                    ? '全部$label'
                    : values.length == 1
                    ? (options[values.first] ?? label)
                    : '$label · 已选${values.length}项',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const SpaceIcon('down', size: 9),
          ],
        ),
      ),
    ),
  );
}
