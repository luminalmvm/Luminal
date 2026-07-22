// The Retime speed-lens maths, all pure so it unit-tests without a widget tree.
// Ported from `crates/lumit-core/src/retime.rs` (the `Ease` shapes, the rate
// speed profile v0 + (v1−v0)·e(u), and the Map-segment derivative
// y′(u)/x′(u)) and from `crates/lumit-ui/src/shell/graph.rs::graph_plot_retime`
// (the speed-view sampling and the boundary handling), adapted to work in comp
// *frames* on the x axis so the curve shares the timeline ruler's zoom mapping
// rather than a whole-width t/duration scale.
//
// In plain terms: this file knows the shape of each speed ramp, how to turn a
// Retime store into a list of (frame, speed-%) points to draw, which boundary a
// pointer is grabbing, and how far a dragged boundary may travel before it hits
// its neighbours.

import 'dart:math' as math;

import '../../bridge/bridge.dart';

/// The five Vegas ease profiles (docs/04-RETIMING.md §4.1), matching
/// `lumit_core::retime::Ease`.
enum GraphEase { linear, slow, fast, smooth, sharp }

/// The ease named by a segment's serde variant (`Linear`/`Slow`/`Fast`/
/// `Smooth`/`Sharp`), defaulting to [GraphEase.linear] for anything else.
GraphEase easeFromName(String? name) => switch (name) {
      'Slow' => GraphEase.slow,
      'Fast' => GraphEase.fast,
      'Smooth' => GraphEase.smooth,
      'Sharp' => GraphEase.sharp,
      _ => GraphEase.linear,
    };

/// The five ramp presets as the labels the header draws.
const List<String> presetLabels = ['Lin', 'Slow', 'Fast', 'Smth', 'Shrp'];

/// The preset-row label for an ease (the exact string the `setSegmentPreset`
/// op takes: `Lin`/`Slow`/`Fast`/`Smth`/`Shrp`).
String presetLabelFor(GraphEase e) => switch (e) {
      GraphEase.linear => 'Lin',
      GraphEase.slow => 'Slow',
      GraphEase.fast => 'Fast',
      GraphEase.smooth => 'Smth',
      GraphEase.sharp => 'Shrp',
    };

/// e(u), the speed-profile shape itself (0 at the segment start, 1 at the end)
/// — `lumit_core::retime::Ease::small_e`, ported line-for-line.
double smallE(GraphEase ease, double u) {
  switch (ease) {
    case GraphEase.linear:
      return u;
    case GraphEase.slow:
      return u * u;
    case GraphEase.fast:
      return 2.0 * u - u * u;
    case GraphEase.smooth:
      if (u <= 0.5) return 2.0 * u * u;
      final w = 1.0 - u;
      return 1.0 - 2.0 * w * w;
    case GraphEase.sharp:
      if (u <= 0.5) return 2.0 * u - 2.0 * u * u;
      return 2.0 * u * u - 2.0 * u + 1.0;
  }
}

/// E(u), the integral of e(u) (0 at the segment start) — `retime.rs::big_e`,
/// ported line-for-line. Used to map local time → source position (`evaluate`).
double bigE(GraphEase ease, double u) {
  switch (ease) {
    case GraphEase.linear:
      return u * u / 2.0;
    case GraphEase.slow:
      return u * u * u / 3.0;
    case GraphEase.fast:
      return u * u - u * u * u / 3.0;
    case GraphEase.smooth:
      if (u <= 0.5) return 2.0 * u * u * u / 3.0;
      final w = 1.0 - u;
      return u + 2.0 * w * w * w / 3.0 - 0.5;
    case GraphEase.sharp:
      if (u <= 0.5) return u * u - 2.0 * u * u * u / 3.0;
      return 2.0 * u * u * u / 3.0 - u * u + u - 1.0 / 6.0;
  }
}

/// The speed endpoints of a rate segment with the reverse gate applied: while
/// reverse is off, a negative speed evaluates as zero (§6.2). Every ease is
/// monotone, so clamping the endpoints clamps the whole profile.
(double, double) clampedSpeeds(double v0, double v1, bool allowReverse) {
  if (allowReverse) return (v0, v1);
  double floor(double v) => v < 0 ? 0 : v;
  return (floor(v0), floor(v1));
}

/// A cubic bezier over four scalar control points (Bernstein form) —
/// `retime.rs::bezier`.
double _bezier(List<double> p, double u) {
  final w = 1.0 - u;
  return w * w * w * p[0] +
      3.0 * w * w * u * p[1] +
      3.0 * w * u * u * p[2] +
      u * u * u * p[3];
}

