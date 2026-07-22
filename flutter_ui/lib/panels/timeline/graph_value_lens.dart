// The transform *value* graph lens (K-078; ported from
// `crates/lumit-ui/src/shell/graph.rs::graph_plot`). For the selected layer's
// chosen (or first animated) transform property it draws the animation curve
// exactly as the engine evaluates it — piecewise per key-pair honouring each
// side's interpolation: Hold steps, Linear lines, Bezier segments sampled
// densely from the real cubic (never a straight line between keys). Keys draw
// with the interp-coded glyphs (key_glyph.dart) and a selected key rings and
// shows its draggable bezier tangent handles. A key drags in time+value; a
// handle drag rewrites the key's bezier speed/influence; a double-click adds a
// key; a right-click sets its interpolation or deletes it.
//
// The commits use the granular bridge keyframe ops (the Flutter bridge exposes
// no whole-animation setter): a value-only key drag is one `addKeyframe`; a
// time+value drag is `shiftKeyframes` (time, interp preserved) then `addKeyframe`
// (value); a handle drag is one `setKeyframeInterp`; a double-click one
// `addKeyframe`; a delete one `removeKeyframe`. Interp/glyph coding, the bezier
// sampling, the handle geometry, the auto-fit and the snapping are all pure in
// graph_maths.dart and unit-tested.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../bridge/bridge.dart';
import '../../state/app_state.dart';
import '../../widgets/controls.dart';
import 'graph_maths.dart';
import 'key_glyph.dart';
import 'lane_scale.dart';

/// The transform property names a layer can graph (its transform read-back's
/// keys, in the snapshot's own order), or empty when the layer carries no
/// transform (an older engine).
List<String> graphablePropNames(BridgeLayer layer) =>
    layer.transform?.properties.keys.toList() ?? const [];

/// The property the value lens should graph: the caller's [preferred] when it is
/// still a property of [layer], else the layer's first animated property, else
/// its first property, else `position_x` — mirroring egui's `graph_prop`
/// (`unwrap_or(PositionX)`, following the last-touched channel).
String resolveGraphProp(BridgeLayer layer, String? preferred) {
  final names = graphablePropNames(layer);
  if (preferred != null && names.contains(preferred)) return preferred;
  for (final n in names) {
    if (layer.transform?[n]?.animated ?? false) return n;
  }
  return names.isNotEmpty ? names.first : 'position_x';
}

/// The value graph for one transform [prop] of [layer].
class GraphValueLens extends StatefulWidget {
  final AppStateStub app;
  final String compId;
  final BridgeLayer layer;
  final String prop;
  final LaneScale scale;
  final double fps;

  const GraphValueLens({
    super.key,
    required this.app,
    required this.compId,
    required this.layer,
    required this.prop,
    required this.scale,
    required this.fps,
  });

  @override
  State<GraphValueLens> createState() => _GraphValueLensState();
}

/// A live key drag: the key [index], its provisional comp [frame] and [value].
typedef _KeyDrag = ({int index, double frame, double value});

/// A live tangent-handle drag: the key [index], which [isOut] side, and the
/// provisional [speed]/[influence] it maps to.
typedef _HandleDrag = ({int index, bool isOut, double speed, double influence});

class _GraphValueLensState extends State<GraphValueLens> {
  int? _selected;
  _KeyDrag? _keyDrag;
  _HandleDrag? _handleDrag;

  // Layout captured each build, read by the gesture callbacks between builds.
  List<BridgeKeyframe> _keys = const [];
  double _staticValue = 0;
  (double, double) _range = (0, 1);
  (double, double)? _frozenRange; // held still during a handle drag
  double _plotH = 1;

  AppStateStub get app => widget.app;
  LaneScale get scale => widget.scale;
  double get fps => widget.fps <= 0 ? 1.0 : widget.fps;

  BridgeTransformProperty? get _property => widget.layer.transform?[widget.prop];

  double _yOf(double v, (double, double) range) {
    final (lo, hi) = range;
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    return _plotH - ((v - lo) / span) * _plotH;
  }

