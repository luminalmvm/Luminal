// The Timeline keyframe copy/paste payload and its pure encode/apply helpers
// (egui note 2.2: copy the selected lane keys, paste them at the playhead). All
// pure so the clipboard round-trip and the paste-frame maths unit-test without a
// widget tree.
//
// In plain terms: copying records each selected key's channel, its offset from
// the earliest copied key, its value and how it eases. Pasting drops the same
// shape back down starting at the playhead — the earliest key lands on the
// playhead and the rest keep their spacing.
//
// The bridge's batch op understands only add/remove/toggle (fxparams.rs), so a
// paste inserts the values as one undo step per layer via `applyKeyframeBatch`
// (`add`), then restores each non-Linear key's easing through `setKeyframeInterp`
// — the shapes survive the round-trip even though there is no batch-interp op.

import 'dart:convert';

import '../../bridge/bridge.dart';
import 'fx_keys.dart';
import 'lane_selection.dart';

/// One copied keyframe: its layer + property channel, its [frameOffset] from the
/// earliest copied key, its [value], and its two-sided easing (variant names plus
/// the Bezier `(speed, influence)` handles, present only on a Bezier side). An
/// effect-param key additionally carries its [effectId] and value [channel]
/// (null [effectId] = a transform key), so effect lanes copy/paste alongside the
/// transform lanes.
class ClipboardKey {
  final String layerId;
  final String property;
  final int frameOffset;
  final double value;
  final String interpIn;
  final String interpOut;
  final double? speedIn;
  final double? influenceIn;
  final double? speedOut;
  final double? influenceOut;

  /// The owning effect instance for an effect-param key, or null for a transform
  /// key.
  final String? effectId;

  /// The param value channel (0 for a scalar/transform key).
  final int channel;

  const ClipboardKey({
    required this.layerId,
    required this.property,
    required this.frameOffset,
    required this.value,
    required this.interpIn,
    required this.interpOut,
    this.speedIn,
    this.influenceIn,
    this.speedOut,
    this.influenceOut,
    this.effectId,
    this.channel = 0,
  });

  /// Whether either side eases (not plain Linear/Linear) — the keys whose shape
  /// must be restored after a value-only batch paste.
  bool get eases => interpIn != 'Linear' || interpOut != 'Linear';

  /// Whether this is an effect-param key (vs a transform one).
  bool get isEffect => effectId != null;

  Map<String, dynamic> toJson() => {
        'layer': layerId,
        'property': property,
        'offset': frameOffset,
        'value': value,
        'interp_in': interpIn,
        'interp_out': interpOut,
        if (speedIn != null) 'speed_in': speedIn,
        if (influenceIn != null) 'influence_in': influenceIn,
        if (speedOut != null) 'speed_out': speedOut,
        if (influenceOut != null) 'influence_out': influenceOut,
        if (effectId != null) 'effect': effectId,
        if (effectId != null) 'channel': channel,
      };

  factory ClipboardKey.fromJson(Map<String, dynamic> m) => ClipboardKey(
        layerId: m['layer'] as String,
        property: m['property'] as String,
        frameOffset: (m['offset'] as num).toInt(),
        value: (m['value'] as num).toDouble(),
        interpIn: m['interp_in'] as String? ?? 'Linear',
        interpOut: m['interp_out'] as String? ?? 'Linear',
        speedIn: (m['speed_in'] as num?)?.toDouble(),
        influenceIn: (m['influence_in'] as num?)?.toDouble(),
        speedOut: (m['speed_out'] as num?)?.toDouble(),
        influenceOut: (m['influence_out'] as num?)?.toDouble(),
        effectId: m['effect'] as String?,
        channel: (m['channel'] as num?)?.toInt() ?? 0,
      );
}

/// A copied set of keys (offsets are relative to the earliest copied key, so a
/// paste re-anchors the whole shape at the playhead).
class KeyframeClipboard {
  final List<ClipboardKey> keys;
  const KeyframeClipboard(this.keys);

  bool get isEmpty => keys.isEmpty;

  /// The distinct layer ids the clipboard touches (a paste batches per layer).
  Set<String> get layerIds => {for (final k in keys) k.layerId};

  String encode() => jsonEncode({'keys': [for (final k in keys) k.toJson()]});

  /// Decode a payload produced by [encode]; a malformed string yields an empty
  /// clipboard rather than a throw.
  static KeyframeClipboard decode(String? raw) {
    if (raw == null) return const KeyframeClipboard([]);
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const KeyframeClipboard([]);
      final rawKeys = m['keys'];
      if (rawKeys is! List) return const KeyframeClipboard([]);
      return KeyframeClipboard([
        for (final k in rawKeys)
          if (k is Map) ClipboardKey.fromJson(k.cast<String, dynamic>()),
      ]);
    } catch (_) {
      return const KeyframeClipboard([]);
    }
  }
}

