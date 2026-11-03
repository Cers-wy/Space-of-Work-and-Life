import 'package:flutter/material.dart';
import 'theme.dart';

/// Schedule-only colors: the workspace theme and other views keep their palette.
class GanttInk {
  final Color fill;
  const GanttInk(this.fill);
  Color get foreground => Colors.white;
  Color get detail => Colors.white.withValues(alpha: .78);

  factory GanttInk.forStatus(Palette p, String status) {
    const light = [
      0xff5475ad,
      0xff8860b2,
      0xff397c68,
      0xff846039,
      0xff965778,
      0xff426e85,
    ];
    const dark = [
      0xff4f5f91,
      0xff745294,
      0xff447b6c,
      0xff89643d,
      0xff945b7c,
      0xff436f86,
    ];
    final int index;
    if (status == 'todo') {
      index = 0;
    } else if (status == 'doing') {
      index = 1;
    } else if (status == 'done') {
      index = 2;
    } else {
      // Stable across launches and status reordering; no model/schema changes.
      var hash = 0;
      for (final unit in status.codeUnits) {
        hash = (hash * 31 + unit) & 0x7fffffff;
      }
      index = 3 + hash % 3;
    }
    return GanttInk(p.blend(Color(light[index]), Color(dark[index])));
  }
}
