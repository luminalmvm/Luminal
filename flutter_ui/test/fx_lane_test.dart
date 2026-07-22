// Effect-parameter lanes in the Timeline outline (06 §C): the pure fx-key logic
// (channels, union frames, channel fields), the extended lane-key identity and
// its shift grouping, the fx clipboard round trip, and widget tests that the
// Effects group + parameter rows render with a stopwatch / navigator / lane, and
// that a lane drag and the navigator commit the bridge-v0.9 effect-param ops.

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumit_flutter/bridge/bridge.dart';
import 'package:lumit_flutter/panels/timeline/fx_keys.dart';
import 'package:lumit_flutter/panels/timeline/keyframe_clipboard.dart';
import 'package:lumit_flutter/panels/timeline/lane_selection.dart';
import 'package:lumit_flutter/panels/timeline_panel.dart';
import 'package:lumit_flutter/widgets/controls.dart';
import 'package:lumit_flutter/state/app_state.dart';
import 'package:lumit_flutter/theme/theme.dart';

BridgeEffectParam _scalarParam({
  required String name,
  required double value,
  required List<int> frames,
  bool animated = true,
}) =>
    BridgeEffectParam(
      name: name,
      kind: 'scalar',
      value: value,
      animated: animated,
      keys: [
        for (final f in frames)
          BridgeKeyframe(
              frame: f, value: value, interpIn: 'Linear', interpOut: 'Linear'),
      ],
    );