  double _valueOf(double y, (double, double) range) {
    final (lo, hi) = range;
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    return lo + ((_plotH - y) / _plotH).clamp(0.0, 1.0) * span;
  }

  /// The keys with the active key drag applied (provisional, sorted for the
  /// curve). Handle drags leave the key positions untouched.
  List<BridgeKeyframe> _shownKeys() {
    final drag = _keyDrag;
    if (drag == null) return _keys;
    final out = [
      for (var i = 0; i < _keys.length; i++)
        if (i == drag.index)
          BridgeKeyframe(
            frame: drag.frame.round(),
            value: drag.value,
            interpIn: _keys[i].interpIn,
            interpOut: _keys[i].interpOut,
            bezierIn: _keys[i].bezierIn,
            bezierOut: _keys[i].bezierOut,
          )
        else
          _keys[i],
    ]..sort((a, b) => a.frame.compareTo(b.frame));
    return out;
  }

  // --- hit testing --------------------------------------------------------

  /// The key index whose glyph is within 8 px of [local], or null.
  int? _keyAt(Offset local) {
    final range = _frozenRange ?? _range;
    for (var i = 0; i < _keys.length; i++) {
      final k = _keys[i];
      final p = Offset(scale.xOfFrame(k.frame), _yOf(k.value, range));
      if ((p - local).distance <= 8) return i;
    }
    return null;
  }

  /// The selected key's tangent-handle nearest [local] (within 8 px), or null.
  _HandleDrag? _handleAt(Offset local) {
    final sel = _selected;
    if (sel == null || sel >= _keys.length) return null;
    final range = _frozenRange ?? _range;
    final k = _keys[sel];
    for (final isOut in const [true, false]) {
      final interp = isOut ? k.interpOut : k.interpIn;
      final bez = isOut ? k.bezierOut : k.bezierIn;
      if (interp != 'Bezier' || bez == null) continue;
      final nb = isOut
          ? (sel + 1 < _keys.length ? _keys[sel + 1].frame : null)
          : (sel > 0 ? _keys[sel - 1].frame : null);
      if (nb == null) continue;
      final e = handleEndpoint(
        keyFrame: k.frame.toDouble(),
        keyValue: k.value,
        neighbourFrame: nb.toDouble(),
        isOut: isOut,
        speed: bez.speed,
        influence: bez.influence,
        fps: fps,
      );
      final p = Offset(scale.xOfFrame(e.frame), _yOf(e.value, range));
      if ((p - local).distance <= 8) {
        return (index: sel, isOut: isOut, speed: bez.speed, influence: bez.influence);
      }
    }
    return null;
  }

  int? _neighbourFrame(int index, bool isOut) => isOut
      ? (index + 1 < _keys.length ? _keys[index + 1].frame : null)
      : (index > 0 ? _keys[index - 1].frame : null);

  // --- gestures -----------------------------------------------------------

  void _onTapUp(TapUpDetails d) {
    if (d.localPosition.dx < scale.trackLeft) return;
    final hit = _keyAt(d.localPosition);
    setState(() => _selected = hit);
  }

  void _onDoubleTapDown(TapDownDetails d) {
    if (d.localPosition.dx < scale.trackLeft) return;
    final frame = snapGraphFrame(
      scale.frameOfX(d.localPosition.dx),
      magnet: app.snapping,
      fps: fps,
      beats: const [],
      pxPerFrame: scale.pxPerFrame,
      retime: false,
    ).clamp(0, scale.frameCount);
    final value = _valueOf(d.localPosition.dy, _frozenRange ?? _range);
    app.addKeyframe(widget.compId, widget.layer.id, widget.prop, frame, value);
  }

