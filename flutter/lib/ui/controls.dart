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
      case 'upload':
        path(const [Offset(6, 6), Offset(10, 2), Offset(14, 6)]);
        line(10, 2, 10, 13);
        path(const [
          Offset(3, 11),
          Offset(3, 18),
          Offset(17, 18),
          Offset(17, 11),
        ]);
      case 'pause':
        line(7, 4, 7, 16);
        line(13, 4, 13, 16);
      case 'play':
        path(const [Offset(6, 3), Offset(16, 10), Offset(6, 17), Offset(6, 3)]);
      case 'refresh':
        c.drawArc(
          const Rect.fromLTWH(3, 3, 14, 14),
          math.pi * .2,
          math.pi * 1.6,
          false,
          p,
        );
        path(const [Offset(16, 2), Offset(16, 6), Offset(12, 6)]);
      case 'preview':
        c.drawPath(
          Path()
            ..moveTo(2, 10)
            ..quadraticBezierTo(10, 0, 18, 10)
            ..quadraticBezierTo(10, 20, 2, 10),
          p,
        );
        c.drawCircle(const Offset(10, 10), 2.5, p);
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
      case 'tools':
        c.drawPath(
          Path()
            ..moveTo(16.6, 2.2)
            ..cubicTo(13.5, 1.2, 11.1, 3.8, 11.8, 7.2)
            ..lineTo(3.0, 16)
            ..quadraticBezierTo(2.0, 17.2, 3.1, 18.1)
            ..quadraticBezierTo(4.2, 19.1, 5.3, 18)
            ..lineTo(14, 9.3)
            ..cubicTo(17.4, 10.1, 20, 7.2, 18.9, 4.2)
            ..lineTo(16.5, 6.5)
            ..lineTo(14.5, 5.8)
            ..lineTo(14.1, 4.5)
            ..close(),
          p,
        );
        path(const [Offset(9, 10), Offset(2, 4), Offset(4, 2), Offset(10, 8)]);
        path(const [
          Offset(13, 12),
          Offset(18, 16.5),
          Offset(18, 18),
          Offset(16.5, 18),
          Offset(12, 13.5),
        ]);
      case 'invoice':
        path(const [
          Offset(4, 2),
          Offset(16, 2),
          Offset(16, 18),
          Offset(13, 16),
          Offset(10, 18),
          Offset(7, 16),
          Offset(4, 18),
          Offset(4, 2),
        ]);
        line(7, 6, 13, 6);
        line(7, 9.5, 13, 9.5);
        line(7, 13, 10.5, 13);
      case 'printer':
        rect(3, 7, 14, 7);
        path(const [Offset(6, 7), Offset(6, 2), Offset(14, 2), Offset(14, 7)]);
        rect(6, 11, 8, 7);
        line(13.5, 9, 14.5, 9);
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

const spaceFormControlHeight = 40.0;

class SpaceButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool primary, selected, danger, subtle;
  final bool _form;
  final bool showSelectedBackground, showHoverBackground;
  final double? height;
  final double surfaceInset;
  final EdgeInsetsGeometry padding;
  const SpaceButton({
    super.key,
    required this.child,
    this.onPressed,
    this.tooltip,
    this.primary = false,
    this.selected = false,
    this.showSelectedBackground = true,
    this.showHoverBackground = true,
    this.danger = false,
    this.subtle = false,
    this.height = 40,
    this.surfaceInset = 0,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
  }) : _form = false;

  SpaceButton.form(
    String label, {
    super.key,
    this.onPressed,
    this.tooltip,
    this.primary = false,
    this.danger = false,
  }) : child = Text(label),
       _form = true,
       subtle = true,
       selected = false,
       showSelectedBackground = true,
       showHoverBackground = true,
       height = spaceFormControlHeight,
       surfaceInset = 0,
       padding = const EdgeInsets.symmetric(horizontal: 12);

  @override
  State<SpaceButton> createState() => _SpaceButtonState();
}

