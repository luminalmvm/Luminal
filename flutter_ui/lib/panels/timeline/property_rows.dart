// Which transform property rows a layer's Transform twirl shows, and in what
// grouped order. Ported from the egui `transform_property_rows`
// (crates/lumit-ui/src/shell/inspector/transform_rows.rs): Anchor point,
// Position, Scale, Rotation, Opacity, with the x/y pairs sharing one row
// (AE-style — the two values stay independent, the row furniture merges), plus
// the 3D-only rows (Position z, Rotation x, Rotation y) when the layer is 3D.
// Pure data so the row set is unit-tested without a widget tree.

import '../../bridge/bridge.dart';
import 'fx_keys.dart';

/// One property row descriptor: its display [label] and the snake_case bridge
/// property name(s) it edits — a pair (`anchor_x`, `anchor_y`) on one row, or a
/// single name for Rotation/Opacity.
class PropRowSpec {
  final String label;
  final List<String> props;

  const PropRowSpec(this.label, this.props);

  /// A two-axis (x/y) row that shows two value readouts.
  bool get isPair => props.length == 2;

  /// The property name whose animation drives the row's stopwatch/navigator
  /// (the x channel of a pair, like egui's linked rows).
  String get primary => props.first;
}

/// The transform rows for a layer, in the egui outline's order. [threeD] adds
/// the depth rows; [isCamera] drops Anchor point (cameras have no anchor row).
List<PropRowSpec> transformRows({
  required bool threeD,
  required bool isCamera,
}) {
  return [
    if (!isCamera) const PropRowSpec('Anchor point', ['anchor_x', 'anchor_y']),
    const PropRowSpec('Position', ['position_x', 'position_y']),
    const PropRowSpec('Scale', ['scale_x', 'scale_y']),
    const PropRowSpec('Rotation', ['rotation']),
    const PropRowSpec('Opacity', ['opacity']),
    if (threeD) ...const [
      PropRowSpec('Position z', ['position_z']),
      PropRowSpec('Rotation x', ['rotation_x']),
      PropRowSpec('Rotation y', ['rotation_y']),
    ],
  ];
}

/// The union of a row's keyframes across its axes, sorted by frame and
/// de-duplicated by frame (a linked pair keys both axes together, so one glyph
/// stands for both) — the lane and navigator both work on this union, mirroring
/// egui's `union_key_times`.
List<BridgeKeyframe> rowKeys(BridgeTransform? transform, PropRowSpec spec) {
  if (transform == null) return const [];
  final out = <BridgeKeyframe>[];
  final seen = <int>{};
  for (final name in spec.props) {
    final prop = transform[name];
    if (prop == null) continue;
    for (final k in prop.keys) {
      if (seen.add(k.frame)) out.add(k);
    }
  }
  out.sort((a, b) => a.frame.compareTo(b.frame));
  return out;
}

/// Whether any axis of a row is animated (its stopwatch shows accent).
bool rowAnimated(BridgeTransform? transform, PropRowSpec spec) {
  if (transform == null) return false;
  for (final name in spec.props) {
    if (transform[name]?.animated == true) return true;
  }
  return false;
}

// --- Effect-parameter rows (the timeline outline's Effects group) ----------

/// The animatable parameters of an effect instance, in stack order — the rows
/// the timeline Effects group shows under that effect (one per param). Mirrors
/// egui's `effects_rows`, which lists a row per Float param; the Flutter model
/// additionally surfaces the bridge-v0.9 colour/point channel keys, so every
/// animatable-kind param (scalar/point/colour) gets a row. Non-animatable kinds
/// (enum/bool/seed/file/layer) have no lane and are dropped here.
List<BridgeEffectParam> fxAnimatableParams(BridgeEffect effect) => [
      for (final p in effect.params)
        if (fxParamAnimatable(p.kind)) p,
    ];

/// The sentence-case display label for an effect param [name] (`blur_radius` →
/// "Blur radius"), the same folding the Effect controls panel uses.
String fxParamLabel(String name) {
  final words = name.split('_').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return name;
  final first = words.first;
  final head =
      first.isEmpty ? first : '${first[0].toUpperCase()}${first.substring(1)}';
  return [head, ...words.skip(1)].join(' ');
}
