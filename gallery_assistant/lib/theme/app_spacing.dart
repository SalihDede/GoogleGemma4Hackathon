import 'package:flutter/widgets.dart';

abstract class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

abstract class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28; // M3 dialog/sheet
  static const double full = 999;
}

abstract class AppPadding {
  static const all4 = EdgeInsets.all(AppSpacing.xs);
  static const all8 = EdgeInsets.all(AppSpacing.sm);
  static const all12 = EdgeInsets.all(AppSpacing.md);
  static const all16 = EdgeInsets.all(AppSpacing.lg);
  static const all24 = EdgeInsets.all(AppSpacing.xl);

  static const h16v8 = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.sm,
  );
  static const h16v12 = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.md,
  );
  static const h24v16 = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl,
    vertical: AppSpacing.lg,
  );
}
