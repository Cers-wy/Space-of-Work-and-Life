import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class Palette extends ThemeExtension<Palette> {
  final double darkness;
  bool get dark => darkness >= .5;
  const Palette(bool dark) : darkness = dark ? 1 : 0;
  const Palette._(this.darkness);
  Color blend(Color light, Color dark) => Color.lerp(light, dark, darkness)!;
  @override
  Palette copyWith({double? darkness}) => Palette._(darkness ?? this.darkness);
  @override
  Palette lerp(covariant Palette? other, double t) => other == null
      ? this
      : Palette._(darkness + (other.darkness - darkness) * t);
  Color value(int light, int darkValue) =>
      blend(Color(0xff000000 | light), Color(0xff000000 | darkValue));
  Color get canvas => value(0xe8eef6, 0x000000);
  Color get text => value(0x26364d, 0xf5f5f7);
  Color get secondary => value(0x53647b, 0xccccd2);
  Color get muted => value(0x64738b, 0xa0a0ab);
  Color get accent => value(0x2f6cff, 0xb879ff);
  Color get blue => value(0x3668c1, 0xabc7ff);
  Color get purple => value(0x7759ad, 0xc5b5ff);
  Color get green => value(0x2d806b, 0x96dbc2);
  Color get amber => value(0x93672d, 0xf0cf9c);
  Color get red => value(0xba5366, 0xf9b3c2);
  Color get border => blend(
    Colors.white.withValues(alpha: .85),
    const Color(0xffc4b5d8).withValues(alpha: .18),
  );
  Color get card => blend(
    Colors.white.withValues(alpha: .72),
    const Color(0xff1f1f1f).withValues(alpha: .66),
  );
  Color get panel => blend(
    const Color(0xfff9fcff).withValues(alpha: .52),
    const Color(0xff181818).withValues(alpha: .55),
  );
  Color get primary => value(0x356bfa, 0x9333ea);
  Color get hover => accent.withValues(alpha: .08 + .08 * darkness);
  Color selectedButtonBackground([Color? darkColor]) =>
      blend(const Palette(false).primary, darkColor ?? hover);
  Color selectedButtonForeground([Color? darkColor]) =>
      blend(Colors.white, darkColor ?? accent);
  Color get popup => value(0xffffff, 0x27232e);
  Color get popupBorder => value(0xcbd6e5, 0x665572);
  Color category(String s) => s == 'work'
      ? blue
      : s == 'personal'
      ? purple
      : green;
  Color status(String s) => s == 'todo'
      ? blue
      : s == 'doing'
      ? purple
      : s == 'done'
      ? green
      : accent;
  Color priority(String s) => s == 'high'
      ? red
      : s == 'medium'
      ? amber
      : muted;
  static Palette of(BuildContext c) =>
      Theme.of(c).extension<Palette>() ??
      Palette(Theme.of(c).brightness == Brightness.dark);
}

const spaceCurve = Cubic(.22, 1, .36, 1);
const spaceTitleBarHeight = 40.0;
const spaceDuration = Duration(milliseconds: 500);
TextStyle textStyle(
  Palette p, {
  double size = 14,
  bool bold = false,
  Color? color,
}) => TextStyle(
  fontFamily: 'PingFang SC',
  fontFamilyFallback: const [
    'Microsoft YaHei UI',
    'Noto Sans CJK SC',
    'sans-serif',
  ],
  fontSize: size,
  fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
  color: color ?? p.text,
  decoration: TextDecoration.none,
);
ThemeData spaceTheme(bool dark) {
  final p = Palette(dark);
  return ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    fontFamily: 'PingFang SC',
    extensions: [p],
    scaffoldBackgroundColor: p.canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: dark ? Brightness.dark : Brightness.light,
    ),
    textTheme: TextTheme(
      bodyMedium: textStyle(p),
      bodySmall: textStyle(p, size: 12),
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: textStyle(p, size: 12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xff27232e) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.border),
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withValues(alpha: .25),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.dragged)
            ? 6.0
            : 4.0,
      ),
      radius: const Radius.circular(4),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => p.secondary.withValues(
          alpha: states.contains(WidgetState.dragged)
              ? .7
              : states.contains(WidgetState.hovered)
              ? .55
              : .35,
        ),
      ),
      crossAxisMargin: 2,
      mainAxisMargin: 2,
      interactive: true,
    ),
    dividerColor: p.border,
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      border: InputBorder.none,
    ),
  );
}

