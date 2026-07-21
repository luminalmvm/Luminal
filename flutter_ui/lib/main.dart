// Lumit's Flutter frontend (K-174, the frontend alternative experiment).
// The engine stays in the Rust crates; this application is the chrome —
// see docs/flutter-port/ for the plan and the parity checklist.

import 'package:flutter/widgets.dart';

import 'bridge/bridge.dart';
import 'shell/shell.dart';
import 'state/workspace.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final workspace = Workspace()..load();
  // Try the engine bridge; a null result keeps the F0 placeholder behaviour
  // (the app and every test must work without the library present).
  final bridge = LumitBridge.tryLoad();
  runApp(LumitApp(workspace: workspace, bridge: bridge));
}

class LumitApp extends StatelessWidget {
  final Workspace workspace;
  final LumitBridge? bridge;
  const LumitApp({super.key, required this.workspace, this.bridge});

  @override
  Widget build(BuildContext context) {
    // WidgetsApp-level infrastructure only — no Material chrome
    // (docs/flutter-port/04 "Why not Material chrome"). Phase F0 renders at
    // native scale, exactly like a fresh egui install; the UI-scale setting
    // starts applying when the setting is wired to the window in a later
    // slice.
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) => Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: workspace.theme.surface0,
          child: LumitShell(workspace: workspace, bridge: bridge),
        ),
      ),
    );
  }
}
