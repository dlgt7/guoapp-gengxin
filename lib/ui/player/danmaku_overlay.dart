import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../danmaku_controller.dart';
import '../../danmaku_models.dart';
import '../../playback_preferences.dart';

const danmakuMaxLanes = 64;
const _danmakuGap = 24.0;
const _danmakuMinLifetimeMs = 4000;
const _danmakuMaxTextRunes = 181;
const _danmakuExtraLaneDelayMs = 1200;

class DanmakuFlight {
  const DanmakuFlight(
    this.item,
    this.text,
    this.lane,
    this.width,
    this.startMs,
    this.lifetimeMs,
  );
  final DanmakuItem item;
  final String text;
  final int lane;
  final double width;
  final int startMs;
  final int lifetimeMs;

  int get endMs => startMs + lifetimeMs;
}

class _DanmakuLane {
  _DanmakuLane(this.startMs, this.width, this.lifetimeMs);
  int startMs;
  double width;
  int lifetimeMs;
}

List<DanmakuFlight> planDanmaku(
  List<DanmakuItem> items, {
  required double width,
  required int rows,
  int? availableRows,
  required double Function(String) measure,
}) {
  if (!width.isFinite || width <= 0 || rows < 1) return const [];
  final laneCount = math
      .min(math.max(rows, availableRows ?? rows), danmakuMaxLanes)
      .toInt();
  final lanes = List<_DanmakuLane?>.filled(laneCount, null);
  final sorted = items.toList()..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  final seen = <String>{};
  final flights = <DanmakuFlight>[];

  // 同轨道前后两条在整个飞行期间都要留出 _danmakuGap：入场时不能压住前一条
  // 尾部，前一条离屏时也不能被更快的新弹幕追上。
  int earliest(int laneIndex, double size, int lifetimeMs, int timeMs) {
    final lane = lanes[laneIndex];
    if (lane == null) return timeMs;
    final entryGap =
        (lane.width + _danmakuGap) * lane.lifetimeMs / (width + lane.width);
    final exitGap =
        lane.lifetimeMs -
        (width - _danmakuGap) * lifetimeMs / (width + size);
    final gap = math.max(entryGap, exitGap).ceil();
    return math.max(timeMs, lane.startMs + gap);
  }

  ({int lane, int startMs}) pick(double size, int lifetimeMs, int timeMs) {
    var primaryStart = earliest(0, size, lifetimeMs, timeMs);
    for (var i = 1; i < rows; i++) {
      final start = earliest(i, size, lifetimeMs, timeMs);
      if (start < primaryStart) primaryStart = start;
    }
    final extraLaneDelay = math
        .max(0, _danmakuExtraLaneDelayMs - (primaryStart - timeMs))
        .toInt();
    var bestLane = 0;
    int? bestScore;
    var bestStart = 0;
    for (var i = 0; i < laneCount; i++) {
      final start = earliest(i, size, lifetimeMs, timeMs);
      final score = start + (i >= rows ? extraLaneDelay : 0);
      if (bestScore == null ||
          score < bestScore ||
          (score == bestScore && start < bestStart)) {
        bestLane = i;
        bestScore = score;
        bestStart = start;
      }
    }
    return (lane: bestLane, startMs: bestStart);
  }

  // 每条有效弹幕都排入队列：暂时没有空位就顺延发射时间，不再丢弃。
  for (final item in sorted) {
    if (item.id.isEmpty ||
        item.text.trim().isEmpty ||
        item.timeMs < 0 ||
        !seen.add(item.id)) {
      continue;
    }
    final runes = item.text.runes;
    final text = String.fromCharCodes(runes.take(_danmakuMaxTextRunes)) +
        (runes.length > _danmakuMaxTextRunes ? '…' : '');
    final size = measure(text).ceilToDouble() + 8;
    final probe = pick(size, danmakuLifetimeMs, item.timeMs);
    final lifetimeMs = (danmakuLifetimeMs - (probe.startMs - item.timeMs))
        .clamp(_danmakuMinLifetimeMs, danmakuLifetimeMs)
        .toInt();
    final chosen = lifetimeMs == danmakuLifetimeMs
        ? probe
        : pick(size, lifetimeMs, item.timeMs);
    final lane = lanes[chosen.lane];
    if (lane == null) {
      lanes[chosen.lane] = _DanmakuLane(chosen.startMs, size, lifetimeMs);
    } else {
      lane
        ..startMs = chosen.startMs
        ..width = size
        ..lifetimeMs = lifetimeMs;
    }
    flights.add(
      DanmakuFlight(item, text, chosen.lane, size, chosen.startMs, lifetimeMs),
    );
  }
  return flights;
}

const _danmakuPalette = [
  Color(0xFFFFFFFF),
  Color(0xFFFF5252),
  Color(0xFFFFEB3B),
  Color(0xFF69F0AE),
  Color(0xFF40C4FF),
  Color(0xFFE040FB),
  Color(0xFFFFAB40),
];

Color _danmakuColor(DanmakuColorMode mode, String id) {
  switch (mode) {
    case DanmakuColorMode.normal:
      return Colors.white;
    case DanmakuColorMode.colorful:
      var hash = 0;
      for (final char in id.codeUnits) {
        hash = (hash * 31 + char) & 0x7FFFFFFF;
      }
      return _danmakuPalette[hash % _danmakuPalette.length];
    case DanmakuColorMode.gradient:
      return Colors.white;
  }
}

