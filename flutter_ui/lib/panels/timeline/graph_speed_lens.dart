// The Retime *speed* lens of the graph editor (docs/04-RETIMING.md §9.2; ported
// from `crates/lumit-ui/src/shell/graph.rs::graph_plot_retime`). For the selected
// footage layer it draws the piecewise speed-over-time curve, a sub-header with
// the Lin/Slow/Fast/Smth/Shrp ramp presets and the →Rate button, reference
// lines/grid, the playhead with a speed readout, and boundaries as draggable
// verticals (each commits `dragBoundary`, which moves a boundary's local time —
// the true home of that op, docs/04 §9.1). The maths lives in graph_maths.dart;
// this file is the widget composition and the boundary-drag interaction.
//
// The lens picker and the Retime enable/Vegas controls live in the shared
// GraphEditor header (graph_editor.dart); this lens carries only its own
// ramp/→Rate sub-header.

import 'package:flutter/widgets.dart';

import '../../bridge/bridge.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../widgets/controls.dart';
import 'graph_maths.dart';
import 'lane_scale.dart';

/// The Retime speed-% lens for a retimed footage [layer].
class GraphSpeedLens extends StatefulWidget {
  final AppStateStub app;
  final String compId;
  final BridgeLayer layer;
  final BridgeRetime retime;
  final LaneScale scale;

  const GraphSpeedLens({
    super.key,
    required this.app,
    required this.compId,
    required this.layer,
    required this.retime,
    required this.scale,
  });

  @override
  State<GraphSpeedLens> createState() => _GraphSpeedLensState();
}

class _GraphSpeedLensState extends State<GraphSpeedLens> {
  /// The interior boundary being dragged, and its live target comp frame.
  int? _dragIndex;
  int _dragFrame = 0;