/// The derivative of [_bezier] — `retime.rs::bezier_deriv`.
double _bezierDeriv(List<double> p, double u) {
  final w = 1.0 - u;
  return 3.0 * w * w * (p[1] - p[0]) +
      6.0 * w * u * (p[2] - p[1]) +
      3.0 * u * u * (p[3] - p[2]);
}

/// The §4.2 control points of a Map segment between its two boundaries, as
/// `([tx0..tx3], [sy0..sy3])` in (local seconds, source seconds) —
/// `retime.rs::map_control_points`.
(List<double>, List<double>) _mapControlPoints(
    BridgeRetimeSegment seg, BridgeRetimeBoundary lo, BridgeRetimeBoundary hi) {
  final t0 = lo.tSeconds, s0 = lo.sSeconds;
  final t1 = hi.tSeconds, s1 = hi.sSeconds;
  final d = t1 - t0;
  final m0 = seg.m0 ?? 0, m1 = seg.m1 ?? 0;
  final b0 = seg.b0 ?? (1 / 3), b1 = seg.b1 ?? (1 / 3);
  return (
    [t0, t0 + b0 * d, t1 - b1 * d, t1],
    [s0, s0 + m0 * b0 * d, s1 - m1 * b1 * d, s1],
  );
}

bool _isOneThird(double v) => (v - 1.0 / 3.0).abs() < 1e-9;

/// Find the bezier parameter u with x(u) = t — `retime.rs::map_param_at`
/// (linear when the handles are the polynomial 1/3, else a Newton-in-bracket
/// solve, `retime.rs::solve_u`).
double _mapParamAt(BridgeRetimeSegment seg, List<double> x, double t) {
  if (_isOneThird(seg.b0 ?? (1 / 3)) && _isOneThird(seg.b1 ?? (1 / 3))) {
    final span = x[3] - x[0];
    if (span <= 0) return 0;
    return ((t - x[0]) / span).clamp(0.0, 1.0);
  }
  return _solveU(x, t);
}

/// Solve x(u) = t by Newton inside a shrinking bisection bracket —
/// `retime.rs::solve_u` (the same solver as `anim::CubicSpan::solve_u`), run to
/// the ≤ 2⁻⁴⁸ relative tolerance of docs/04-RETIMING.md §4.3.
double _solveU(List<double> x, double t) {
  final x0 = x[0], x3 = x[3];
  if (x3 <= x0) return 0;
  final tol = (x3 - x0) * math.pow(2.0, -48);
  var lo = 0.0, hi = 1.0;
  var u = ((t - x0) / (x3 - x0)).clamp(0.0, 1.0);
  for (var i = 0; i < 48; i++) {
    final xu = _bezier(x, u);
    if ((xu - t).abs() <= tol) break;
    if (xu < t) {
      lo = u;
    } else {
      hi = u;
    }
    final dxu = _bezierDeriv(x, u);
    final newton = u - (xu - t) / dxu;
    u = (dxu > 1e-12 && newton > lo && newton < hi) ? newton : 0.5 * (lo + hi);
  }
  return u;
}

/// One sampled point of the speed lens: comp [frame] on the x axis and the
/// instantaneous speed in per cent on the y axis (100 = source rate).
typedef SpeedSample = ({double frame, double pct});

/// Sample the whole retime speed profile as a polyline of (comp frame, speed %)
/// points. Rate segments draw their native ease shape (two endpoint levels
/// joined by e(u)); Map segments draw their derivative y′(u)/x′(u). The x of a
/// point is the comp frame its local time maps to (linear within a segment, so
/// the join sits exactly on its boundary frame). Returns an empty list for a
/// structurally unusable store, never a throw.
List<SpeedSample> sampleSpeedCurve(BridgeRetime retime, {int perSegment = 24}) {
  final out = <SpeedSample>[];
  final bs = retime.boundaries;
  final segs = retime.segments;
  if (bs.length < 2 || segs.length != bs.length - 1) return out;
  final n = math.max(2, perSegment);
  for (var i = 0; i < segs.length; i++) {
    final lo = bs[i], hi = bs[i + 1];
    final seg = segs[i];
    final f0 = lo.tFrame.toDouble(), f1 = hi.tFrame.toDouble();
    final dFrame = f1 - f0;
    if (seg.kind == 'map') {
      final (x, y) = _mapControlPoints(seg, lo, hi);
      final tSpan = hi.tSeconds - lo.tSeconds;
      for (var k = (i == 0) ? 0 : 1; k <= n; k++) {
        final u = k / n;
        final t = _bezier(x, u);
        final frac = tSpan.abs() < 1e-12 ? u : (t - lo.tSeconds) / tSpan;
        final frame = f0 + frac * dFrame;
        final dx = _bezierDeriv(x, u);
        final speed = _bezierDeriv(y, u) / (dx.abs() < 1e-12 ? 1e-12 : dx);
        out.add((frame: frame, pct: speed * 100.0));
      }
    } else {
      final (v0, v1) =
          clampedSpeeds(seg.v0 ?? 1, seg.v1 ?? 1, retime.reverse);
      final ease = easeFromName(seg.ease);
      for (var k = (i == 0) ? 0 : 1; k <= n; k++) {
        final u = k / n;
        final frame = f0 + u * dFrame;
        final speed = v0 + (v1 - v0) * smallE(ease, u);
        out.add((frame: frame, pct: speed * 100.0));
      }
    }
  }
  return out;
}

