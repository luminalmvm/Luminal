// Palette filtering: every term must match, aliases count, and the shipped
// command list carries the hidden export alias (command_palette.rs:158).

import 'package:flutter_test/flutter_test.dart';
import 'package:lumit_flutter/shell/command_palette.dart';
import 'package:lumit_flutter/state/app_state.dart';
import 'package:lumit_flutter/state/workspace.dart';

void main() {
  test('an empty query matches everything', () {
    const c = PaletteCommand('Save project', _noop);
    expect(c.matches(''), isTrue);
    expect(c.matches('   '), isTrue);
  });

  test('every whitespace-separated term must appear', () {
    const c = PaletteCommand('Add solid layer', _noop);
    expect(c.matches('solid'), isTrue);
    expect(c.matches('add layer'), isTrue);
    expect(c.matches('add camera'), isFalse);
    expect(c.matches('SOLID'), isTrue, reason: 'case-insensitive');
  });

  test('hidden aliases are searchable', () {
    const c = PaletteCommand('Export comp…', _noop,
        aliases: 'render output video mp4');
    expect(c.matches('render'), isTrue);
    expect(c.matches('mp4'), isTrue);
  });

  test('the shipped list covers the egui palette surface', () {
    final ws = Workspace();
    final cmds = paletteCommands(
      app: AppStateStub(),
      workspace: ws,
      openSettings: _noop,
    );
    final labels = [for (final c in cmds) c.label];
    expect(labels, contains('Save project'));
    expect(labels, contains('Open Settings'));
    expect(labels, contains('Reset workspace'));
    expect(labels, contains('Colour scheme: Catppuccin Mocha'));
    // The export command answers the banned-term alias without wearing it.
    final export = cmds.firstWhere((c) => c.label == 'Export comp…');
    expect(export.matches('render output'), isTrue);
  });
}

void _noop() {}
