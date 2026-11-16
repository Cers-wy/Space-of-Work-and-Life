import 'package:flutter/material.dart';

import 'theme.dart';

/// Shared only by destructive/leave confirmations; menus keep their own surface.
Future<T?> showConfirmation<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierLabel: '取消确认',
  barrierColor: Colors.black.withValues(
    alpha: .08 + .12 * Palette.of(context).darkness,
  ),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 200),
  transitionBuilder: (_, animation, _, child) => FadeTransition(
    opacity: animation.drive(CurveTween(curve: spaceCurve)),
    child: child,
  ),
  pageBuilder: (c, _, _) => builder(c),
);

class ConfirmationSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const ConfirmationSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) => Glass(
    child: SingleChildScrollView(padding: padding, child: child),
  );
}