/// The index of the segment whose comp-frame span `[boundaries[i].tFrame,
/// boundaries[i+1].tFrame)` contains [frame] (the last segment claims its own
/// end). Null for a structurally unusable store or a frame outside the domain.
/// This is the segment the preset row and →Rate act on when the playhead sits
/// on [frame].
int? segmentIndexAtFrame(BridgeRetime retime, int frame) {
  final bs = retime.boundaries;
  final segs = retime.segments;
  if (bs.length < 2 || segs.length != bs.length - 1) return null;
  if (frame < bs.first.tFrame || frame > bs.last.tFrame) return null;
  for (var i = 0; i < segs.length; i++) {
    final start = bs[i].tFrame;
    final end = bs[i + 1].tFrame;
    if (frame >= start && (frame < end || i == segs.length - 1)) return i;
  }
  return null;
}

/// The instantaneous speed in per cent at comp [frame] (the header readout).
/// Zero for a structurally unusable store or a frame outside the domain.
double speedPctAtFrame(BridgeRetime retime, int frame) {
  final i = segmentIndexAtFrame(retime, frame);
  if (i == null) return 0;
  final lo = retime.boundaries[i], hi = retime.boundaries[i + 1];
  final seg = retime.segments[i];
  final span = (hi.tFrame - lo.tFrame).toDouble();
  final u = span.abs() < 1e-9
      ? 0.0
      : ((frame - lo.tFrame) / span).clamp(0.0, 1.0);
  if (seg.kind == 'map') {
    final (x, y) = _mapControlPoints(seg, lo, hi);
    final tSpan = hi.tSeconds - lo.tSeconds;
    final t = lo.tSeconds + u * tSpan;
    final param = _mapParamAt(seg, x, t);
    final dx = _bezierDeriv(x, param);
    return _bezierDeriv(y, param) / (dx.abs() < 1e-12 ? 1e-12 : dx) * 100.0;
  }
  final (v0, v1) = clampedSpeeds(seg.v0 ?? 1, seg.v1 ?? 1, retime.reverse);
  return (v0 + (v1 - v0) * smallE(easeFromName(seg.ease), u)) * 100.0;
}

/// The interior boundary indices — the ones a drag may move. The first and last
/// boundaries are the clip's own domain ends (docs/04-RETIMING.md §3 pins the
/// start at local time 0), so only `1..n-2` are draggable; a single-segment
/// store therefore has none.
List<int> draggableBoundaryIndices(BridgeRetime retime) => [
      for (var i = 1; i < retime.boundaries.length - 1; i++) i,
    ];

