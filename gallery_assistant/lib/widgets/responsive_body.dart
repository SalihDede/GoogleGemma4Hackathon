import 'package:flutter/material.dart';

import '../theme/breakpoints.dart';

/// İçeriği geniş ekranlarda ortalar ve okunabilir bir maxWidth ile sınırlar.
/// Telefonlarda hiçbir kısıtlama getirmez (full width).
class ResponsiveBody extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final Alignment alignment;

  const ResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    final mw = maxWidth ?? context.readableContentMaxWidth;
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: mw),
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
  }
}

/// Modal/onboarding gibi dar konteynerler için ortalanmış kart genişliği.
class ResponsiveCardBody extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ResponsiveCardBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedPadding = padding.resolve(Directionality.of(context));
        final minHeight = (constraints.maxHeight - resolvedPadding.vertical)
            .clamp(0.0, double.infinity)
            .toDouble();

        return SingleChildScrollView(
          padding: resolvedPadding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: context.cardMaxWidth),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