  AppStateStub get app => widget.app;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Column(
      children: [
        _subHeader(t),
        Expanded(child: _plot(t)),
      ],
    );
  }

  /// The speed lens's own sub-header: the ramp presets, the →Rate button and the
  /// playhead speed readout, aligned under the ruler by a left gutter the width
  /// of the outline column.
  Widget _subHeader(LumitTheme t) {
    final frame = app.previewFrame;
    final pct = speedPctAtFrame(widget.retime, frame);
    final inDomain = segmentIndexAtFrame(widget.retime, frame) != null;
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          SizedBox(
            width: widget.scale.trackLeft,
            child: Container(
              color: t.surface1,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.centerLeft,
              child: Text('Ramp', style: t.small.copyWith(color: t.textMuted)),
            ),
          ),
          Expanded(
            child: Container(
              color: t.surface1,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final label in presetLabels)
                            Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: LumitTooltip(
                                message:
                                    'Ease the speed ramp under the playhead',
                                child: HouseButton(
                                  small: true,
                                  onPressed: inDomain
                                      ? () => app.setSegmentPreset(widget.compId,
                                          widget.layer.id, frame, label)
                                      : null,
                                  child: Text(label, style: t.small),
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          LumitTooltip(
                            message:
                                'Convert the mapped segment under the playhead to a constant-ease rate',
                            child: HouseButton(
                              small: true,
                              onPressed: inDomain
                                  ? () => app.convertSegmentToRate(
                                      widget.compId, widget.layer.id, frame)
                                  : null,
                              child: Text('→Rate', style: t.small),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${pct.toStringAsFixed(1)}%',
                      style: t.small.copyWith(color: t.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The plot: the sampled speed curve, reference lines, boundaries and the
  /// playhead, with a boundary-drag gesture over the lane.
  Widget _plot(LumitTheme t) {
    final retime = widget.retime;
    // While a boundary drag is in flight, sample a preview store whose join has
    // moved, so the curve follows the drag live before it commits.
    final shown = _dragIndex != null
        ? withBoundaryFrame(retime, _dragIndex!, _dragFrame)
        : retime;
    final samples = sampleSpeedCurve(shown);
    final range = speedRange(samples);
    final playhead = app.previewFrame;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (d) {
        final i = boundaryAtX(shown, d.localPosition.dx, widget.scale.xOfFrame);
        if (i != null) {
          setState(() {
            _dragIndex = i;
            _dragFrame = retime.boundaries[i].tFrame;
          });
        }
      },
      onHorizontalDragUpdate: (d) {
        if (_dragIndex == null) return;
        final f = widget.scale.frameOfX(d.localPosition.dx).round();
        setState(() => _dragFrame = clampBoundaryFrame(retime, _dragIndex!, f));
      },
      onHorizontalDragEnd: (_) {
        final i = _dragIndex;
        if (i != null) {
          app.dragBoundary(widget.compId, widget.layer.id, i, _dragFrame);
        }
        setState(() {
          _dragIndex = null;
          _dragFrame = 0;
        });
      },
      child: CustomPaint(
        painter: SpeedCurvePainter(
          samples: samples,
          retime: shown,
          scale: widget.scale,
          range: range,
          playheadFrame: playhead,
          activeSegment: segmentIndexAtFrame(retime, playhead),
          dragIndex: _dragIndex,
          surface0: t.surface0,
          surface1: t.surface1,
          hairline: t.hairline,
          hairlineStrong: t.hairlineStrong,
          curveColour: t.curve.length > 1 ? t.curve[1] : t.curve.first,
          accent: t.accent,
          textMuted: t.textMuted,
          accentBand: t.accent.withValues(alpha: 0.10),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Paints the speed lens: gutter + plot backgrounds, active-segment shading, the
/// per-cent y grid with the 0%/100% reference lines, the speed curve clipped to
/// the plot, the boundaries (draggable ones stronger, the dragged one accent
/// with a square top handle) and the playhead.
class SpeedCurvePainter extends CustomPainter {
  final List<SpeedSample> samples;
  final BridgeRetime retime;
  final LaneScale scale;
  final (double, double) range;
  final int? playheadFrame;
  final int? activeSegment;
  final int? dragIndex;
  final Color surface0, surface1, hairline, hairlineStrong;
  final Color curveColour, accent, textMuted, accentBand;

  SpeedCurvePainter({
    required this.samples,
    required this.retime,
    required this.scale,
    required this.range,
    required this.playheadFrame,
    required this.activeSegment,
    required this.dragIndex,
    required this.surface0,
    required this.surface1,
    required this.hairline,
    required this.hairlineStrong,
    required this.curveColour,
    required this.accent,
    required this.textMuted,
    required this.accentBand,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = scale.trackLeft;
    final plotRight = scale.trackLeft + scale.trackWidth;
    final plotRect = Rect.fromLTRB(plotLeft, 0, plotRight, size.height);
    final (lo, hi) = range;
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;

    double yOf(double pct) => size.height - ((pct - lo) / span) * size.height;

    canvas.drawRect(
        Rect.fromLTRB(0, 0, plotLeft, size.height), Paint()..color = surface1);
    canvas.drawRect(plotRect, Paint()..color = surface0);

    final active = activeSegment;
    if (active != null && active + 1 < retime.boundaries.length) {
      final x0 = scale.xOfFrame(retime.boundaries[active].tFrame);
      final x1 = scale.xOfFrame(retime.boundaries[active + 1].tFrame);
      final l = x0.clamp(plotLeft, plotRight);
      final r = x1.clamp(plotLeft, plotRight);
      if (r > l) {
        canvas.drawRect(
            Rect.fromLTRB(l, 0, r, size.height), Paint()..color = accentBand);
      }
    }

    final grid = Paint()
      ..color = hairline
      ..strokeWidth = 0.5;
    for (var i = 1; i <= 4; i++) {
      final frac = i / 5.0;
      final y = size.height - frac * size.height;
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), grid);
      final v = lo + frac * span;
      _label(canvas, '${v.toStringAsFixed(0)}%', plotLeft + 4, y - 1);
    }
    final refPaint = Paint()
      ..color = hairlineStrong
      ..strokeWidth = 0.5;
    for (final v in const [0.0, 100.0]) {
      if (v >= lo && v <= hi) {
        final y = yOf(v);
        canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), refPaint);
      }
    }

    if (samples.length >= 2) {
      canvas.save();
      canvas.clipRect(plotRect);
      final path = Path();
      for (var i = 0; i < samples.length; i++) {
        final x = scale.xOfFrame(samples[i].frame);
        final y = yOf(samples[i].pct);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = curveColour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.restore();
    }

    final draggable = draggableBoundaryIndices(retime).toSet();
    for (var i = 0; i < retime.boundaries.length; i++) {
      final x = scale.xOfFrame(retime.boundaries[i].tFrame);
      if (x < plotLeft - 0.5 || x > plotRight + 0.5) continue;
      final isDrag = i == dragIndex;
      final colour = isDrag
          ? accent
          : draggable.contains(i)
              ? hairlineStrong
              : hairline;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = colour
          ..strokeWidth = isDrag ? 1.5 : 1.0,
      );
      if (draggable.contains(i)) {
        canvas.drawRect(
          Rect.fromCenter(center: Offset(x, 5), width: 7, height: 7),
          Paint()..color = colour,
        );
      }
    }

    final ph = playheadFrame;
    if (ph != null) {
      final x = scale.xOfFrame(ph);
      if (x >= plotLeft - 0.5 && x <= plotRight + 0.5) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = accent
            ..strokeWidth = 1.0,
        );
      }
    }
  }

  void _label(Canvas canvas, String text, double x, double baselineY) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textMuted,
          fontSize: 9,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x, baselineY - tp.height));
  }

  @override
  bool shouldRepaint(SpeedCurvePainter old) =>
      old.samples != samples ||
      old.range != range ||
      old.playheadFrame != playheadFrame ||
      old.activeSegment != activeSegment ||
      old.dragIndex != dragIndex ||
      old.retime != retime;
}