class SpaceAccessibility extends InheritedWidget {
  final bool reduceTransparency;
  const SpaceAccessibility({
    super.key,
    required this.reduceTransparency,
    required super.child,
  });
  static bool reduced(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SpaceAccessibility>()
          ?.reduceTransparency ??
      false;
  @override
  bool updateShouldNotify(SpaceAccessibility old) =>
      old.reduceTransparency != reduceTransparency;
}

class Ambient extends StatelessWidget {
  final bool reduceTransparency;
  const Ambient({super.key, this.reduceTransparency = false});
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _AmbientPainter(
        Palette.of(context),
        reduceTransparency || SpaceAccessibility.reduced(context),
      ),
      size: Size.infinite,
    ),
  );
}

class _AmbientPainter extends CustomPainter {
  final Palette palette;
  final bool reduced;
  _AmbientPainter(this.palette, this.reduced);
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = palette.canvas);
    if (reduced) return;
    const light = <List<num>>[
      [0xaacbfa, .65, .7, .9, 100, -.3, .15],
      [0xd1daf6, .7, .7, 1, 100, .4, -.35],
      [0xfaf9f1, .8, .6, .8, 80, 0, 0],
    ];
    const dark = <List<num>>[
      [0x8b5cf6, .22, .5, .65, 120, .05, .05],
      [0x9333ea, .36, .65, .55, 100, .35, -.4],
      [0xa855f7, .28, .55, .45, 100, -.35, .45],
    ];
    final items = List.generate(
      light.length,
      (i) => <num>[
        0,
        for (var j = 1; j < light[i].length; j++)
          light[i][j] + (dark[i][j] - light[i][j]) * palette.darkness,
      ],
    );
    for (var i = 0; i < items.length; i++) {
      final e = items[i];
      c.drawOval(
        Rect.fromCenter(
          center: Offset(s.width * (.5 + e[5]), s.height * (.5 + e[6])),
          width: s.width * e[2],
          height: s.height * e[3],
        ),
        Paint()
          ..color = palette
              .blend(
                Color(0xff000000 | light[i][0].toInt()),
                Color(0xff000000 | dark[i][0].toInt()),
              )
              .withValues(alpha: e[1].toDouble())
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, e[4].toDouble()),
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.palette.darkness != palette.darkness || old.reduced != reduced;
}

class Contour extends CustomClipper<Path> {
  final String kind;
  const Contour(this.kind);
  Path path(Size s) {
    final w = s.width, h = s.height;
    if (kind == 'sidebar') {
      final e = w - 16;
      return Path()
        ..moveTo(8, 0)
        ..lineTo(e - 8, 0)
        ..quadraticBezierTo(e, 0, e, 8)
        ..lineTo(e, 12)
        ..cubicTo(e, 17, e + 3, 20, e + 8, 20)
        ..cubicTo(e + 13, 20, e + 16, 23, e + 16, 28)
        ..lineTo(e + 16, 36)
        ..cubicTo(e + 16, 41, e + 13, 44, e + 8, 44)
        ..cubicTo(e + 3, 44, e, 47, e, 52)
        ..lineTo(e, h - 8)
        ..quadraticBezierTo(e, h, e - 8, h)
        ..lineTo(8, h)
        ..quadraticBezierTo(0, h, 0, h - 8)
        ..lineTo(0, 8)
        ..quadraticBezierTo(0, 0, 8, 0)
        ..close();
    }
    if (kind == 'overview') {
      return Path()
        ..moveTo(8, 0)
        ..lineTo(w - 8, 0)
        ..quadraticBezierTo(w, 0, w, 8)
        ..lineTo(w, h - 8)
        ..quadraticBezierTo(w, h, w - 8, h)
        ..lineTo(8, h)
        ..quadraticBezierTo(0, h, 0, h - 8)
        ..lineTo(0, 52)
        ..cubicTo(0, 47, 3, 44, 8, 44)
        ..cubicTo(13, 44, 16, 41, 16, 36)
        ..lineTo(16, 28)
        ..cubicTo(16, 23, 13, 20, 8, 20)
        ..cubicTo(3, 20, 0, 17, 0, 12)
        ..lineTo(0, 8)
        ..quadraticBezierTo(0, 0, 8, 0)
        ..close();
    }
    return Path()..addRRect(
      RRect.fromRectAndRadius(
        Offset.zero & s,
        Radius.circular(kind == 'settings' ? 16 : 8),
      ),
    );
  }