class _SpaceButtonState extends State<SpaceButton> {
  bool hover = false, focus = false, pressed = false;
  @override
  Widget build(BuildContext context) {
    final w = widget, p = Palette.of(context);
    final filledSelection = w.selected && w.showSelectedBackground;
    final highlighted = hover && w.showHoverBackground;
    final hoverFill = w.danger ? p.red.withValues(alpha: .12) : p.hover;
    final formFill = p.card.withValues(alpha: .50);
    final background = w.subtle && (w.primary || filledSelection)
        ? p.actionSurface(highlighted: highlighted)
        : w.primary
        ? p.primary
        : filledSelection
        ? p.selectedButtonBackground()
        : w._form
        ? (highlighted ? Color.alphaBlend(hoverFill, formFill) : formFill)
        : highlighted
        ? hoverFill
        : Colors.transparent;
    final color = w.danger
        ? p.red
        : w.subtle && (w.primary || filledSelection)
        ? p.accentText
        : w.primary
        ? Colors.white
        : filledSelection
        ? p.selectedButtonForeground()
        : w._form
        ? p.text
        : w.selected
        ? p.accent
        : p.secondary;
    final radius = BorderRadius.circular(8);
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
        onTap: w.onPressed,
        child: GestureDetector(
          excludeFromSemantics: true,
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
            child: Padding(
              padding: EdgeInsets.all(w.surfaceInset),
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                curve: spaceCurve,
                height: w.height == null
                    ? null
                    : w.height! - 2 * w.surfaceInset,
                constraints: w._form
                    ? const BoxConstraints(minWidth: 72)
                    : null,
                padding: w.padding,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: radius,
                  border: w.subtle && w.primary
                      ? Border.all(color: p.actionBorder)
                      : w._form
                      ? Border.all(color: p.border)
                      : null,
                ),
                foregroundDecoration: focus
                    ? BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          color: !w.subtle && filledSelection
                              ? p.selectedButtonForeground()
                              : p.accent,
                          width: 2,
                        ),
                      )
                    : null,
                child: DefaultTextStyle(
                  style: textStyle(
                    p,
                    size: w.subtle ? 13 : 14,
                    bold: true,
                    color: color,
                  ),
                  child: IconTheme(
                    data: IconThemeData(color: color, size: 14),
                    child: Center(widthFactor: 1, child: w.child),
                  ),
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
  final bool primary, selected, danger;
  final double size, iconSize;
  final double _surfaceInset;
  const IconButtonS(
    this.icon,
    this.label, {
    super.key,
    this.onPressed,
    this.primary = false,
    this.selected = false,
    this.danger = false,
    this.size = 32,
    this.iconSize = 16,
  }) : _surfaceInset = 0;

  const IconButtonS.toolbar(
    this.icon,
    this.label, {
    super.key,
    this.onPressed,
    this.primary = false,
    this.selected = false,
    this.danger = false,
    this.iconSize = 14,
  }) : size = 32,
       _surfaceInset = 2;

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
        danger: danger,
        height: size,
        surfaceInset: _surfaceInset,
        padding: EdgeInsets.zero,
        child: SpaceIcon(
          icon,
          size: iconSize,
          color: onPressed == null
              ? p.muted.withValues(alpha: .35)
              : primary
              ? Colors.white
              : danger
              ? p.red
              : selected
              ? p.selectedButtonForeground()
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

class SpaceTitleBar extends StatelessWidget {
  final List<Widget> children;
  const SpaceTitleBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: spaceTitleBarHeight,
    width: double.infinity,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: children),
    ),
  );
}

class SpaceEditorSection extends StatelessWidget {
  final String? title, detail;
  final List<Widget> children;
  const SpaceEditorSection({
    super.key,
    this.title,
    this.detail,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Glass(
      blur: false,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final heading?)
            Text(heading, style: textStyle(p, bold: true)),
          if (detail case final description?) ...[
            if (title != null) const SizedBox(height: 4),
            Text(description, style: textStyle(p, size: 12, color: p.muted)),
          ],
          if (title != null || detail != null) const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class SpaceEditorFooter extends StatelessWidget {
  final List<Widget> children;
  const SpaceEditorFooter({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Divider(height: 1, color: Palette.of(context).border),
      SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: children),
        ),
      ),
    ],
  );
}

class SpaceEditorRow extends StatelessWidget {
  final List<Widget> children;
  final bool selected;
  const SpaceEditorRow({
    super.key,
    required this.children,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) => Glass(
    blur: false,
    child: AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 140),
      curve: spaceCurve,
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: selected ? Palette.of(context).hover : Colors.transparent,
      child: Row(children: children),
    ),
  );
}

