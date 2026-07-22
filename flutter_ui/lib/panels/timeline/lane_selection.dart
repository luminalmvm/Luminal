// The Timeline lane keyframe selection: a value-identity id for one key, the
// modifier-aware click that grows or replaces the selection (egui's
// `lane_select_click`), and the grouping the drag commit leans on to fire one
// `shiftKeyframes` per (layer, property). Pure, so all of it is unit-tested.

import 'package:flutter/foundation.dart';

/// One selectable lane key, identified by its layer, property and comp frame
/// (the value identity egui's `LaneKeySel` carries). Effect-parameter lanes
/// extend the identity with the owning effect instance ([effectId]) and the
/// param [channel] (egui's `PropRow::Effect { effect, param }`): a transform key
/// leaves [effectId] null; an effect key sets it, so a `position_x` key and an
/// effect param that happens to share the name never collide. The whole
/// [property]/[frame] machinery (selection, drag, glyphs) is otherwise unchanged,
/// so the transform lanes keep behaving exactly as before.
@immutable
class LaneKeyId {
  final String layerId;
  final String property;
  final int frame;

  /// The owning effect instance id for an effect-param lane, or null for a
  /// transform lane.
  final String? effectId;

  /// The param channel this lane key stands for (0 for a scalar or transform
  /// key; the canonical channel of a multi-channel param's union glyph).
  final int channel;

  const LaneKeyId(
    this.layerId,
    this.property,
    this.frame, {
    this.effectId,
    this.channel = 0,
  });

  /// Whether this is an effect-parameter lane key (vs a transform one).
  bool get isEffect => effectId != null;

  /// The same key at a different [frame] (the shape a drag/paste re-anchors to),
  /// carrying the effect identity across.
  LaneKeyId atFrame(int frame) => LaneKeyId(layerId, property, frame,
      effectId: effectId, channel: channel);

  @override
  bool operator ==(Object other) =>
      other is LaneKeyId &&
      other.layerId == layerId &&
      other.property == property &&
      other.frame == frame &&
      other.effectId == effectId &&
      other.channel == channel;

  @override
  int get hashCode => Object.hash(layerId, property, frame, effectId, channel);
}

/// Apply a modifier-aware click to the lane selection (egui note 2.6): a plain
/// click ([additive] false) replaces it with just [key]; an additive click
/// (Ctrl/Shift) toggles the key's membership. Mutates [selection] in place.
void laneSelectClick(
  Set<LaneKeyId> selection,
  LaneKeyId key, {
  required bool additive,
}) {
  if (additive) {
    if (!selection.remove(key)) selection.add(key);
  } else {
    selection
      ..clear()
      ..add(key);
  }
}

/// Group selected TRANSFORM keys by their (layer, property) channel, each mapped
/// to its sorted frame list — the shape the drag commit walks so it fires one
/// `shiftKeyframes(layer, property, frames, delta)` per channel (one undo step
/// each), exactly as egui commits its lane drag per property. Effect-param keys
/// are skipped (they commit through [groupEffectKeysForShift]).
Map<(String, String), List<int>> groupKeysForShift(Iterable<LaneKeyId> keys) {
  final out = <(String, String), List<int>>{};
  for (final k in keys) {
    if (k.isEffect) continue;
    (out[(k.layerId, k.property)] ??= <int>[]).add(k.frame);
  }
  for (final frames in out.values) {
    frames.sort();
  }
  return out;
}

/// Group selected EFFECT keys by their (layer, effectId, paramName) channel —
/// the shape the fx drag commit walks so it fires one
/// `shiftEffectParamKeyframes` per param (repeated once per value channel, since
/// a multi-channel param keys every channel together). Transform keys are
/// skipped. The key is `(layerId, effectId, paramName)`.
Map<(String, String, String), List<int>> groupEffectKeysForShift(
    Iterable<LaneKeyId> keys) {
  final out = <(String, String, String), List<int>>{};
  for (final k in keys) {
    final e = k.effectId;
    if (e == null) continue;
    (out[(k.layerId, e, k.property)] ??= <int>[]).add(k.frame);
  }
  for (final frames in out.values) {
    frames.sort();
  }
  return out;
}
