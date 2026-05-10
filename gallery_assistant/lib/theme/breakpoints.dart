import 'package:flutter/widgets.dart';

/// Material 3 Window Size Class.
/// https://m3.material.io/foundations/layout/applying-layout/window-size-classes
enum WindowSize {
  /// Telefon dikey, < 600 dp
  compact,

  /// Telefon yatay / küçük tablet, 600–840 dp
  medium,

  /// Tablet / foldable açık / desktop, ≥ 840 dp
  expanded,
}

/// Cihaz ve layout sorgu uzantıları. `context.windowSize`, `context.isCompact`
/// gibi tek satırlık erişim sağlar.
extension AppContextX on BuildContext {
  WindowSize get windowSize {
    final w = MediaQuery.sizeOf(this).width;
    if (w < 600) return WindowSize.compact;
    if (w < 840) return WindowSize.medium;
    return WindowSize.expanded;
  }

  bool get isCompact => windowSize == WindowSize.compact;
  bool get isMedium => windowSize == WindowSize.medium;
  bool get isExpanded => windowSize == WindowSize.expanded;
  bool get isAtLeastMedium => !isCompact;

  /// Sohbet/okuma içeriği için maksimum içerik genişliği.
  /// Geniş ekranlarda satır uzunluğunu okunabilir tutar.
  double get readableContentMaxWidth => switch (windowSize) {
        WindowSize.compact => double.infinity,
        WindowSize.medium => 720,
        WindowSize.expanded => 800,
      };

  /// Kart/dialog gibi konteynerler için max genişlik.
  double get cardMaxWidth => switch (windowSize) {
        WindowSize.compact => double.infinity,
        WindowSize.medium => 480,
        WindowSize.expanded => 520,
      };
}
