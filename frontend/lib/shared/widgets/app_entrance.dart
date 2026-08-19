import 'package:flutter/material.dart';

import '../../app/theme/app_motion.dart';

/// One-shot fade + slide-up entrance. Runs when the widget first mounts;
/// rebuilds (e.g. toggling a like) do not replay it.
class AppEntrance extends StatefulWidget {
  const AppEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 12,
    this.duration = AppMotion.normal,
  });

  final Widget child;
  final Duration delay;
  final double offset;
  final Duration duration;

  @override
  State<AppEntrance> createState() => _AppEntranceState();
}

class _AppEntranceState extends State<AppEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: Duration.zero,
    );
    final curved =
        CurvedAnimation(parent: _controller, curve: AppMotion.entrance);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _slide =
        Tween<double>(begin: widget.offset, end: 0).animate(curved);
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.translate(
          offset: Offset(0, _slide.value),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Staggers a list of children in with a shared entrance curve.
class AppStagger extends StatelessWidget {
  const AppStagger({
    super.key,
    required this.children,
    this.interval = const Duration(milliseconds: 40),
    this.offset = 12,
  });

  final List<Widget> children;
  final Duration interval;
  final double offset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++)
          AppEntrance(
            delay: interval * i,
            offset: offset,
            child: children[i],
          ),
      ],
    );
  }
}
