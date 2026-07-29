import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';

/// Soft shimmer block used by skeleton layouts.
class PulseLoadingBlock extends StatefulWidget {
  const PulseLoadingBlock({
    super.key,
    this.height = 64,
    this.width,
    this.borderRadius,
  });

  final double height;
  final double? width;
  final BorderRadius? borderRadius;

  @override
  State<PulseLoadingBlock> createState() => _PulseLoadingBlockState();
}

class _PulseLoadingBlockState extends State<PulseLoadingBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width ?? double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ??
                BorderRadius.circular(PulseTokens.radiusCard),
            gradient: LinearGradient(
              begin: Alignment(-1.2 + (t * 2.8), 0),
              end: Alignment(-0.2 + (t * 2.8), 0),
              colors: [
                PulseTokens.surface.withValues(alpha: 0.55),
                PulseTokens.surfaceHover.withValues(alpha: 0.75),
                PulseTokens.surface.withValues(alpha: 0.55),
              ],
            ),
            border: Border.all(color: PulseTokens.strokeSubtle),
          ),
        );
      },
    );
  }
}

class PulseInlineSpinner extends StatelessWidget {
  const PulseInlineSpinner({super.key, this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: color ?? PulseTokens.accent,
      ),
    );
  }
}

/// Timeline-shaped skeleton used while the service connects or list settles.
class TimelineSkeleton extends StatelessWidget {
  const TimelineSkeleton({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        PulseTokens.pagePadX,
        12,
        PulseTokens.pagePadX,
        PulseTokens.pagePadBottom,
      ),
      itemCount: rows,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 22, right: 14),
              child: PulseLoadingBlock(
                width: 10,
                height: 10,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Expanded(
              child: PulseLoadingBlock(
                height: index == 0 ? 88 : 76,
              ),
            ),
          ],
        );
      },
    );
  }
}