  @override
  Path getClip(Size size) => path(size);
  @override
  bool shouldReclip(Contour oldClipper) => oldClipper.kind != kind;
}

/// Scoped to the workspace, whose surfaces sit over the already softened
/// ambient background. Keep filter elements mounted while resizing so focus,
/// scroll positions and card state survive the transition.
class WorkspaceMotion extends InheritedWidget {
  final bool active;
  const WorkspaceMotion({
    super.key,
    required this.active,
    required super.child,
  });
  static bool activeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceMotion>()?.active ??
      false;
  @override
  bool updateShouldNotify(WorkspaceMotion oldWidget) =>
      active != oldWidget.active;
}

class Glass extends StatelessWidget {
  final Widget child;
  final Widget? background;
  final String contour;
  final bool card, blur;
  final EdgeInsetsGeometry? padding;
  const Glass({
    super.key,
    required this.child,
    this.background,
    this.contour = '',
    this.card = false,
    this.blur = true,
    this.padding,
  });
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final shape = Contour(contour);
    final reduced = SpaceAccessibility.reduced(context);
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: reduced
            ? p.blend(
                Colors.white,
                card ? const Color(0xff1f1f1f) : const Color(0xff181818),
              )
            : card
            ? p.card
            : p.panel,
      ),
      child: ColoredBox(
        color: const Color(
          0xffa855f7,
        ).withValues(alpha: card ? 0 : .055 * p.darkness),
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
    if (blur && !reduced) {
      surface = BackdropFilter.grouped(
        enabled: !WorkspaceMotion.activeOf(context),
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: surface,
      );
    }
    return ClipPath(
      clipper: shape,
      child: CustomPaint(
        foregroundPainter: _GlassEdge(shape, p),
        child: background == null
            ? surface
            : Stack(
                children: [
                  Positioned.fill(child: background!),
                  surface,
                ],
              ),
      ),
    );
  }
}

class _GlassEdge extends CustomPainter {
  final Contour contour;
  final Palette p;
  _GlassEdge(this.contour, this.p);
  @override
  void paint(Canvas c, Size s) {
    final path = contour.path(s);
    c.save();
    c.clipPath(path);
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = p.border,
    );
    c.restore();
  }

  @override
  bool shouldRepaint(_GlassEdge o) =>
      p.darkness != o.p.darkness || contour.kind != o.contour.kind;
}

class PopupSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const PopupSurface({super.key, required this.child, this.padding});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.popup,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.popupBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.dark ? .32 : .14),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class CardFlow extends StatefulWidget {
  final Widget child;
  final bool emphasized;
  final double time;
  static int _snapshots = 0;
  @visibleForTesting
  static int get debugSnapshotImages => _snapshots;
  const CardFlow({
    super.key,
    required this.child,
    this.emphasized = false,
    this.time = 0,
  });
  @override
  State<CardFlow> createState() => _CardFlowState();
}

