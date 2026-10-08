// Small building blocks shared by every screen.
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A rounded card surface.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(S.lg), this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return Material(
      color: C.surface,
      borderRadius: BorderRadius.circular(R.lg),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(S.xs, S.xl, S.xs, S.md),
        child: Row(
          children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ?trailing,
          ],
        ),
      );
}

/// Label · value · optional sub-line (stat tile contract).
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.unit, this.sub, this.icon});
  final String label;
  final String value;
  final String? unit;
  final Widget? sub;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: C.text3), const SizedBox(width: 6)],
            Flexible(child: Text(label, style: t.labelMedium?.copyWith(color: C.text2), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: S.sm),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: value, style: t.headlineSmall),
              if (unit != null) TextSpan(text: ' $unit', style: t.bodyMedium?.copyWith(color: C.text2)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (sub != null) ...[const SizedBox(height: S.xs), sub!],
        ],
      ),
    );
  }
}

/// "+12 % vs yesterday": arrow + text, coloured by whether the change is good.
class DeltaText extends StatelessWidget {
  const DeltaText({super.key, required this.fraction, required this.versus});
  final double fraction; // +0.12 = 12 % more
  final String versus;

  @override
  Widget build(BuildContext context) {
    final up = fraction > 0.005;
    final down = fraction < -0.005;
    // using LESS energy is good
    final color = up ? C.serious : (down ? C.goodText : C.text2);
    final icon = up ? Icons.arrow_upward_rounded : (down ? Icons.arrow_downward_rounded : Icons.remove_rounded);
    final pct = (fraction.abs() * 100).round();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 2),
      Flexible(
        child: Text(
          up || down ? '$pct % vs $versus' : 'same as $versus',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: C.text2),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

enum PillKind { live, stale, offline, info }

/// Status chip: icon + word, never colour alone.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.kind, required this.label});
  final PillKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (Color c, IconData? icon) = switch (kind) {
      PillKind.live => (C.goodText, null),
      PillKind.stale => (C.warning, Icons.schedule_rounded),
      PillKind.offline => (C.criticalText, Icons.power_off_rounded),
      PillKind.info => (C.text2, Icons.info_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (kind == PillKind.live) _PulseDot(color: c) else Icon(icon, size: 14, color: c),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: C.text)),
      ]),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});
  final Color color;
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 10,
        height: 10,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Stack(alignment: Alignment.center, children: [
            Container(
              width: 4 + 6 * _c.value,
              height: 4 + 6 * _c.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.45 * (1 - _c.value)),
              ),
            ),
            Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ]),
        ),
      );
}

/// Progress through the cheap price block of the bill.
/// Teal while inside the block, amber for the part above it, a tick for the
/// projected end-of-period usage. Labels carry the meaning, not just colour.
class TierMeter extends StatelessWidget {
  const TierMeter({super.key, required this.used, required this.limit, this.projected});
  final double used;
  final double limit; // end of the cheap block
  final double? projected;

  @override
  Widget build(BuildContext context) {
    final scale = [used, limit * 1.25, if (projected != null) projected! * 1.05].reduce((a, b) => a > b ? a : b);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      double x(double v) => (v / scale).clamp(0, 1) * w;
      final inBlock = x(used.clamp(0, limit));
      final over = used > limit ? x(used) - x(limit) : 0.0;
      return SizedBox(
        height: 28,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            right: 0,
            top: 7,
            child: Container(
              height: 8,
              decoration: BoxDecoration(color: const Color(0xFF173A32), borderRadius: BorderRadius.circular(99)),
            ),
          ),
          Positioned(
            left: 0,
            top: 7,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              width: inBlock,
              height: 8,
              decoration: BoxDecoration(color: C.series, borderRadius: BorderRadius.circular(99)),
            ),
          ),
          if (over > 0)
            Positioned(
              left: x(limit) + 2, // 2px surface gap between the two fills
              top: 7,
              child: Container(
                width: (over - 2).clamp(0, w),
                height: 8,
                decoration: BoxDecoration(color: C.warning, borderRadius: BorderRadius.circular(99)),
              ),
            ),
          // end of the cheap block
          Positioned(
            left: x(limit) - 1,
            top: 2,
            child: Container(width: 2, height: 18, color: C.text2),
          ),
          // where this bill is heading at the current pace
          if (projected != null && projected! > used)
            Positioned(
              left: x(projected!) - 5,
              top: 19,
              child: const CustomPaint(size: Size(10, 7), painter: _UpTriangle(C.text2)),
            ),
        ]),
      );
    });
  }
}

class _UpTriangle extends CustomPainter {
  const _UpTriangle(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(s.width / 2, 0)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_UpTriangle o) => o.color != color;
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(S.xxl),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: C.brand.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 34, color: C.brand),
        ),
        const SizedBox(height: S.lg),
        Text(title, style: t.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: S.sm),
        Text(body, style: t.bodyMedium?.copyWith(color: C.text2), textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: S.xl), action!],
      ]),
    );
  }
}

/// Placeholder while a card loads.
class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key, this.height = 120});
  final double height;

  @override
  Widget build(BuildContext context) => Panel(
        child: SizedBox(
          height: height - 2 * S.lg,
          child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Panel(
        child: Row(children: [
          const Icon(Icons.cloud_off_rounded, color: C.criticalText),
          const SizedBox(width: S.md),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
}

/// The round bolt mark from the front label.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF242A30),
          border: Border.all(color: C.brand, width: size * 0.06),
          boxShadow: [BoxShadow(color: C.brand.withValues(alpha: 0.25), blurRadius: size * 0.5)],
        ),
        child: Icon(Icons.bolt_rounded, color: C.brand, size: size * 0.6),
      );
}