class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.controller,
    required this.aspectRatio,
    this.fontScale = 1,
    this.maxRows = 4,
    this.colorMode = DanmakuColorMode.normal,
  });
  final DanmakuController controller;
  final double aspectRatio;
  final double fontScale;
  final int maxRows;
  final DanmakuColorMode colorMode;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  Object? _layout;
  List<DanmakuFlight> _schedule = const [];

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              constraints.maxWidth <= 0 ||
              constraints.maxHeight <= 0) {
            return const SizedBox.shrink();
          }
          final aspect = widget.aspectRatio.isFinite && widget.aspectRatio > 0
              ? widget.aspectRatio
              : 16 / 9;
          final width = math.min(
            constraints.maxWidth,
            constraints.maxHeight * aspect,
          );
          final height = math.min(
            constraints.maxHeight,
            constraints.maxWidth / aspect,
          );
          final fontSize =
              (width < 600 ? 16.0 : 20.0) * widget.fontScale;
          final scaler = MediaQuery.textScalerOf(context);
          final rowHeight = scaler.scale(fontSize) * 1.5;
          final availableRows = ((height * .55 - 8) / rowHeight)
              .floor()
              .clamp(0, danmakuMaxLanes)
              .toInt();
          final rows = math.min(widget.maxRows, availableRows);
          final baseStyle = TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.2,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 3, offset: Offset(1, 1)),
            ],
          );
          return Center(
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    final controller = widget.controller;
                    if (!controller.visible || rows == 0) {
                      return const SizedBox.shrink();
                    }
                    final layout = (
                      controller,
                      controller.dataRevision,
                      width,
                      rows,
                      availableRows,
                      fontSize,
                      scaler,
                    );
                    if (_layout != layout) {
                      _layout = layout;
                      _schedule = planDanmaku(
                        controller.items,
                        width: width,
                        rows: rows,
                        availableRows: availableRows,
                        measure: (text) {
                          final painter = TextPainter(
                            text: TextSpan(text: text, style: baseStyle),
                            textDirection: TextDirection.ltr,
                            textScaler: scaler,
                            maxLines: 1,
                          )..layout();
                          final measured = painter.width;
                          painter.dispose();
                          return measured;
                        },
                      );
                    }
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final flight in _schedule)
                          if (controller.positionMs >= flight.startMs &&
                              controller.positionMs < flight.endMs)
                            Positioned(
                              key: ValueKey('danmaku-item-${flight.item.id}'),
                              left: 0,
                              top: 8 + flight.lane * rowHeight,
                              width: flight.width,
                              height: rowHeight,
                              child: _DanmakuMotion(
                                flight: flight,
                                width: width,
                                positionMs: controller.positionMs,
                                moving: controller.moving,
                                rate: controller.rate,
                                revision: controller.motionRevision,
                                style: baseStyle,
                                scaler: scaler,
                                color: _danmakuColor(
                                  widget.colorMode,
                                  flight.item.id,
                                ),
                                colorMode: widget.colorMode,
                              ),
                            ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _DanmakuMotion extends StatefulWidget {
  const _DanmakuMotion({
    required this.flight,
    required this.width,
    required this.positionMs,
    required this.moving,
    required this.rate,
    required this.revision,
    required this.style,
    required this.scaler,
    required this.color,
    required this.colorMode,
  });
  final DanmakuFlight flight;
  final double width;
  final int positionMs;
  final bool moving;
  final double rate;
  final int revision;
  final TextStyle style;
  final TextScaler scaler;
  final Color color;
  final DanmakuColorMode colorMode;

  @override
  State<_DanmakuMotion> createState() => _DanmakuMotionState();
}

class _DanmakuMotionState extends State<_DanmakuMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_DanmakuMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.width != widget.width ||
        oldWidget.flight.width != widget.flight.width ||
        oldWidget.flight.startMs != widget.flight.startMs ||
        oldWidget.flight.lifetimeMs != widget.flight.lifetimeMs) {
      _sync();
    }
  }

  void _sync() {
    _motion.stop();
    final lifetimeMs = widget.flight.lifetimeMs;
    final elapsed = (widget.positionMs - widget.flight.startMs).clamp(
      0,
      lifetimeMs,
    );
    _motion.value = elapsed / lifetimeMs;
    if (widget.moving && elapsed < lifetimeMs) {
      _motion.animateTo(
        1,
        duration: Duration(
          microseconds: ((lifetimeMs - elapsed) * 1000 / widget.rate)
              .round()
              .clamp(1, 86400000000),
        ),
        curve: Curves.linear,
      );
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style.copyWith(color: widget.color);
    final text = Text(
      widget.flight.text,
      style: style,
      textScaler: widget.scaler,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      softWrap: false,
    );
    return AnimatedBuilder(
      animation: _motion,
      child: RepaintBoundary(
        child: widget.colorMode == DanmakuColorMode.gradient
            ? ShaderMask(
                shaderCallback: (bounds) {
                  final progress = _motion.value;
                  return LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      widget.color,
                      Color.lerp(widget.color, Colors.cyanAccent, progress)!,
                    ],
                  ).createShader(bounds);
                },
                child: text,
              )
            : text,
      ),
      builder: (context, child) => Transform.translate(
        key: ValueKey('danmaku-motion-${widget.flight.item.id}'),
        offset: Offset(
          widget.width - (widget.width + widget.flight.width) * _motion.value,
          0,
        ),
        child: child,
      ),
    );
  }
}
