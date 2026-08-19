import 'package:flutter/material.dart';

import '../../app/theme/app_motion.dart';

/// Wraps a child so it scales down on press and bounces back on release.
/// Use on cards, buttons, or any tappable widget for tactile feedback.
class TapScale extends StatefulWidget {
  const TapScale({
    super.key,
    required this.onTap,
    required this.child,
    this.scaleDown = 0.95,
  });

  final VoidCallback? onTap;
  final Widget child;
  final double scaleDown;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.fast,
      reverseDuration: const Duration(milliseconds: 300),
    );
    _scale = Tween<double>(begin: 1, end: widget.scaleDown).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => _controller.forward() : null,
      onTapUp: widget.onTap != null
          ? (_) {
              _controller.reverse();
              widget.onTap?.call();
            }
          : null,
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: _scale.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