class SpaceCheckbox extends StatelessWidget {
  final bool? value;
  final String label;
  final String? description;
  final bool showLabel;
  final VoidCallback? onPressed;

  const SpaceCheckbox({
    super.key,
    required this.value,
    required this.label,
    this.description,
    this.showLabel = true,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = onPressed != null;
    final color = !enabled
        ? p.muted.withValues(alpha: .45)
        : value == false
        ? p.secondary
        : p.accent;
    final indicator = SizedBox.square(
      dimension: 32,
      child: Center(
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 140),
          curve: spaceCurve,
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value == false
                ? Colors.transparent
                : color.withValues(alpha: .14),
            border: Border.all(color: color),
          ),
          child: switch (value) {
            true => SpaceIcon('check', size: 13, color: color),
            null => SizedBox(
              width: 8,
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
            false => null,
          },
        ),
      ),
    );
    final control = Semantics(
      container: true,
      label: label,
      hint: description,
      checked: value ?? false,
      mixed: value == null,
      enabled: enabled,
      onTap: onPressed,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          excludeFromSemantics: true,
          splashFactory: NoSplash.splashFactory,
          onTap: onPressed,
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          borderRadius: BorderRadius.circular(8),
          hoverColor: p.hover,
          focusColor: p.accent.withValues(alpha: .22),
          highlightColor: p.accent.withValues(alpha: .16),
          child: showLabel
              ? ExcludeSemantics(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: description == null ? 48 : 56,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          indicator,
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: textStyle(
                                    p,
                                    color: enabled ? p.text : p.muted,
                                  ),
                                ),
                                if (description != null)
                                  Text(
                                    description!,
                                    style: textStyle(
                                      p,
                                      size: 12,
                                      color: p.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : indicator,
        ),
      ),
    );
    return showLabel
        ? control
        : Tooltip(message: label, excludeFromSemantics: true, child: control);
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
  final bool selected;
  const CategoryLabel(
    this.category, {
    super.key,
    this.count,
    this.name,
    this.selected = false,
  });
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
            color: selected
                ? p.selectedButtonForeground(p.category(category))
                : p.category(category),
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${name ?? categories[category] ?? category}${count == null ? '' : ' $count'}',
            style: textStyle(
              p,
              size: 12,
              color: selected
                  ? p.selectedButtonForeground(p.secondary)
                  : p.secondary,
            ),
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
  Widget build(BuildContext context) => IconButtonS.toolbar(
    dark ? 'sun' : 'moon',
    dark ? '切换到明亮主题' : '切换到暗色主题',
    onPressed: onToggle,
  );
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
      height: lines == 1 ? spaceFormControlHeight : null,
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
              ? const BoxConstraints.tightFor(height: spaceFormControlHeight)
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
            minHeight: spaceFormControlHeight,
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

class SpacePickerField extends StatefulWidget {
  final String label, text;
  final String? icon;
  final double? width;
  final bool active, placeholder;
  final Future<void> Function(BuildContext)? open;

  const SpacePickerField({
    super.key,
    required this.label,
    required this.text,
    required this.open,
    this.icon,
    this.width,
    this.active = false,
    this.placeholder = false,
  });

  @override
  State<SpacePickerField> createState() => _SpacePickerFieldState();
}

class _SpacePickerFieldState extends State<SpacePickerField> {
  bool expanded = false;

