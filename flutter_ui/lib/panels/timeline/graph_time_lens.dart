// The Retime *Time* (source-position) lens of the graph editor
// (docs/04-RETIMING.md §9.1; K-078; ported from the value-lens behaviour of
// `crates/lumit-ui/src/shell/graph.rs::graph_plot` with `is_retime = true`). It
// draws the source-position-over-comp-time curve — Map segments as the cubic
// through their control points, Rate segments as the integrated position — with
// the boundary source-position reference lines, the boundaries as draggable
// joins, and the playhead with a source-timecode readout.
//
// Boundaries drag horizontally in TIME (the boundary's local time moves, its
// source position kept), committing the `dragBoundary` op — the faithful home of
// that op (docs/04 §9.1). Interior boundaries only (the domain ends are pinned);
// a drag snaps to beat markers and whole frames when the magnet is on
// (graph.rs:1616-1628). The value maths lives in graph_maths.dart.

import 'package:flutter/widgets.dart';

import '../../bridge/bridge.dart';
import '../../state/app_state.dart';
import '../../widgets/controls.dart';
import 'graph_maths.dart';
import 'lane_scale.dart';

/// The Retime source-position lens for a retimed footage [layer].
class GraphTimeLens extends StatefulWidget {
  final AppStateStub app;
  final String compId;
  final BridgeLayer layer;
  final BridgeRetime retime;
  final LaneScale scale;
  final List<int> markers;
  final double fps;

  const GraphTimeLens({
    super.key,
    required this.app,
    required this.compId,
    required this.layer,
    required this.retime,
    required this.scale,
    required this.markers,
    required this.fps,
  });

  @override
  State<GraphTimeLens> createState() => _GraphTimeLensState();
}

class _GraphTimeLensState extends State<GraphTimeLens> {
  int? _dragIndex;
  int _dragFrame = 0;

  AppStateStub get app => widget.app;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    final retime = widget.retime;
    final shown = _dragIndex != null
        ? withBoundaryFrame(retime, _dragIndex!, _dragFrame)
        : retime;

    // The visible comp-frame window (the shared ruler view), so a zoomed graph
    // keeps full curve resolution rather than stretching a whole-comp polyline.
    final lo = widget.scale.viewStartFrame;
    final hi = widget.scale.viewStartFrame +
        widget.scale.trackWidth / (widget.scale.pxPerFrame <= 0 ? 1 : widget.scale.pxPerFrame);
    final samples = sampleSourceCurve(shown, lo, hi);
    final range = sourceRange(sampleSourceCurve(shown, 0, widget.scale.frameCount.toDouble()));
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
        final raw = widget.scale.frameOfX(d.localPosition.dx);
        final snapped = snapGraphFrame(
          raw,
          magnet: app.snapping,
          fps: widget.fps,
          beats: app.snapping ? widget.markers : const [],
          pxPerFrame: widget.scale.pxPerFrame,
          retime: true,
        );
        setState(() =>
            _dragFrame = clampBoundaryFrame(retime, _dragIndex!, snapped));
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
        painter: SourceCurvePainter(
          samples: samples,
          retime: shown,
          scale: widget.scale,
          range: range,
          playheadFrame: playhead,
          dragIndex: _dragIndex,
          surface0: t.surface0,
          surface1: t.surface1,
          hairline: t.hairline,
          hairlineStrong: t.hairlineStrong,
          curveColour: t.curve.first,
          accent: t.accent,
          textMuted: t.textMuted,
          textSecondary: t.textSecondary,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Paints the Time lens: gutter + plot backgrounds, the source-seconds y grid,
/// the boundary source-position reference lines, the source-position curve
/// clipped to the plot, the boundaries as draggable joins (a diamond glyph at
/// each interior boundary's source position) and the playhead with a readout.
class SourceCurvePainter extends CustomPainter {
  final List<SourceSample> samples;
  final BridgeRetime retime;
  final LaneScale scale;
  final (double, double) range;
  final int? playheadFrame;
  final int? dragIndex;
  final Color surface0, surface1, hairline, hairlineStrong;
  final Color curveColour, accent, textMuted, textSecondary;

  SourceCurvePainter({
    required this.samples,
    required this.retime,
    required this.scale,
    required this.range,
    required this.playheadFrame,
    required this.dragIndex,
    required this.surface0,
    required this.surface1,
    required this.hairline,
    required this.hairlineStrong,
    required this.curveColour,
    required this.accent,
    required this.textMuted,
    required this.textSecondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = scale.trackLeft;
    final plotRight = scale.trackLeft + scale.trackWidth;
    final plotRect = Rect.fromLTRB(plotLeft, 0, plotRight, size.height);
    final (lo, hi) = range;
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;

    double yOf(double secs) => size.height - ((secs - lo) / span) * size.height;

    canvas.drawRect(
        Rect.fromLTRB(0, 0, plotLeft, size.height), Paint()..color = surface1);
    canvas.drawRect(plotRect, Paint()..color = surface0);

    // Y-axis: source-seconds gridlines with their labels.
    final grid = Paint()
      ..color = hairline
      ..strokeWidth = 0.5;
    for (final v in axisTickValues(lo, hi)) {
      final y = yOf(v);
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), grid);
      _label(canvas, '${fmtAxisValue(v, span)} s', plotLeft + 4, y - 1);
    }

    // Boundary source-position reference lines (the joins the curve passes
    // through), drawn a touch stronger than the grid.
    final ref = Paint()
      ..color = hairlineStrong
      ..strokeWidth = 0.5;
    for (final p in sourceBoundaryPoints(retime)) {
      final y = yOf(p.secs);
      if (y >= -1 && y <= size.height + 1) {
        canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), ref);
      }
    }

