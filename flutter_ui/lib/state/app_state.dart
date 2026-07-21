// The Phase-F0 stand-in for the engine-backed application state. In the egui
// frontend this is `AppState` (crates/lumit-ui/src/app_state/), owned by Rust;
// here it is a small ChangeNotifier that answers the chrome's questions and
// records the actions the chrome dispatches, so every menu item, shortcut and
// panel control can be wired now and re-pointed at the bridge in Phase F1
// (docs/flutter-port/03-ARCHITECTURE.md).

import 'package:flutter/foundation.dart';

/// One entry in the stub's action log — what a real engine call would have
/// been. The status line surfaces the latest as a notice, so clicking through
/// the chrome shows honest feedback about what is and isn't wired yet.
class StubAction {
  final String action;
  final DateTime at;
  StubAction(this.action) : at = DateTime.now();
}

class AppStateStub extends ChangeNotifier {
  /// Quiet status-line notice (docs/15 §10 — completion is quiet).
  String? notice;

  /// A genuine error, drawn in the error tint. Kept separate from `notice`
  /// exactly as the Rust side splits them.
  String? errorNotice;

  bool playing = false;
  int previewFrame = 0;
  int previewFrameCount = 0;
  double timelineZoom = 1.0;
  bool timelineGraphMode = false;
  bool snapping = true;
  int? selectedLayer;
  final List<String> openComps = [];
  int beatSensitivity = 50;
  bool canUndo = false;
  bool canRedo = false;

  final List<StubAction> actionLog = [];

  /// Record an engine action the bridge will implement, and say so in the
  /// status line — never silently swallow a click.
  void engine(String action) {
    actionLog.add(StubAction(action));
    notice = '$action — engine bridge arrives in phase F1';
    notifyListeners();
  }

  void togglePlay() {
    playing = !playing;
    notifyListeners();
  }

  void stepFrame(int delta) {
    if (playing) playing = false;
    previewFrame = (previewFrame + delta).clamp(0, previewFrameCount);
    notifyListeners();
  }

  void goToFrame(int frame) {
    if (playing) playing = false;
    previewFrame = frame.clamp(0, previewFrameCount);
    notifyListeners();
  }

  void zoomTimeline(double factor) {
    timelineZoom = (timelineZoom * factor).clamp(1.0, 400.0);
    notifyListeners();
  }

  void zoomTimelineFit() {
    timelineZoom = 1.0;
    notifyListeners();
  }

  void toggleGraphMode() {
    timelineGraphMode = !timelineGraphMode;
    notifyListeners();
  }

  void setNotice(String? n) {
    notice = n;
    notifyListeners();
  }
}