  void _onPanStart(DragStartDetails d) {
    final handle = _handleAt(d.localPosition);
    if (handle != null) {
      _frozenRange = _range; // the axis holds still while a handle drags
      setState(() => _handleDrag = handle);
      return;
    }
    final key = _keyAt(d.localPosition);
    if (key != null) {
      setState(() {
        _selected = key;
        _keyDrag = (
          index: key,
          frame: _keys[key].frame.toDouble(),
          value: _keys[key].value,
        );
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final range = _frozenRange ?? _range;
    if (_handleDrag != null) {
      final hd = _handleDrag!;
      final nb = _neighbourFrame(hd.index, hd.isOut);
      if (nb == null) return;
      final k = _keys[hd.index];
      final mapped = handleFromDrag(
        keyFrame: k.frame.toDouble(),
        keyValue: k.value,
        neighbourFrame: nb.toDouble(),
        isOut: hd.isOut,
        dragFrame: scale.frameOfX(d.localPosition.dx),
        dragValue: _valueOf(d.localPosition.dy, range),
        fps: fps,
      );
      setState(() => _handleDrag = (
            index: hd.index,
            isOut: hd.isOut,
            speed: mapped.speed,
            influence: mapped.influence,
          ));
      return;
    }
    if (_keyDrag != null) {
      final kd = _keyDrag!;
      final frame = snapGraphFrame(
        scale.frameOfX(d.localPosition.dx),
        magnet: app.snapping,
        fps: fps,
        beats: const [],
        pxPerFrame: scale.pxPerFrame,
        retime: false,
      ).clamp(0, scale.frameCount).toDouble();
      setState(() => _keyDrag = (
            index: kd.index,
            frame: frame,
            value: _valueOf(d.localPosition.dy, range),
          ));
    }
  }

  void _onPanEnd(DragEndDetails d) {
    final hd = _handleDrag;
    if (hd != null) {
      _commitHandle(hd);
      setState(() {
        _handleDrag = null;
        _frozenRange = null;
      });
      return;
    }
    final kd = _keyDrag;
    if (kd != null) {
      _commitKeyDrag(kd);
      setState(() => _keyDrag = null);
    }
  }

  /// Commit a key drag: `shiftKeyframes` for a time move (interp + value
  /// preserved), then `addKeyframe` for the value at the landed frame (interp
  /// preserved by the engine's half-frame replace). A pure value move is the
  /// single `addKeyframe`; a no-op move commits nothing.
  void _commitKeyDrag(_KeyDrag kd) {
    if (kd.index >= _keys.length) return;
    final old = _keys[kd.index];
    final newFrame = kd.frame.round();
    final movedTime = newFrame != old.frame;
    final movedValue = (kd.value - old.value).abs() > 1e-9;
    if (!movedTime && !movedValue) return;
    if (movedTime) {
      app.shiftKeyframes(widget.compId, widget.layer.id, widget.prop,
          [old.frame], newFrame - old.frame);
    }
    if (movedValue || movedTime) {
      app.addKeyframe(
          widget.compId, widget.layer.id, widget.prop, newFrame, kd.value);
    }
    setState(() => _selected = kd.index);
  }

  /// Commit a tangent-handle drag as one `setKeyframeInterp`: the dragged side
  /// takes the new bezier `(speed, influence)`; a unified (smooth) key mirrors
  /// the slope onto the partner side (keeping its own reach), else the partner
  /// keeps its current interpolation.
  void _commitHandle(_HandleDrag hd) {
    if (hd.index >= _keys.length) return;
    final k = _keys[hd.index];
    final draggedName = 'Bezier';
    final partnerInterp = hd.isOut ? k.interpIn : k.interpOut;
    final partnerBez = hd.isOut ? k.bezierIn : k.bezierOut;
    // A smooth key (both sides bezier, equal slope) mirrors the drag.
    final unified = k.interpIn == 'Bezier' &&
        k.interpOut == 'Bezier' &&
        k.bezierIn != null &&
        k.bezierOut != null &&
        (k.bezierIn!.speed - k.bezierOut!.speed).abs() < 1e-6;
    final String partnerName;
    final double partnerSpeed, partnerInfluence;
    if (unified) {
      partnerName = 'Bezier';
      partnerSpeed = hd.speed;
      partnerInfluence = sideInfluence(partnerInterp, partnerBez);
    } else {
      partnerName = partnerInterp;
      partnerSpeed = partnerBez?.speed ?? 0;
      partnerInfluence = partnerBez?.influence ?? kEaseThird;
    }
    app.setKeyframeInterp(
      widget.compId,
      widget.layer.id,
      widget.prop,
      k.frame,
      hd.isOut ? partnerName : draggedName,
      hd.isOut ? draggedName : partnerName,
      speedIn: hd.isOut ? partnerSpeed : hd.speed,
      influenceIn: hd.isOut ? partnerInfluence : hd.influence,
      speedOut: hd.isOut ? hd.speed : partnerSpeed,
      influenceOut: hd.isOut ? hd.influence : partnerInfluence,
    );
  }

  /// The graph-key right-click menu (graph.rs's context menu): set the key's
  /// interpolation or delete it, committed as one op.
  void _openKeyMenu(int index, Offset global) {
    if (index >= _keys.length) return;
    final k = _keys[index];
    showLumitPopup<void>(
      context: context,
      position: global,
      builder: (close) => FloatSurface(
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MenuRow(
                onPressed: () {
                  close(null);
                  _setInterp(k.frame, 'Bezier', speed: 0, influence: kEaseThird);
                },
                child: const Text('Easy ease'),
              ),
              MenuRow(
                onPressed: () {
                  close(null);
                  _setInterp(k.frame, 'Linear');
                },
                child: const Text('Linear'),
              ),
              MenuRow(
                onPressed: () {
                  close(null);
                  _setInterp(k.frame, 'Hold');
                },
                child: const Text('Hold'),
              ),
              MenuRow(
                onPressed: () {
                  close(null);
                  app.removeKeyframe(
                      widget.compId, widget.layer.id, widget.prop, k.frame);
                  setState(() => _selected = null);
                },
                child: const Text('Delete key'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setInterp(int frame, String name,
      {double speed = 0, double influence = kEaseThird}) {
    app.setKeyframeInterp(
      widget.compId,
      widget.layer.id,
      widget.prop,
      frame,
      name,
      name,
      speedIn: speed,
      influenceIn: influence,
      speedOut: speed,
      influenceOut: influence,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    final prop = _property;
    _keys = prop?.keys ?? const [];
    _staticValue = prop?.value ?? 0;

    // The x window of the shared ruler view.
    final frameLo = scale.viewStartFrame;
    final frameHi = scale.viewStartFrame +
        scale.trackWidth / (scale.pxPerFrame <= 0 ? 1 : scale.pxPerFrame);

    // The provisional keys (with any live key drag) drive both the curve and
    // the fit; a handle drag leaves the fit frozen so the axis holds still.
    final shown = _shownKeys();
    _range = fitValueRange(shown, fps, frameLo, frameHi, staticValue: _staticValue);
    final range = _frozenRange ?? _range;

    // The tangent applied to the drawn curve during a live handle drag.
    final curveKeys = _handleDrag == null ? shown : _keysWithHandle(_handleDrag!);
    final samples = sampleValueCurve(
      curveKeys,
      fps,
      frameLo,
      frameHi,
      staticValue: _staticValue,
    );

    return LayoutBuilder(
      builder: (context, c) {
        _plotH = c.maxHeight;
        return Listener(
          onPointerDown: (e) {
            if (e.kind == PointerDeviceKind.mouse &&
                e.buttons == kSecondaryMouseButton) {
              final local = (context.findRenderObject() as RenderBox?)
                  ?.globalToLocal(e.position);
              if (local != null) {
                final hit = _keyAt(local);
                if (hit != null) {
                  setState(() => _selected = hit);
                  _openKeyMenu(hit, e.position);
                }
              }
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Report the drag from the true grab point, not the post-slop
            // position, so a key/handle hit-test lands on what was grabbed.
            dragStartBehavior: DragStartBehavior.down,
            onTapUp: _onTapUp,
            onDoubleTapDown: _onDoubleTapDown,
            onDoubleTap: () {}, // arm the double-tap recogniser
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: CustomPaint(
              painter: _ValueCurvePainter(
                samples: samples,
                keys: _keys,
                keyDrag: _keyDrag,
                handleDrag: _handleDrag,
                selected: _selected,
                prop: widget.prop,
                scale: scale,
                range: range,
                fps: fps,
                playheadFrame: app.previewFrame,
                empty: _keys.isEmpty,
                surface0: t.surface0,
                surface1: t.surface1,
                hairline: t.hairline,
                hairlineStrong: t.hairlineStrong,
                curveColour: t.curve.first,
                handleColour: t.curve.length > 3 ? t.curve[3] : t.curve.first,
                accent: t.accent,
                textMuted: t.textMuted,
                keyColour: t.textSecondary,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }

  /// The keys with the live handle drag folded into the dragged side (and, for a
  /// smooth key, mirrored) — for the live curve only.
  List<BridgeKeyframe> _keysWithHandle(_HandleDrag hd) {
    return [
      for (var i = 0; i < _keys.length; i++)
        if (i == hd.index)
          _applyHandle(_keys[i], hd)
        else
          _keys[i],
    ];
  }

  BridgeKeyframe _applyHandle(BridgeKeyframe k, _HandleDrag hd) {
    // Handles only appear on already-Bezier sides, so only the bezier value on
    // the dragged side (and, for a smooth key, the mirrored partner) changes —
    // the interp names stay put.
    final dragged = BridgeBezier(speed: hd.speed, influence: hd.influence);
    final unified = k.interpIn == 'Bezier' &&
        k.interpOut == 'Bezier' &&
        k.bezierIn != null &&
        k.bezierOut != null &&
        (k.bezierIn!.speed - k.bezierOut!.speed).abs() < 1e-6;
    BridgeBezier? partner(String interp, BridgeBezier? bez) => unified
        ? BridgeBezier(speed: hd.speed, influence: sideInfluence(interp, bez))
        : bez;
    return BridgeKeyframe(
      frame: k.frame,
      value: k.value,
      interpIn: k.interpIn,
      interpOut: k.interpOut,
      bezierIn: hd.isOut ? partner(k.interpIn, k.bezierIn) : dragged,
      bezierOut: hd.isOut ? dragged : partner(k.interpOut, k.bezierOut),
    );
  }
}

/// Paints the value graph: gutter + plot backgrounds, the value-unit y grid, the
/// dense bezier curve, the playhead, the interp-coded key glyphs (a selected key
/// ringed) and, on the selected key, its gold tangent handles.
class _ValueCurvePainter extends CustomPainter {
  final List<ValueSample> samples;
  final List<BridgeKeyframe> keys;
  final _KeyDrag? keyDrag;
  final _HandleDrag? handleDrag;
  final int? selected;
  final String prop;
  final LaneScale scale;
  final (double, double) range;
  final double fps;
  final int? playheadFrame;
  final bool empty;
  final Color surface0, surface1, hairline, hairlineStrong;
  final Color curveColour, handleColour, accent, textMuted, keyColour;

  _ValueCurvePainter({
    required this.samples,
    required this.keys,
    required this.keyDrag,
    required this.handleDrag,
    required this.selected,
    required this.prop,
    required this.scale,
    required this.range,
    required this.fps,
    required this.playheadFrame,
    required this.empty,
    required this.surface0,
    required this.surface1,
    required this.hairline,
    required this.hairlineStrong,
    required this.curveColour,
    required this.handleColour,
    required this.accent,
    required this.textMuted,
    required this.keyColour,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = scale.trackLeft;
    final plotRight = scale.trackLeft + scale.trackWidth;
    final plotRect = Rect.fromLTRB(plotLeft, 0, plotRight, size.height);
    final (lo, hi) = range;
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;

    double yOf(double v) => size.height - ((v - lo) / span) * size.height;
    double xOf(double frame) => scale.xOfFrame(frame);

    canvas.drawRect(
        Rect.fromLTRB(0, 0, plotLeft, size.height), Paint()..color = surface1);
    canvas.drawRect(plotRect, Paint()..color = surface0);

    // Y-axis: value-unit gridlines with their labels.
    final unit = propUnit(prop);
    final grid = Paint()
      ..color = hairline
      ..strokeWidth = 0.5;
    for (final v in axisTickValues(lo, hi)) {
      final y = yOf(v);
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), grid);
      _label(canvas, '${fmtAxisValue(v, span)}$unit', plotLeft + 4, y - 1);
    }

    // The value curve, clipped to the plot.
    if (samples.length >= 2) {
      canvas.save();
      canvas.clipRect(plotRect);
      final path = Path();
      for (var i = 0; i < samples.length; i++) {
        final p = Offset(xOf(samples[i].frame), yOf(samples[i].value));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
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

    // Playhead.
    final ph = playheadFrame;
    if (ph != null) {
      final x = xOf(ph.toDouble());
      if (x >= plotLeft - 0.5 && x <= plotRight + 0.5) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height),
            Paint()..color = accent..strokeWidth = 1.0);
      }
    }

    // Keys (with any live drag applied to the dragged one), clipped to the plot
    // so a key dragged off-view does not paint over the gutter/ruler.
    canvas.save();
    canvas.clipRect(plotRect);
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      final drag = (keyDrag != null && keyDrag!.index == i) ? keyDrag : null;
      final frame = drag?.frame ?? k.frame.toDouble();
      final value = drag?.value ?? k.value;
      final pos = Offset(xOf(frame), yOf(value));
      final isSel = selected == i;
      drawKeyGlyph(
        canvas,
        pos,
        keyShapeOf(k),
        fill: isSel ? accent : keyColour,
        outline: isSel ? accent : keyColour,
        selected: isSel,
        selectRing: accent,
      );
      if (isSel) _drawHandles(canvas, i, k, xOf, yOf);
    }
    canvas.restore();
  }

  /// The selected key's gold tangent handles: one per bezier side that has a
  /// neighbour, its endpoint from [handleEndpoint] (the live drag overriding the
  /// dragged side).
  void _drawHandles(Canvas canvas, int index, BridgeKeyframe k,
      double Function(double) xOf, double Function(double) yOf) {
    final pos = Offset(xOf(k.frame.toDouble()), yOf(k.value));
    for (final isOut in const [true, false]) {
      final interp = isOut ? k.interpOut : k.interpIn;
      final bez = isOut ? k.bezierOut : k.bezierIn;
      if (interp != 'Bezier' || bez == null) continue;
      final nb = isOut
          ? (index + 1 < keys.length ? keys[index + 1].frame : null)
          : (index > 0 ? keys[index - 1].frame : null);
      if (nb == null) continue;
      final live = handleDrag;
      final useDrag = live != null && live.index == index && live.isOut == isOut;
      final speed = useDrag ? live.speed : bez.speed;
      final influence = useDrag ? live.influence : bez.influence;
      final e = handleEndpoint(
        keyFrame: k.frame.toDouble(),
        keyValue: k.value,
        neighbourFrame: nb.toDouble(),
        isOut: isOut,
        speed: speed,
        influence: influence,
        fps: fps,
      );
      final hp = Offset(xOf(e.frame), yOf(e.value));
      canvas.drawLine(
          pos, hp, Paint()..color = handleColour..strokeWidth = 1.0);
      canvas.drawCircle(hp, useDrag ? 4.5 : 3.0, Paint()..color = handleColour);
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
  bool shouldRepaint(_ValueCurvePainter old) =>
      old.samples != samples ||
      old.keys != keys ||
      old.keyDrag != keyDrag ||
      old.handleDrag != handleDrag ||
      old.selected != selected ||
      old.range != range ||
      old.playheadFrame != playheadFrame ||
      old.prop != prop;
}