void main() {
  group('fx_keys', () {
    test('animatable kinds and their channel lists', () {
      expect(fxParamAnimatable('scalar'), isTrue);
      expect(fxParamAnimatable('point'), isTrue);
      expect(fxParamAnimatable('colour'), isTrue);
      expect(fxParamAnimatable('enum'), isFalse);
      expect(fxParamChannels('scalar'), [0]);
      expect(fxParamChannels('point'), [0, 1]);
      expect(fxParamChannels('colour'), [0, 1, 2, 3]);
      expect(fxParamChannels('bool'), isEmpty);
    });

    test('union frames fold a scalar param and multi-channel channels', () {
      final scalar = _scalarParam(name: 'radius', value: 4, frames: [30, 10]);
      expect(fxUnionFrames(scalar), [10, 30]);
      final point = BridgeEffectParam(
        name: 'centre',
        kind: 'point',
        value: const [0.5, 0.5],
        animated: true,
        channelKeys: {
          'keys_x': [
            const BridgeKeyframe(
                frame: 5, value: 0.5, interpIn: 'Linear', interpOut: 'Linear'),
          ],
          'keys_y': [
            const BridgeKeyframe(
                frame: 20, value: 0.5, interpIn: 'Linear', interpOut: 'Linear'),
          ],
        },
      );
      expect(fxUnionFrames(point), [5, 20]);
    });

    test('channel key field maps and channel key lookup', () {
      expect(fxChannelKeyField('scalar', 0), isNull);
      expect(fxChannelKeyField('point', 0), 'keys_x');
      expect(fxChannelKeyField('point', 1), 'keys_y');
      expect(fxChannelKeyField('colour', 2), 'keys_b');
      final scalar = _scalarParam(name: 'r', value: 7, frames: [12]);
      expect(fxChannelKeyAt(scalar, 0, 12)?.value, 7);
      expect(fxChannelKeyAt(scalar, 0, 99), isNull);
    });

    test('channel values read the current param value per channel', () {
      final colour = BridgeEffectParam(
          name: 'tint', kind: 'colour', value: const [0.1, 0.2, 0.3, 1.0]);
      expect(fxChannelValues(colour), [(0, 0.1), (1, 0.2), (2, 0.3), (3, 1.0)]);
    });
  });

  group('LaneKeyId with effect identity', () {
    test('effect and transform keys never collide on identity', () {
      const tx = LaneKeyId('l', 'radius', 10);
      const fx = LaneKeyId('l', 'radius', 10, effectId: 'e1');
      expect(tx == fx, isFalse);
      expect(tx.isEffect, isFalse);
      expect(fx.isEffect, isTrue);
      // atFrame carries the effect identity across.
      final moved = fx.atFrame(15);
      expect(moved.effectId, 'e1');
      expect(moved.frame, 15);
    });

    test('groupKeysForShift skips fx keys; groupEffectKeysForShift takes them',
        () {
      final keys = {
        const LaneKeyId('l', 'position_x', 10),
        const LaneKeyId('l', 'position_x', 20),
        const LaneKeyId('l', 'radius', 10, effectId: 'e1'),
        const LaneKeyId('l', 'radius', 40, effectId: 'e1'),
      };
      final tx = groupKeysForShift(keys);
      expect(tx.keys.length, 1);
      expect(tx[('l', 'position_x')], [10, 20]);
      final fx = groupEffectKeysForShift(keys);
      expect(fx.keys.length, 1);
      expect(fx[('l', 'e1', 'radius')], [10, 40]);
    });
  });

  group('fx clipboard round trip', () {
    BridgeComp makeComp() => BridgeComp.fromJson(jsonDecode('''
      {
        "width": 1000, "height": 500, "fps": {"num": 30, "den": 1},
        "frame_count": 300,
        "layers": [
          {"id":"lf","index":0,"name":"clip","kind":"footage",
           "in_frame":0,"out_frame":300,"label":0,"switches":{},
           "effects":[
             {"id":"e1","name":"blur","enabled":true,"params":[
               {"name":"radius","kind":"scalar","value":5.0,"animated":true,
                "keys":[
                  {"frame":30,"value":5.0,"interp_in":"Hold","interp_out":"Hold"},
                  {"frame":60,"value":9.0,"interp_in":"Linear","interp_out":"Linear"}
                ]}
             ]}
           ]}
        ],
        "markers": []
      }''') as Map<String, dynamic>);

    test('an fx selection copies its channel keys and pastes ids', () {
      final comp = makeComp();
      final sel = {
        const LaneKeyId('lf', 'radius', 30, effectId: 'e1'),
        const LaneKeyId('lf', 'radius', 60, effectId: 'e1'),
      };
      final clip = buildKeyframeClipboard(sel, comp);
      expect(clip.keys.length, 2);
      expect(clip.keys.every((k) => k.isEffect), isTrue);
      expect(clip.keys.first.effectId, 'e1');
      // The earliest key is at offset 0; the Hold key keeps its easing.
      final held = clip.keys.firstWhere((k) => k.frameOffset == 0);
      expect(held.interpIn, 'Hold');
      // effectClipboardKeys pulls exactly the fx keys.
      expect(effectClipboardKeys(clip).length, 2);
      // Encode/decode carries the effect identity.
      final round = KeyframeClipboard.decode(clip.encode());
      expect(round.keys.first.effectId, 'e1');
      // Pasted ids keep the effect identity at playhead + offset.
      final ids = pastedKeyIds(clip, 100);
      expect(ids.every((i) => i.effectId == 'e1'), isTrue);
      expect(ids.map((i) => i.frame).toSet(), {100, 130});
    });
  });

  group('Effects group in the Timeline outline (widget)', () {
    testWidgets('renders the group, param row, stopwatch and navigator; the '
        'stopwatch and navigator commit fx ops', (tester) async {
      final fake = _FxFake();
      final app = AppStateStub(bridge: fake)..selectLayer('lf');
      await tester.pumpWidget(_host(app));
      await tester.pump();

      // Open the layer twirl, then the Effects group, then the effect twirl.
      await tester.tap(find.byKey(const ValueKey('twirl:lf')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('group:lf:effects')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('group:lf:fx:e1')));
      await tester.pump();

      // The parameter row and its stopwatch are present.
      expect(find.byKey(const ValueKey('fxrow:lf:e1:radius')), findsOneWidget);
      expect(find.byKey(const ValueKey('fxstopwatch:lf:e1:radius')),
          findsOneWidget);

      // The stopwatch toggles animation on channel 0.
      await tester.tap(find.byKey(const ValueKey('fxstopwatch:lf:e1:radius')));
      await tester.pump();
      expect(fake.ops, contains('fxtoggle:c1/lf/e1/radius/ch0@0'));

      // Between the keys (30, 90) the diamond adds a key at the playhead.
      app.goToFrame(60);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fxnav-toggle:lf:e1:radius')));
      await tester.pump();
      expect(fake.ops.any((o) => o.startsWith('fxadd:c1/lf/e1/radius/ch0@60')),
          isTrue);
    });

    testWidgets('dragging a lane key commits shiftEffectParamKeyframes',
        (tester) async {
      final fake = _FxFake();
      final app = AppStateStub(bridge: fake)..snapping = false;
      app.selectLayer('lf');
      await tester.pumpWidget(_host(app));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('twirl:lf')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('group:lf:effects')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('group:lf:fx:e1')));
      await tester.pump();

      // Same lane geometry as the transform drag test: trackLeft 260 over an
      // 800-wide surface, trackWidth 532, over 300 frames.
      const ppf = 532 / 300;
      final rowRect =
          tester.getRect(find.byKey(const ValueKey('fxrow:lf:e1:radius')));
      final glyphX = 260 + 30 * ppf; // key at frame 30
      const dx = 40.0;
      await tester.dragFrom(
          Offset(glyphX, rowRect.center.dy), const Offset(dx, 0));
      await tester.pump();
      final shifts =
          fake.ops.where((o) => o.startsWith('fxshift:')).toList();
      expect(shifts.length, 1);
      expect(shifts.first, startsWith('fxshift:c1/lf/e1/radius/ch0/[30]+'));
    });
  });
}