/// The interior boundary whose drawn vertical is within [thresholdPx] of the
/// pointer at [pointerX], or null. [xOfFrame] maps a boundary's comp frame to
/// the same x the ruler uses. Ties go to the nearer boundary.
int? boundaryAtX(
  BridgeRetime retime,
  double pointerX,
  double Function(num frame) xOfFrame, {
  double thresholdPx = 6,
}) {
  int? best;
  var bestDist = thresholdPx;
  for (final i in draggableBoundaryIndices(retime)) {
    final d = (xOfFrame(retime.boundaries[i].tFrame) - pointerX).abs();
    if (d <= bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}

/// Clamp a dragged boundary's target comp [frame] between its neighbours, one
/// frame clear of each (horizontal boundary drags are clamped between
/// neighbouring boundaries, docs/04-RETIMING.md §9). [index] must be interior.
int clampBoundaryFrame(BridgeRetime retime, int index, int frame) {
  final bs = retime.boundaries;
  final lo = bs[index - 1].tFrame + 1;
  final hi = bs[index + 1].tFrame - 1;
  if (hi < lo) return bs[index].tFrame; // no room; leave it put
  return frame.clamp(lo, hi);
}

/// A copy of [retime] with boundary [index]'s comp frame moved to [frame] — the
/// live-preview store drawn while a boundary drag is in flight (only the x of
/// the join moves; the segment speeds are untouched, matching the speed lens).
BridgeRetime withBoundaryFrame(BridgeRetime retime, int index, int frame) {
  final bs = [
    for (var i = 0; i < retime.boundaries.length; i++)
      if (i == index)
        BridgeRetimeBoundary(
          tFrame: frame,
          tSeconds: retime.boundaries[i].tSeconds,
          sSeconds: retime.boundaries[i].sSeconds,
          smooth: retime.boundaries[i].smooth,
        )
      else
        retime.boundaries[i],
  ];
  return BridgeRetime(
    reverse: retime.reverse,
    interpolation: retime.interpolation,
    boundaries: bs,
    segments: retime.segments,
  );
}

/// The source position (seconds) at local comp time [tSecs] — a port of
/// `retime.rs::Retime::evaluate`: a Rate segment maps `s_i + d·[v0·u +
/// (v1−v0)·E(u)]`, a Map segment `bezier(y, u(t))`. `tSecs` is clamped into the
/// store's local domain. Holds the first boundary's source position for a
/// structurally unusable store (never throws).
double sourceSecsAtLocal(BridgeRetime retime, double tSecs) {
  final bs = retime.boundaries;
  final segs = retime.segments;
  if (bs.length < 2 || segs.length != bs.length - 1) {
    return bs.isEmpty ? 0.0 : bs.first.sSeconds;
  }
  final t = tSecs.clamp(bs.first.tSeconds, bs.last.tSeconds);
  // Largest segment whose start boundary is <= t.
  var idx = 0;
  for (var i = 0; i < bs.length; i++) {
    if (bs[i].tSeconds <= t) idx = i;
  }
  final i = idx.clamp(0, segs.length - 1);
  final lo = bs[i], hi = bs[i + 1];
  final d = hi.tSeconds - lo.tSeconds;
  if (d <= 0) return lo.sSeconds;
  final seg = segs[i];
  if (seg.kind == 'map') {
    final (x, y) = _mapControlPoints(seg, lo, hi);
    return _bezier(y, _mapParamAt(seg, x, t));
  }
  final u = ((t - lo.tSeconds) / d).clamp(0.0, 1.0);
  final (v0, v1) = clampedSpeeds(seg.v0 ?? 1, seg.v1 ?? 1, retime.reverse);
  return lo.sSeconds + d * (v0 * u + (v1 - v0) * bigE(easeFromName(seg.ease), u));
}

/// The local comp time (seconds) at which the source is exhausted — a port of
/// `retime.rs::Retime::overrun_local_time`: the first boundary whose source
/// position reaches [sourceDurationSecs], then a bisection back to the exact
/// crossing. `0` when the clip starts already past the source end; null when the
/// source lasts to the out point (no overrun).
double? overrunLocalTime(BridgeRetime retime, double sourceDurationSecs) {
  final bs = retime.boundaries;
  final segs = retime.segments;
  if (bs.length < 2 || segs.length != bs.length - 1) return null;
  final dur = sourceDurationSecs;
  for (var i = 0; i < bs.length; i++) {
    if (bs[i].sSeconds < dur) continue;
    if (i == 0) return 0.0; // starts already past the source end
    var lo = bs[i - 1].tSeconds;
    var hi = bs[i].tSeconds;
    for (var k = 0; k < 40; k++) {
      final mid = 0.5 * (lo + hi);
      if (sourceSecsAtLocal(retime, mid) >= dur) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return hi;
  }
  return null;
}

/// Where a retimed footage layer runs out of source, as a comp-time span in
/// seconds `(start, out)` — a port of `speed_rows.rs::overrun_span_secs`: from
/// the exhaustion point (clamped to the in point) to the out point, or null when
/// the source lasts to the out point (or runs out only past it). Indication
/// only — the hatch never moves a boundary (K-022).
(double, double)? overrunSpanSecs(
  BridgeRetime retime,
  double sourceDurationSecs,
  double startOffsetSecs,
  double inPointSecs,
  double outPointSecs,
) {
  final local = overrunLocalTime(retime, sourceDurationSecs);
  if (local == null) return null;
  final start = math.max(startOffsetSecs + local, inPointSecs);
  return start < outPointSecs ? (start, outPointSecs) : null;
}

/// The auto-fit y-range (speed %) for a sampled curve: always framing the 0%
/// and 100% references, padded 12% like the egui speed lens. Returns
/// `(lo, hi)`.
(double, double) speedRange(List<SpeedSample> samples) {
  var lo = 0.0, hi = 100.0;
  for (final s in samples) {
    lo = math.min(lo, s.pct);
    hi = math.max(hi, s.pct);
  }
  final pad = math.max((hi - lo).abs(), 1.0) * 0.12;
  return (lo - pad, hi + pad);
}

// ===========================================================================
// The transform value graph (K-078; ported from
// `crates/lumit-core/src/anim.rs` — `evaluate`/`evaluate_speed`/`CubicSpan` —
// and `crates/lumit-ui/src/shell/graph.rs` — `graph_plot`, the bezier
// handle geometry, the auto-fit and the beat/frame snapping). All pure so it
// unit-tests against the same hand-computed and anim.rs constants the engine
// pins (the EASY_EASE midpoint, the easy-ease flat ends).
//
// In plain terms: this half of the file knows how to turn a property's
// keyframes into a smooth curve (sampling the real bezier between each pair of
// keys, exactly as the engine evaluates it), where a key's tangent handle sits
// on screen and how to read a dragged handle back into (speed, influence), how
// tall to make the graph so the whole curve and its handles fit, and where a
// dragged key or boundary snaps to when the magnet is on.
// ===========================================================================

/// The AE easy-ease influence third — `anim::EASY_EASE`'s influence, the
/// default handle reach a Linear/Hold side lends the bezier maths.
const double kEaseThird = 1.0 / 3.0;

/// A keyframe side's influence (bezier handle reach as a fraction of the gap),
/// defaulting to the easy-ease third for a Linear/Hold side — `graph.rs`'s
/// `side_influence`.
double sideInfluence(String interp, BridgeBezier? bezier) =>
    (interp == 'Bezier' && bezier != null) ? bezier.influence : kEaseThird;

/// A keyframe side's bezier slope (value-units per second), or null when the
/// side is Linear/Hold and carries no single slope — `graph.rs`'s `side_speed`.
double? sideSpeed(String interp, BridgeBezier? bezier) =>
    (interp == 'Bezier' && bezier != null) ? bezier.speed : null;

/// The AE (speed, influence) a side contributes to the cubic: a Bezier side's
/// own pair (influence floored to 1e-3), else the chord slope with a ⅓ reach —
/// `anim::side_params`.
(double, double) _sideParams(String interp, BridgeBezier? bezier, double chord) {
  if (interp == 'Bezier' && bezier != null) {
    return (bezier.speed, bezier.influence.clamp(1e-3, 1.0));
  }
  return (chord, kEaseThird);
}

/// One span's cubic bezier built from AE parameters — `anim::CubicSpan`, ported
/// line-for-line (the same bracketed-Newton solve the engine uses, so a
/// steep-handle curve is sampled exactly rather than approximated).
class GraphCubic {
  final List<double> _x;
  final List<double> _y;
  const GraphCubic._(this._x, this._y);

  /// `P0=(t1,v1) P1=(t1+bOut·Δt, v1+sOut·bOut·Δt)
  ///  P2=(t2−bIn·Δt, v2−sIn·bIn·Δt) P3=(t2,v2)` — `CubicSpan::from_ae`.
  factory GraphCubic.fromAe(double t1, double v1, double t2, double v2,
      double speedOut, double inflOut, double speedIn, double inflIn) {
    final dt = t2 - t1;
    return GraphCubic._(
      [t1, t1 + inflOut * dt, t2 - inflIn * dt, t2],
      [v1, v1 + speedOut * inflOut * dt, v2 - speedIn * inflIn * dt, v2],
    );
  }

  /// Solve x(u) = t by Newton inside a shrinking bracket — `CubicSpan::solve_u`
  /// (binding; the same solver as the retime map param solve).
  double _solveU(double t) {
    final x0 = _x[0], x3 = _x[3];
    if (x3 <= x0) return 0;
    var lo = 0.0, hi = 1.0;
    var u = ((t - x0) / (x3 - x0)).clamp(0.0, 1.0);
    for (var i = 0; i < 16; i++) {
      final xu = _bezier(_x, u);
      if ((xu - t).abs() < 1e-12) break;
      if (xu < t) {
        lo = u;
      } else {
        hi = u;
      }
      final dxu = _bezierDeriv(_x, u);
      final newton = u - (xu - t) / dxu;
      u = (dxu > 1e-12 && newton > lo && newton < hi) ? newton : 0.5 * (lo + hi);
    }
    return u;
  }

  /// The value at time `t` (seconds).
  double valueAt(double t) => _bezier(_y, _solveU(t));

  /// The instantaneous slope dv/dt at `t` — `y′(u)/x′(u)`, x′ floored so a
  /// 100%-influence handle stays finite (`CubicSpan::speed_at`).
  double speedAt(double t) {
    final u = _solveU(t);
    return _bezierDeriv(_y, u) / math.max(_bezierDeriv(_x, u), 1e-12);
  }
}

/// Evaluate a property's keyframes at comp time [tSecs] — a port of
/// `anim::evaluate`, honouring each pair of adjacent sides (Hold-out wins the
/// span, Linear/Linear is the chord, any bezier side shapes the cubic). The
/// keys carry their comp [frame]; [fps] turns frames into the seconds the
/// bezier speed is expressed in. Clamps flat past the ends; 0 for no keys.
double evaluateValueKeys(List<BridgeKeyframe> keys, double fps, double tSecs) {
  if (keys.isEmpty) return 0;
  final f = fps <= 0 ? 1.0 : fps;
  final first = keys.first, last = keys.last;
  if (tSecs <= first.frame / f) return first.value;
  if (tSecs >= last.frame / f) return last.value;
  var idx = keys.length - 2;
  for (var i = 0; i < keys.length - 1; i++) {
    if (tSecs < keys[i + 1].frame / f) {
      idx = i;
      break;
    }
  }
  return _evalSpan(keys[idx], keys[idx + 1], f, tSecs);
}

double _evalSpan(BridgeKeyframe a, BridgeKeyframe b, double f, double t) {
  final t1 = a.frame / f, t2 = b.frame / f;
  final dt = t2 - t1;
  if (dt <= 0) return a.value;
  if (a.interpOut == 'Hold') return a.value;
  if (a.interpOut == 'Linear' && b.interpIn == 'Linear') {
    return a.value + (b.value - a.value) * ((t - t1) / dt);
  }
  final chord = (b.value - a.value) / dt;
  final (s1, b1) = _sideParams(a.interpOut, a.bezierOut, chord);
  final (s2, b2) = _sideParams(b.interpIn, b.bezierIn, chord);
  return GraphCubic.fromAe(t1, a.value, t2, b.value, s1, b1, s2, b2).valueAt(t);
}

/// The instantaneous speed dv/dt at [tSecs] — a port of `anim::evaluate_speed`
/// (flat past the ends and across a Hold-out span, the exact derivative of the
/// value bezier elsewhere).
double evaluateSpeedKeys(List<BridgeKeyframe> keys, double fps, double tSecs) {
  if (keys.isEmpty) return 0;
  final f = fps <= 0 ? 1.0 : fps;
  final first = keys.first, last = keys.last;
  if (tSecs <= first.frame / f || tSecs >= last.frame / f) return 0;
  var idx = keys.length - 2;
  for (var i = 0; i < keys.length - 1; i++) {
    if (tSecs < keys[i + 1].frame / f) {
      idx = i;
      break;
    }
  }
  final a = keys[idx], b = keys[idx + 1];
  final t1 = a.frame / f, t2 = b.frame / f;
  final dt = t2 - t1;
  if (dt <= 0) return 0;
  if (a.interpOut == 'Hold') return 0;
  if (a.interpOut == 'Linear' && b.interpIn == 'Linear') {
    return (b.value - a.value) / dt;
  }
  final chord = (b.value - a.value) / dt;
  final (s1, b1) = _sideParams(a.interpOut, a.bezierOut, chord);
  final (s2, b2) = _sideParams(b.interpIn, b.bezierIn, chord);
  return GraphCubic.fromAe(t1, a.value, t2, b.value, s1, b1, s2, b2).speedAt(tSecs);
}

/// One sampled point of the value lens: comp [frame] on x, the property [value]
/// on y (or its slope, in the speed sub-view).
typedef ValueSample = ({double frame, double value});

/// Sample a property's value curve densely across `[frameLo, frameHi]`, so the
/// bezier reads smooth at any zoom — the piecewise curve `graph_plot` draws,
/// never a straight line between keys. [speed] samples the exact derivative
/// instead (the speed sub-view). A flat line at [staticValue] when there are no
/// keys (a still property you can double-click a first key onto).
List<ValueSample> sampleValueCurve(
  List<BridgeKeyframe> keys,
  double fps,
  double frameLo,
  double frameHi, {
  int samples = 160,
  bool speed = false,
  double staticValue = 0,
}) {
  final f = fps <= 0 ? 1.0 : fps;
  final n = math.max(2, samples);
  final span = (frameHi - frameLo);
  final out = <ValueSample>[];
  for (var i = 0; i <= n; i++) {
    final frame = frameLo + span * i / n;
    final t = frame / f;
    final v = keys.isEmpty
        ? (speed ? 0.0 : staticValue)
        : (speed
            ? evaluateSpeedKeys(keys, f, t)
            : evaluateValueKeys(keys, f, t));
    out.add((frame: frame, value: v));
  }
  return out;
}

/// The comp-frame endpoint and value of a key's bezier tangent handle on one
/// side — `graph.rs`'s handle geometry. [neighbourFrame] is the frame of the key
/// on that side; a handle of slope [speed] reaching [influence] of the gap ends
/// at `value ± speed · reach` a fraction [influence] of the way to the
/// neighbour. `fps` turns the frame gap into the seconds the slope is per.
({double frame, double value}) handleEndpoint({
  required double keyFrame,
  required double keyValue,
  required double neighbourFrame,
  required bool isOut,
  required double speed,
  required double influence,
  required double fps,
}) {
  final f = fps <= 0 ? 1.0 : fps;
  final segFrames = isOut ? neighbourFrame - keyFrame : keyFrame - neighbourFrame;
  final reachSecs = influence * (segFrames.abs() / f);
  final endFrame = isOut
      ? keyFrame + influence * segFrames.abs()
      : keyFrame - influence * segFrames.abs();
  final endValue = isOut ? keyValue + speed * reachSecs : keyValue - speed * reachSecs;
  return (frame: endFrame, value: endValue);
}

/// Read a dragged tangent-handle endpoint back into `(speed, influence)` for one
/// side — the inverse of [handleEndpoint], matching `graph.rs`'s value-lens drag
/// (`dt` clamped inside the segment with a tiny floor; influence and speed share
/// that reach so the handle lands under the cursor).
({double speed, double influence}) handleFromDrag({
  required double keyFrame,
  required double keyValue,
  required double neighbourFrame,
  required bool isOut,
  required double dragFrame,
  required double dragValue,
  required double fps,
}) {
  final f = fps <= 0 ? 1.0 : fps;
  final segFrames = (isOut ? neighbourFrame - keyFrame : keyFrame - neighbourFrame).abs();
  if (segFrames <= 1e-9) return (speed: 0, influence: kEaseThird);
  final dFrames = (isOut ? dragFrame - keyFrame : keyFrame - dragFrame)
      .clamp(segFrames * 1e-3, segFrames);
  final influence = (dFrames / segFrames).clamp(1e-3, 1.0);
  final dSecs = dFrames / f;
  final speed = (isOut ? dragValue - keyValue : keyValue - dragValue) / dSecs;
  return (speed: speed, influence: influence);
}

/// The value extremes the value graph must frame: every key's value, each
/// bezier side's tangent-handle endpoint (a steep handle can poke past the
/// curve), and the drawn curve's own samples (a bezier can overshoot its
/// keys) — `graph.rs`'s `fit_values_with_handles` plus the curve-sample grow,
/// padded 15%. Reads ALL keys so selecting one never jumps the view.
(double, double) fitValueRange(
  List<BridgeKeyframe> keys,
  double fps,
  double frameLo,
  double frameHi, {
  double staticValue = 0,
}) {
  final f = fps <= 0 ? 1.0 : fps;
  if (keys.isEmpty) {
    final pad = math.max(staticValue.abs(), 1.0) * 0.15;
    return (staticValue - pad, staticValue + pad);
  }
  var lo = double.infinity, hi = -double.infinity;
  for (var i = 0; i < keys.length; i++) {
    final k = keys[i];
    lo = math.min(lo, k.value);
    hi = math.max(hi, k.value);
    for (final isOut in const [false, true]) {
      final interp = isOut ? k.interpOut : k.interpIn;
      final bez = isOut ? k.bezierOut : k.bezierIn;
      final sp = sideSpeed(interp, bez);
      if (sp == null) continue;
      final int? nb = isOut
          ? (i + 1 < keys.length ? keys[i + 1].frame : null)
          : (i > 0 ? keys[i - 1].frame : null);
      if (nb == null) continue;
      final e = handleEndpoint(
        keyFrame: k.frame.toDouble(),
        keyValue: k.value,
        neighbourFrame: nb.toDouble(),
        isOut: isOut,
        speed: sp,
        influence: sideInfluence(interp, bez),
        fps: f,
      );
      lo = math.min(lo, e.value);
      hi = math.max(hi, e.value);
    }
  }
  for (final s in sampleValueCurve(keys, f, frameLo, frameHi, samples: 96)) {
    lo = math.min(lo, s.value);
    hi = math.max(hi, s.value);
  }
  final pad = math.max((hi - lo).abs(), 1.0) * 0.15;
  return (lo - pad, hi + pad);
}

/// The unit a transform property's y-axis labels carry — `graph.rs`'s
/// `prop_unit`, over the snapshot's snake_case names ("" for the pixel
/// properties, which read cleaner bare).
String propUnit(String prop) {
  switch (prop) {
    case 'scale_x':
    case 'scale_y':
    case 'scale_z':
    case 'opacity':
      return '%';
    case 'rotation':
    case 'rotation_x':
    case 'rotation_y':
    case 'rotation_z':
      return '°';
    default:
      return '';
  }
}

/// A y-axis value formatted to suit the span — `graph.rs`'s `fmt_axis_value`
/// (whole numbers once the range is wide, more decimals as it narrows).
String fmtAxisValue(double v, double span) {
  final s = span.abs();
  if (s >= 20.0) return v.toStringAsFixed(0);
  if (s >= 2.0) return v.toStringAsFixed(1);
  return v.toStringAsFixed(2);
}

/// The four evenly spaced gridline values `graph_y_axis` labels across `[lo,
/// hi]` (clear of the pane edges), bottom-to-top.
List<double> axisTickValues(double lo, double hi, {int count = 4}) => [
      for (var i = 1; i <= count; i++) lo + (i / (count + 1)) * (hi - lo),
    ];

/// Snap a dragged graph key/boundary comp [frame] — `graph.rs:1616-1628`. A
/// Retime feature snaps to the nearest beat/marker within [thresholdPx] (so a
/// ramp lands on the beat), else falls to a whole frame; a transform key rounds
/// to a whole frame when the [magnet] is on, and — since the bridge keys on
/// whole comp frames — rounds regardless when it is off (drag-frees within a
/// frame, commits on the grid). [beats] are candidate marker frames.
int snapGraphFrame(
  double frame, {
  required bool magnet,
  required double fps,
  required List<int> beats,
  required double pxPerFrame,
  required bool retime,
  double thresholdPx = 6,
}) {
  if (retime) {
    final thr = thresholdPx / math.max(pxPerFrame, 1e-9);
    int? best;
    var bestD = thr;
    for (final m in beats) {
      final d = (m - frame).abs();
      if (d <= bestD) {
        bestD = d;
        best = m;
      }
    }
    return best ?? frame.round();
  }
  return frame.round();
}

// ===========================================================================
// The Retime Time (source-position) lens (docs/04-RETIMING.md §9.1; K-078):
// source time over local time, the ordinary graph editor reading the store's
// value keyframes. Its curve is `sourceSecsAtLocal` sampled across the domain
// (Map segments curve through their control points, Rate segments the
// integrated position); its boundaries drag horizontally in time through the
// `dragBoundary` op (which moves a boundary's local time, keeping its source
// position — the true home of that op, docs/04 §9.1).
// ===========================================================================

/// One sampled point of the Time lens: comp [frame] on x, source position in
/// [secs] on y.
typedef SourceSample = ({double frame, double secs});

/// The local time (seconds) comp [frame] maps to within [retime]'s domain,
/// read off the boundary `(tFrame, tSeconds)` pairs so a non-zero start offset
/// is handled without a separate fps round-trip (local time is linear in comp
/// frame across the whole domain).
double localSecsOfFrame(BridgeRetime retime, double frame) {
  final bs = retime.boundaries;
  if (bs.length < 2) return bs.isEmpty ? 0.0 : bs.first.tSeconds;
  final f0 = bs.first.tFrame.toDouble(), f1 = bs.last.tFrame.toDouble();
  final s0 = bs.first.tSeconds, s1 = bs.last.tSeconds;
  if ((f1 - f0).abs() < 1e-9) return s0;
  return s0 + (frame - f0) * (s1 - s0) / (f1 - f0);
}

/// Sample the whole source-position curve as (comp frame, source seconds)
/// points across `[frameLo, frameHi]` — the Time-lens curve. Dense enough that
/// a Map segment's cubic reads smooth at any zoom. Empty for a structurally
/// unusable store.
List<SourceSample> sampleSourceCurve(
  BridgeRetime retime,
  double frameLo,
  double frameHi, {
  int samples = 160,
}) {
  final bs = retime.boundaries;
  final segs = retime.segments;
  if (bs.length < 2 || segs.length != bs.length - 1) return const [];
  final n = math.max(2, samples);
  final span = frameHi - frameLo;
  final out = <SourceSample>[];
  for (var i = 0; i <= n; i++) {
    final frame = frameLo + span * i / n;
    final t = localSecsOfFrame(retime, frame);
    out.add((frame: frame, secs: sourceSecsAtLocal(retime, t)));
  }
  return out;
}

/// The Time-lens boundary points as (comp frame, source seconds) — the
/// draggable joins the curve passes through.
List<SourceSample> sourceBoundaryPoints(BridgeRetime retime) => [
      for (final b in retime.boundaries) (frame: b.tFrame.toDouble(), secs: b.sSeconds),
    ];

/// The auto-fit y-range (source seconds) for the Time lens: the source span the
/// boundaries and the sampled curve cover, padded 12%. Frames at least a small
/// window so a still store still draws an axis.
(double, double) sourceRange(List<SourceSample> samples) {
  if (samples.isEmpty) return (0.0, 1.0);
  var lo = double.infinity, hi = -double.infinity;
  for (final s in samples) {
    lo = math.min(lo, s.secs);
    hi = math.max(hi, s.secs);
  }
  final pad = math.max((hi - lo).abs(), 1.0) * 0.12;
  return (lo - pad, hi + pad);
}