    // The source-position curve.
    if (samples.length >= 2) {
      canvas.save();
      canvas.clipRect(plotRect);
      final path = Path();
      for (var i = 0; i < samples.length; i++) {
        final x = scale.xOfFrame(samples[i].frame);
        final y = yOf(samples[i].secs);
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

    // Boundaries: a vertical guide plus a diamond glyph at the join's source
    // position. Interior (draggable) boundaries read stronger; the dragged one
    // in the accent.
    final draggable = draggableBoundaryIndices(retime).toSet();
    for (var i = 0; i < retime.boundaries.length; i++) {
      final b = retime.boundaries[i];
      final x = scale.xOfFrame(b.tFrame);
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
      final y = yOf(b.sSeconds);
      if (draggable.contains(i)) {
        const d = 4.5;
        final glyph = Path()
          ..moveTo(x, y - d)
          ..lineTo(x + d, y)
          ..lineTo(x, y + d)
          ..lineTo(x - d, y)
          ..close();
        canvas.drawPath(glyph, Paint()..color = isDrag ? accent : hairlineStrong);
      }
    }

    // Playhead + a source-position readout at the top-right.
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
      final secs = sourceSecsAtLocal(retime, localSecsOfFrame(retime, ph.toDouble()));
      _readout(canvas, size, 'src ${secs.toStringAsFixed(2)} s', plotRight - 6);
    }
  }

  void _label(Canvas canvas, String text, double x, double baselineY) {
    final tp = _text(text, textMuted, 9)..layout();
    tp.paint(canvas, Offset(x, baselineY - tp.height));
  }

  void _readout(Canvas canvas, Size size, String text, double right) {
    final tp = _text(text, textSecondary, 11)..layout();
    tp.paint(canvas, Offset(right - tp.width, 4));
  }

  TextPainter _text(String text, Color colour, double size) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: colour,
            fontSize: size,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      );

  @override
  bool shouldRepaint(SourceCurvePainter old) =>
      old.samples != samples ||
      old.range != range ||
      old.playheadFrame != playheadFrame ||
      old.dragIndex != dragIndex ||
      old.retime != retime;
}