  Future<void> open() async {
    if (expanded) return;
    setState(() => expanded = true);
    try {
      await widget.open!(context);
    } finally {
      if (mounted) setState(() => expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140);
    return SizedBox(
      width: widget.width,
      child: AnimatedContainer(
        duration: motion,
        curve: spaceCurve,
        decoration: BoxDecoration(
          color: widget.active
              ? p.selectedButtonBackground()
              : p.card.withValues(alpha: .50),
          borderRadius: BorderRadius.circular(8),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: expanded ? p.accent : p.border),
        ),
        child: Semantics(
          expanded: expanded,
          value: widget.text,
          child: SpaceButton(
            tooltip: widget.label,
            onPressed: widget.open == null ? null : open,
            child: Row(
              children: [
                if (widget.icon case final icon?) ...[
                  SpaceIcon(
                    icon,
                    size: 16,
                    color: widget.active
                        ? p.selectedButtonForeground()
                        : p.accent,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    widget.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(
                      p,
                      size: 12,
                      color: widget.active
                          ? p.selectedButtonForeground()
                          : widget.placeholder
                          ? p.muted
                          : p.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: expanded ? .5 : 0,
                  duration: motion,
                  curve: spaceCurve,
                  child: SpaceIcon(
                    'down',
                    size: 12,
                    color: widget.active
                        ? p.selectedButtonForeground(p.secondary)
                        : p.secondary,
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

Map<String, String> projectChoices(SpaceState state, {String? selected}) => {
  '': '无项目',
  for (final project in state.projects)
    if (!project.disabled || project.id == selected)
      project.id: '${project.name}${project.disabled ? '（已停用）' : ''}',
};

class SpaceSelect extends StatelessWidget {
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
  Widget build(BuildContext context) => SpacePickerField(
    label: label,
    text: options[value] ?? label,
    width: width,
    active: active,
    placeholder: !options.containsKey(value),
    open: options.isEmpty
        ? null
        : (anchor) async {
            final box = anchor.findRenderObject() as RenderBox;
            final result = await anchoredPopup<String>(
              anchor,
              _Options(options: options.entries.toList(), value: value),
              width: math.max(180, box.size.width),
              height: math.min(options.length * 40.0 + 16, 320),
              constrainHeight: true,
            );
            if (anchor.mounted && result != null && result != value) {
              onChanged(result);
            }
          },
  );
}

class _Options extends StatefulWidget {
  final List<MapEntry<String, String>> options;
  final String value;
  const _Options({required this.options, required this.value});
  @override
  State<_Options> createState() => _OptionsState();
}

class _OptionsState extends State<_Options> {
  late int index;
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    index = math.max(
      0,
      widget.options.indexWhere((e) => e.key == widget.value),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => revealIndex());
  }

  void revealIndex() {
    if (!mounted || !scroll.hasClients) return;
    final start = index * 40.0 + 8;
    final end = start + 36;
    final position = scroll.position;
    if (start < position.pixels) {
      scroll.jumpTo(start.clamp(0, position.maxScrollExtent));
    } else if (end > position.pixels + position.viewportDimension) {
      scroll.jumpTo(
        (end - position.viewportDimension).clamp(0, position.maxScrollExtent),
      );
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
    } else if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space) &&
        event is KeyDownEvent) {
      Navigator.pop(context, widget.options[index].key);
    } else {
      final target = switch (key) {
        LogicalKeyboardKey.arrowDown => index + 1,
        LogicalKeyboardKey.arrowUp => index - 1,
        LogicalKeyboardKey.home => 0,
        LogicalKeyboardKey.end => widget.options.length - 1,
        _ => null,
      };
      if (target == null) return KeyEventResult.ignored;
      setState(() => index = target.clamp(0, widget.options.length - 1));
      revealIndex();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: key,
      child: PopupSurface(
        child: ListView.separated(
          controller: scroll,
          padding: const EdgeInsets.all(8),
          itemCount: widget.options.length,
          separatorBuilder: (_, i) => const SizedBox(height: 4),
          itemBuilder: (context, i) {
            final option = widget.options[i];
            final selected = option.key == widget.value;
            return MouseRegion(
              onEnter: (_) => setState(() => index = i),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: i == index ? p.hover : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SpaceButton(
                  height: 36,
                  selected: selected,
                  onPressed: () => Navigator.pop(context, option.key),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        child: selected
                            ? SpaceIcon(
                                'check',
                                size: 14,
                                color: p.selectedButtonForeground(),
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          option.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle(
                            p,
                            size: 12,
                            color: selected
                                ? p.selectedButtonForeground()
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
  Widget build(BuildContext c) => SpacePickerField(
    label: label,
    text: value.isEmpty ? '未设置$label' : value,
    icon: 'calendar',
    placeholder: value.isEmpty,
    open: (anchor) async {
      final date = await anchoredPopup<String>(
        anchor,
        DatePopover(value: value, allowsClear: allowsClear),
        width: 304,
        height: 376,
      );
      if (anchor.mounted && date != null) onChanged(date);
    },
  );
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
  bool constrainHeight = false,
}) {
  final box = context.findRenderObject() as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  final screen = MediaQuery.sizeOf(context);
  final popupWidth = math.min(width, math.max(1.0, screen.width - 16));
  final left = anchor.left.clamp(
    8.0,
    math.max(8.0, screen.width - popupWidth - 8),
  );
  final below = math.max(0.0, screen.height - anchor.bottom - 16);
  final above = math.max(0.0, anchor.top - 16);
  // Some callers use the whole workspace when there is no button to anchor to.
  final useViewport = constrainHeight && below == 0 && above == 0;
  final openBelow = height <= below || (constrainHeight && below >= above);
  final available = useViewport
      ? screen.height - 16
      : (openBelow ? below : above);
  final popupHeight = constrainHeight
      ? math.min(height, math.max(1.0, available))
      : height;
  final top = useViewport
      ? 8.0
      : openBelow
      ? anchor.bottom + 8
      : math.max(8.0, anchor.top - popupHeight - 8);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭浮层',
    barrierColor: barrierColor,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 120),
    pageBuilder: (c, a, b) => Stack(
      children: [
        Positioned(
          left: left.toDouble(),
          top: top,
          width: popupWidth,
          height: constrainHeight ? popupHeight : null,
          child: Material(
            type: MaterialType.transparency,
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  Navigator.pop(c);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: child,
            ),
          ),
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
  final VoidCallback? onChanged;
  final Future<bool> Function(Set<String>)? saveSelection;
  const SpaceMultiSelect({
    super.key,
    required this.values,
    required this.options,
    required this.label,
    required VoidCallback this.onChanged,
    this.width,
  }) : saveSelection = null;

  const SpaceMultiSelect.persistent({
    super.key,
    required this.values,
    required this.options,
    required this.label,
    required Future<bool> Function(Set<String>) this.saveSelection,
    this.width,
  }) : onChanged = null;

  bool get persistent => saveSelection != null;
  bool get all => persistent ? values.length == options.length : values.isEmpty;

  @override
  Widget build(BuildContext context) => SpacePickerField(
    label: label,
    width: width,
    active: !all,
    text: all
        ? '全部$label'
        : values.length == 1
        ? (options[values.first] ?? label)
        : '$label · 已选${values.length}项',
    open: open,
  );

  Future<void> open(BuildContext anchor) async {
    var selected = values;
    var saving = false, saveFailed = false;
    await anchoredPopup<void>(
      anchor,
      StatefulBuilder(
        builder: (context, setPopupState) {
          Future<void> change(Set<String> next) async {
            if (saving) return;
            if (saveSelection case final save?) {
              final previous = selected;
              setPopupState(() {
                selected = next;
                saving = true;
                saveFailed = false;
              });
              final saved = await save(next);
              if (context.mounted) {
                setPopupState(() {
                  if (!saved) selected = previous;
                  saving = false;
                  saveFailed = !saved;
                });
              }
            } else {
              selected
                ..clear()
                ..addAll(next);
              onChanged!();
              setPopupState(() {});
            }
          }

          return Focus(
            autofocus: true,
            child: PopupSurface(
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  SpaceButton(
                    height: 36,
                    selected: persistent
                        ? selected.length == options.length
                        : selected.isEmpty,
                    onPressed: saving
                        ? null
                        : () => change(persistent ? options.keys.toSet() : {}),
                    child: Text('全部$label'),
                  ),
                  for (final entry in options.entries)
                    SpaceCheckbox(
                      label: entry.value,
                      value: selected.contains(entry.key),
                      description:
                          persistent &&
                              selected.length == 1 &&
                              selected.contains(entry.key)
                          ? '至少保留一列'
                          : null,
                      onPressed: saving
                          ? null
                          : () {
                              final next = {...selected};
                              if (!next.remove(entry.key)) next.add(entry.key);
                              if (!persistent || next.isNotEmpty) change(next);
                            },
                    ),
                  if (saveFailed)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        '设置保存失败，请重试。',
                        style: textStyle(
                          Palette.of(context),
                          size: 12,
                          color: Palette.of(context).red,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      width: 240,
      height: math.min(options.length * 48.0 + 52, 360),
      constrainHeight: true,
    );
  }
}
