// Bridge v0 Dart-side tests: the JSON → typed-model parsing (fed literal
// strings, no library needed), and the guarantee that AppStateStub without a
// bridge behaves exactly as the F0 placeholder did.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumit_flutter/bridge/bridge.dart';
import 'package:lumit_flutter/state/app_state.dart';

void main() {
  group('BridgeSnapshot parsing', () {
    test('an empty document parses to no items and no undo', () {
      final reply = BridgeReply.parse(
        '{"ok":true,"items":[],"can_undo":false,"can_redo":false,"path":null}',
      );
      expect(reply.ok, isTrue);
      final snap = reply.snapshot!;
      expect(snap.items, isEmpty);
      expect(snap.canUndo, isFalse);
      expect(snap.canRedo, isFalse);
      expect(snap.path, isNull);
    });

    test('a nested folder tree parses with kinds and children', () {
      const json = '''
      {
        "ok": true,
        "items": [
          {
            "id": "f1", "name": "Compositions", "kind": "folder",
            "children": [
              {"id": "c1", "name": "Intro", "kind": "composition", "children": []}
            ]
          },
          {"id": "a1", "name": "clip.mp4", "kind": "footage", "children": []},
          {"id": "s1", "name": "White solid", "kind": "solid", "children": []}
        ],
        "can_undo": true, "can_redo": false, "path": "C:/edit.lum"
      }''';
      final reply = BridgeReply.parse(json);
      expect(reply.ok, isTrue);
      final snap = reply.snapshot!;
      expect(snap.canUndo, isTrue);
      expect(snap.path, 'C:/edit.lum');
      expect(snap.items.length, 3);

      final folder = snap.items[0];
      expect(folder.kind, BridgeItemKind.folder);
      expect(folder.name, 'Compositions');
      expect(folder.children.length, 1);
      expect(folder.children[0].kind, BridgeItemKind.composition);
      expect(folder.children[0].name, 'Intro');

      expect(snap.items[1].kind, BridgeItemKind.footage);
      expect(snap.items[2].kind, BridgeItemKind.solid);
    });

    test('an unknown kind degrades rather than throwing', () {
      final reply = BridgeReply.parse(
        '{"ok":true,"items":[{"id":"x","name":"?","kind":"nebula","children":[]}],'
        '"can_undo":false,"can_redo":false,"path":null}',
      );
      expect(reply.ok, isTrue);
      expect(reply.snapshot!.items.single.kind, BridgeItemKind.unknown);
    });

    test('an error reply carries the message, not a snapshot', () {
      final reply = BridgeReply.parse(
        '{"ok":false,"error":"open project: not a Lumit project"}',
      );
      expect(reply.ok, isFalse);
      expect(reply.snapshot, isNull);
      expect(reply.error, 'open project: not a Lumit project');
    });

    test('malformed JSON is reported, never thrown', () {
      final reply = BridgeReply.parse('not json at all');
      expect(reply.ok, isFalse);
      expect(reply.error, contains('malformed'));
    });
  });

  group('AppStateStub without a bridge', () {
    test('bridge is null and no snapshot is held', () {
      final app = AppStateStub();
      expect(app.bridge, isNull);
      expect(app.snapshot, isNull);
    });

    test('document actions keep the exact F0 notice text', () {
      // Each action must produce the same notice as the original
      // `engine('…')` call did, so the placeholder build is unchanged. A fresh
      // instance per action keeps the notices from bleeding together.
      var app = AppStateStub()..newProject();
      expect(app.notice, 'New project — engine bridge arrives in phase F1');

      app = AppStateStub()..newComposition();
      expect(app.notice, 'New composition — engine bridge arrives in phase F1');

      app = AppStateStub()..undo();
      expect(app.notice, 'Undo — engine bridge arrives in phase F1');

      app = AppStateStub()..redo();
      expect(app.notice, 'Redo — engine bridge arrives in phase F1');

      app = AppStateStub()..save();
      expect(app.notice, 'Save — engine bridge arrives in phase F1');

      app = AppStateStub()..openProject();
      expect(app.notice, 'Open project — engine bridge arrives in phase F1');
    });
  });
}
