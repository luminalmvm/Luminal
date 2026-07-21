// Widget smoke tests: the shell renders the default workspace, the Window
// menu opens Settings, and the Settings window shows its pages.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumit_flutter/main.dart';
import 'package:lumit_flutter/state/workspace.dart';

void main() {
  testWidgets('the shell renders the menu bar, tabs and status line',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(LumitApp(workspace: Workspace()));
    await tester.pump();

    for (final label in ['File', 'Edit', 'Composition', 'Window']) {
      expect(find.text(label), findsOneWidget);
    }
    // The left tab group's pills ('Project' also titles the fronted panel's
    // placeholder body, so it can match more than once).
    expect(find.text('Project'), findsWidgets);
    expect(find.text('Effect controls'), findsOneWidget);
    expect(find.text('Effects & presets'), findsOneWidget);
    expect(find.text('Hierarchy'), findsOneWidget);
    expect(find.text('Flutter frontend — phase F0'), findsOneWidget);
  });

  testWidgets('Window → Settings… opens the Settings window on Appearance',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(LumitApp(workspace: Workspace()));
    await tester.pump();

    await tester.tap(find.text('Window'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings…'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Colour scheme'), findsOneWidget);
    expect(find.text('Panel shape'), findsOneWidget);

    // Switch to the Performance page.
    await tester.tap(find.text('Performance').first);
    await tester.pumpAndSettle();
    expect(find.text('Memory budget'), findsOneWidget);

    // Done closes it.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Memory budget'), findsNothing);
  });

  testWidgets('tab pills switch the left group', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(LumitApp(workspace: Workspace()));
    await tester.pump();

    // The pill strip scrolls; bring the last pill into view before tapping.
    await tester.ensureVisible(find.text('Hierarchy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hierarchy'));
    await tester.pumpAndSettle();
    expect(
      find.text('The composition tree arrives in phase F4.'),
      findsOneWidget,
    );
  });
}