/// Build a clipboard from the current lane [selection], reading each selected
/// key's value and easing out of [comp]. Offsets are measured from the earliest
/// selected frame. Returns an empty clipboard when nothing resolves.
KeyframeClipboard buildKeyframeClipboard(
    Set<LaneKeyId> selection, BridgeComp comp) {
  if (selection.isEmpty) return const KeyframeClipboard([]);
  final earliest =
      selection.map((k) => k.frame).reduce((a, b) => a < b ? a : b);
  final keys = <ClipboardKey>[];
  for (final id in selection) {
    final layer = _layer(comp, id.layerId);
    if (id.isEffect) {
      // An effect union key expands to one clipboard entry per value channel,
      // each with that channel's value + easing at the frame.
      final param = _effectParam(layer, id.effectId!, id.property);
      if (param == null) continue;
      for (final ch in fxParamChannels(param.kind)) {
        final key = fxChannelKeyAt(param, ch, id.frame);
        if (key == null) continue;
        keys.add(ClipboardKey(
          layerId: id.layerId,
          property: id.property,
          frameOffset: id.frame - earliest,
          value: key.value,
          interpIn: key.interpIn,
          interpOut: key.interpOut,
          speedIn: key.bezierIn?.speed,
          influenceIn: key.bezierIn?.influence,
          speedOut: key.bezierOut?.speed,
          influenceOut: key.bezierOut?.influence,
          effectId: id.effectId,
          channel: ch,
        ));
      }
      continue;
    }
    final key = _keyAt(layer, id.property, id.frame);
    if (key == null) continue;
    keys.add(ClipboardKey(
      layerId: id.layerId,
      property: id.property,
      frameOffset: id.frame - earliest,
      value: key.value,
      interpIn: key.interpIn,
      interpOut: key.interpOut,
      speedIn: key.bezierIn?.speed,
      influenceIn: key.bezierIn?.influence,
      speedOut: key.bezierOut?.speed,
      influenceOut: key.bezierOut?.influence,
    ));
  }
  return KeyframeClipboard(keys);
}

/// The `applyKeyframeBatch` op array (the `add` action) that inserts every
/// [clipboard] key belonging to [layerId] at `playhead + offset` with its value —
/// one undo step per layer. Empty (`[]`) when the layer has no copied keys.
String pasteAddBatchJson(
    KeyframeClipboard clipboard, String layerId, int playheadFrame) {
  final buf = StringBuffer('[');
  var first = true;
  for (final k in clipboard.keys) {
    if (k.layerId != layerId || k.isEffect) continue; // fx keys paste per-op
    if (!first) buf.write(',');
    first = false;
    final frame = playheadFrame + k.frameOffset;
    buf.write(
        '{"property":"${k.property}","action":"add","frame":$frame,"value":${k.value}}');
  }
  buf.write(']');
  return buf.toString();
}

/// The effect-param keys in [clipboard] (the transform keys ride the value
/// batch; these paste through per-key `addEffectParamKeyframe` /
/// `setEffectParamKeyframeInterp`, since the bridge has no effect batch op).
List<ClipboardKey> effectClipboardKeys(KeyframeClipboard clipboard) =>
    [for (final k in clipboard.keys) if (k.isEffect) k];

/// The lane keys a paste lands on (the new selection follows the pasted keys),
/// as `(layerId, property, frame)` at `playhead + offset` — an effect key keeps
/// its effect identity (canonical channel 0), de-duplicated so a multi-channel
/// param's union frame is one selected glyph.
List<LaneKeyId> pastedKeyIds(KeyframeClipboard clipboard, int playheadFrame) {
  final out = <LaneKeyId>{};
  for (final k in clipboard.keys) {
    final frame = playheadFrame + k.frameOffset;
    out.add(k.isEffect
        ? LaneKeyId(k.layerId, k.property, frame, effectId: k.effectId)
        : LaneKeyId(k.layerId, k.property, frame));
  }
  return out.toList();
}

BridgeLayer? _layer(BridgeComp comp, String layerId) {
  for (final l in comp.layers) {
    if (l.id == layerId) return l;
  }
  return null;
}

BridgeKeyframe? _keyAt(BridgeLayer? layer, String property, int frame) {
  final prop = layer?.transform?[property];
  if (prop == null) return null;
  for (final k in prop.keys) {
    if (k.frame == frame) return k;
  }
  return null;
}

BridgeEffectParam? _effectParam(
    BridgeLayer? layer, String effectId, String paramName) {
  if (layer == null) return null;
  for (final e in layer.effects) {
    if (e.id != effectId) continue;
    for (final p in e.params) {
      if (p.name == paramName) return p;
    }
  }
  return null;
}