class _CardFlowState extends State<CardFlow> {
  _FlowSnapshot? snapshot;
  @override
  Widget build(BuildContext context) {
    final moving = WorkspaceMotion.activeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (!moving || snapshot?.dpr != dpr) {
      snapshot?.dispose();
      snapshot = null;
    }
    if (moving) snapshot ??= _FlowSnapshot(dpr);
    return CustomPaint(
      foregroundPainter: _FlowPainter(
        Palette.of(context),
        widget.emphasized,
        widget.time,
        snapshot,
      ),
      child: widget.child,
    );
  }

  @override
  void dispose() {
    snapshot?.dispose();
    super.dispose();
  }
}

class _FlowSnapshot {
  final double dpr;
  ui.Image? image;
  _FlowSnapshot(this.dpr);
  void dispose() {
    if (image != null) {
      image!.dispose();
      image = null;
      CardFlow._snapshots--;
    }
  }
}

class _FlowPainter extends CustomPainter {
  final Palette p;
  final bool emphasized;
  final double time;
  final _FlowSnapshot? snapshot;
  _FlowPainter(this.p, this.emphasized, this.time, [this.snapshot]);
  @override
  void paint(Canvas c, Size s) {
    final frozen = snapshot;
    if (frozen != null && !s.isEmpty) {
      if (frozen.image == null) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(frozen.dpr);
        _FlowPainter(p, emphasized, time).paint(canvas, s);
        final picture = recorder.endRecording();
        frozen.image = picture.toImageSync(
          (s.width * frozen.dpr).ceil(),
          (s.height * frozen.dpr).ceil(),
        );
        picture.dispose();
        CardFlow._snapshots++;
      }
      final image = frozen.image!;
      c.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & s,
        Paint()..filterQuality = FilterQuality.low,
      );
      return;
    }
    final r = RRect.fromRectAndRadius(
      (Offset.zero & s).deflate(.5),
      const Radius.circular(8),
    );
    c.save();
    c.clipRRect(r);
    final x = s.width * ((math.sin(time / 4.5) + 1) / 2 - .25);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, s.height - 10, s.width * .6, 12),
        const Radius.circular(6),
      ),
      Paint()
        ..color = p.accent.withValues(alpha: emphasized ? 0.6 : .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    final angle = time == 0 ? 220 : time % 12 * 30;
    final shader = SweepGradient(
      transform: GradientRotation(angle * math.pi / 180),
      colors: [
        p.accent.withValues(alpha: .12),
        p.accent.withValues(alpha: .16),
        p.accent.withValues(alpha: .55),
        p.dark ? const Color(0xffe6c5ff) : p.accent,
        p.accent.withValues(alpha: .85),
        p.accent.withValues(alpha: .12),
      ],
      stops: const [0, .48, .68, .8, .85, 1],
    ).createShader(Offset.zero & s);
    c.drawRRect(
      r,
      Paint()
        ..color = p.dark ? p.accent.withValues(alpha: .35) : p.border
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
    c.drawRRect(
      r,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = emphasized ? 3 : 2
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.dark ? 4 : 3)
        ..color = Colors.white.withValues(alpha: p.dark ? 0.85 : .3),
    );
    c.drawRRect(
      r,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = emphasized ? 1.5 : 1,
    );
    c.restore();
  }

  @override
  bool shouldRepaint(_FlowPainter o) =>
      o.p.darkness != p.darkness ||
      o.time != time ||
      o.emphasized != emphasized ||
      o.snapshot != snapshot;
}

/// Applied above the Navigator so existing routes, popups and editors update too.
class SpaceScrollBehavior extends MaterialScrollBehavior {
  final bool hidden;
  const SpaceScrollBehavior({required this.hidden});
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (hidden) return child;
    return Scrollbar(controller: details.controller, child: child);
  }

  @override
  bool shouldNotify(covariant SpaceScrollBehavior oldDelegate) =>
      hidden != oldDelegate.hidden;
}
