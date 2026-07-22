// The shared effect-parameter keyframe logic (bridge v0.9): which effect-param
// kinds are animatable, their value channels, the union of a param's key frames
// and the value a fresh key takes. Both the Effect controls panel and the
// Timeline outline's Effects group drive their stopwatch / ◄ ◆ ► navigator /
// keyframe lanes through this, so the two never drift.
//
// In plain terms: a Float param has one animatable value; a point has two (x/y)
// and a colour four (r/g/b/a). Keying one keys every channel of the param at
// once. This module says how many channels a kind has, where the snapshot holds
// each channel's keys, and — folding them together — which comp frames the
// param has a key on (one lane glyph per such frame).
//
// Grounding: egui's `effects_rows` (inspector/effect_rows.rs) draws a lane only
// for Float params (and an X/Y pair keyed on its x axis). The bridge v0.9 read-
// back additionally carries colour/point channel keys, which the Flutter panels
// surface as one row per animatable param (union of channels), matching the
// task's "one row per ANIMATABLE param".

import '../../bridge/bridge.dart';

/// The channel value list of an effect-param [value] (a `List` of numbers),
/// padded to RGBA so an index read is always safe (mirrors the panel's tolerant
/// reader): a colour's `[r,g,b,a]`, a point's `[x,y]`.
List<double> fxRgbaOf(Object? value) {
  if (value is List) {
    final out = [for (final e in value) e is num ? e.toDouble() : 0.0];
    while (out.length < 4) {
      out.add(out.length == 3 ? 1.0 : 0.0);
    }
    return out;
  }
  return const [0, 0, 0, 1];
}

/// Whether a param [kind] carries keyframes (a stopwatch, a navigator, a lane).
/// The animatable kinds are scalar, point and colour; enum/bool/seed/file/layer
/// have no animation op.
bool fxParamAnimatable(String kind) =>
    kind == 'scalar' || kind == 'point' || kind == 'colour';

/// The value channels of an animatable [kind]: `[0]` for a scalar, `[0,1]` for a
/// point, `[0,1,2,3]` for a colour. Empty for a non-animatable kind.
List<int> fxParamChannels(String kind) {
  switch (kind) {
    case 'scalar':
      return const [0];
    case 'point':
      return const [0, 1];
    case 'colour':
      return const [0, 1, 2, 3];
    default:
      return const [];
  }
}

/// Each channel of [param] paired with the value a fresh key on it takes at the
/// playhead (read out of the param's current value) — the shape the stopwatch /
/// diamond commit walks (one op per channel), mirroring the panel's `_channels`.
List<(int, double)> fxChannelValues(BridgeEffectParam param) {
  switch (param.kind) {
    case 'scalar':
      final v = param.value is num ? (param.value as num).toDouble() : 0.0;
      return [(0, v)];
    case 'point':
      final xy = fxRgbaOf(param.value);
      return [(0, xy[0]), (1, xy[1])];
    case 'colour':
      final c = fxRgbaOf(param.value);
      return [(0, c[0]), (1, c[1]), (2, c[2]), (3, c[3])];
    default:
      return const [];
  }
}

/// The union of [param]'s key frames across every channel, sorted and unique —
/// one lane glyph (and one navigator stop) per frame, exactly as the panel's
/// navigator reads it.
List<int> fxUnionFrames(BridgeEffectParam param) {
  final frames = <int>{};
  for (final k in param.keys) {
    frames.add(k.frame);
  }
  for (final list in param.channelKeys.values) {
    for (final k in list) {
      frames.add(k.frame);
    }
  }
  final out = frames.toList()..sort();
  return out;
}

/// A representative keyframe of [param] at comp [frame] — the first channel that
/// carries one — so a lane glyph can read its interpolation shape. Null when no
/// channel has a key there.
BridgeKeyframe? fxKeyAt(BridgeEffectParam param, int frame) {
  for (final k in param.keys) {
    if (k.frame == frame) return k;
  }
  for (final list in param.channelKeys.values) {
    for (final k in list) {
      if (k.frame == frame) return k;
    }
  }
  return null;
}

/// The read-back field holding [channel]'s keys for a param of [kind], or null
/// for a scalar (whose keys live on `param.keys`, not a channel field). Matches
/// the `keys_x`/`keys_y` (point) and `keys_r`/`keys_g`/`keys_b`/`keys_a`
/// (colour) convention the bridge snapshot uses.
String? fxChannelKeyField(String kind, int channel) {
  switch (kind) {
    case 'point':
      return channel == 0 ? 'keys_x' : 'keys_y';
    case 'colour':
      const f = ['keys_r', 'keys_g', 'keys_b', 'keys_a'];
      return (channel >= 0 && channel < f.length) ? f[channel] : null;
    default:
      return null; // scalar → param.keys
  }
}

/// The keyframe on [channel] of [param] at comp [frame], or null when that
/// channel has no key there.
BridgeKeyframe? fxChannelKeyAt(BridgeEffectParam param, int channel, int frame) {
  final field = fxChannelKeyField(param.kind, channel);
  final list = field == null ? param.keys : (param.channelKeys[field] ?? const []);
  for (final k in list) {
    if (k.frame == frame) return k;
  }
  return null;
}