/// A fake DocumentBridge + EditOpsBridge whose snapshot has one footage layer
/// with an animatable scalar effect param (keys at 30, 90). Records the fx ops.
class _FxFake implements DocumentBridge, EditOpsBridge {
  final List<String> ops = [];

  static const _json = '''
  {
    "ok": true,
    "items": [
      {
        "id": "c1", "name": "Scene", "kind": "composition", "children": [],
        "comp": {
          "width": 1000, "height": 500, "fps": {"num": 30, "den": 1},
          "frame_count": 300,
          "layers": [
            {"id":"lf","index":0,"name":"clip","kind":"footage",
             "in_frame":0,"out_frame":300,"label":0,"switches":{},
             "effects":[
               {"id":"e1","name":"blur","enabled":true,"params":[
                 {"name":"radius","kind":"scalar","value":5.0,"animated":true,
                  "keys":[
                    {"frame":30,"value":5.0,"interp_in":"Linear","interp_out":"Linear"},
                    {"frame":90,"value":9.0,"interp_in":"Linear","interp_out":"Linear"}
                  ]}
               ]}
             ]}
          ],
          "markers": []
        }
      }
    ],
    "can_undo": false, "can_redo": false, "path": null
  }''';

  BridgeReply _snap() => BridgeReply.parse(_json);
  BridgeReply _op(String r) {
    ops.add(r);
    return _snap();
  }

  @override
  BridgeReply snapshot() => _snap();

  @override
  BridgeReply toggleEffectParamAnimated(String c, String l, String e, String p,
          int channel, int frame) =>
      _op('fxtoggle:$c/$l/$e/$p/ch$channel@$frame');

  @override
  BridgeReply addEffectParamKeyframe(String c, String l, String e, String p,
          int channel, int frame, double value) =>
      _op('fxadd:$c/$l/$e/$p/ch$channel@$frame=$value');

  @override
  BridgeReply removeEffectParamKeyframe(
          String c, String l, String e, String p, int channel, int frame) =>
      _op('fxremove:$c/$l/$e/$p/ch$channel@$frame');

  @override
  BridgeReply shiftEffectParamKeyframes(String c, String l, String e, String p,
          int channel, String framesJson, int delta) =>
      _op('fxshift:$c/$l/$e/$p/ch$channel/$framesJson+$delta');

  @override
  dynamic noSuchMethod(Invocation invocation) => _snap();
}

Widget _host(AppStateStub app) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: ThemeScope(
          theme: LumitTheme.dark(),
          animationLevel: AnimationLevel.none,
          showTooltips: false,
          child: Overlay(
            initialEntries: [OverlayEntry(builder: (_) => TimelinePanel(app: app))],
          ),
        ),
      ),
    );
