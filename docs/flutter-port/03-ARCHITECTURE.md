# 03 — Architecture: Flutter over the Rust engine

## In plain terms

Today one program does everything: the Rust process opens a window, egui draws
the interface into it, and the same process decodes, composites and exports.
With Flutter, the window and everything drawn in it belongs to Flutter (which
runs Dart code), while the engine stays Rust. The two halves talk over a
*bridge*: Dart calls Rust functions as if they were Dart functions, and Rust
streams results back. The one place that needs more than function calls is the
Viewer — video frames are far too big to copy through a function call per frame,
so the engine draws them into a piece of GPU memory that Flutter displays
directly.

## The layering

```
flutter_ui/  (Dart)          — widgets, layout, theme, input, dialogs
     │  flutter_rust_bridge (generated FFI)
crates/lumit-bridge  (Rust)  — the API surface: commands in, events/state out
     │  plain Rust calls
crates/lumit-core, -eval, -media, -audio, -cache, -gpu, …  (unchanged)
```

- `lumit-bridge` is a **new** crate (Phase F1): a cdylib the Flutter Windows
  runner loads. It owns the engine-side state that `lumit-ui`'s `AppState`
  owns today; `lumit-ui` remains untouched so the egui frontend keeps building.
- Engine crates never depend on the bridge or on Flutter — the docs/05
  dependency rule holds unchanged.
- Long-running work (decode, export, beat detection) already lives on worker
  threads with channels; the bridge exposes those as Dart `Stream`s
  (flutter_rust_bridge's `StreamSink`), which is the same latest-wins pattern
  K-170 documents.

## Commands and state

The egui frontend mutates `AppState` directly each frame. Flutter cannot — the
document lives in Rust. The port keeps one honest boundary:

- **Commands down:** every user action becomes one bridge call (`op` dispatch
  mirrors `lumit_core::ops`, so undo/redo journalling is untouched).
- **State up:** the bridge publishes coarse-grained, versioned snapshots
  (project tree, comp outline, selection, transport) over streams; Dart holds
  them in `ChangeNotifier`s the widgets watch. Fine-grained per-frame data
  (playhead position during playback) rides its own lightweight stream.
- Rule of thumb from 14-ENGINEERING-RULES: typed rational time crosses the
  bridge as `{num, den}` pairs, never as floating seconds.

### Bridge v0

Phase F1 does **not** start with `flutter_rust_bridge`. It starts with **bridge
v0: a hand-rolled JSON-over-C-ABI seam** — plain `extern "C"` functions in
`lumit-bridge` that Dart calls over `dart:ffi`, exchanging UTF-8 JSON strings.
`flutter_rust_bridge` remains the target once the API surface stabilises; v0
keeps the toolchain simple and testable (no codegen step, no build-runner) while
the shape of the commands and snapshots is still being found. The parity
checklist's codegen row stays open until then.

The contract v0 pins, unchanged when codegen replaces it:

- **No panic crosses the boundary.** Every exported function's body runs inside
  `std::panic::catch_unwind`; a panic becomes an ordinary
  `{"ok":false,"error":"…"}` reply, never an unwind into Dart
  (14-ENGINEERING-RULES). Every reply is either `{"ok":true, …}` or
  `{"ok":false,"error":"…"}`, the error a calm sentence for the status line.
- **Rust owns the strings.** Each function returns a Rust-allocated,
  NUL-terminated UTF-8 pointer; Dart copies the bytes out and immediately hands
  the pointer back to `lumit_bridge_free_string` so Rust frees it. Dart never
  frees Rust memory itself, and Rust never reads a freed pointer.
- **One client, one lock.** The engine-side document and its undo store live
  behind a single process-wide `Mutex` (there is exactly one Flutter window),
  held only for the duration of one state transition, never across re-entry.
- **Absent library ⇒ placeholders.** Dart's `LumitBridge.tryLoad()` returns null
  when the `.dll` cannot be found or bound, and the whole frontend (and every
  Flutter test) keeps its F0 placeholder behaviour. The bridge is an
  enhancement, never a hard dependency of the chrome.

## The Viewer texture path (Phase F2)

Windows first, matching the project's priorities:

1. The engine renders the composited frame with wgpu exactly as today
   (preview == export unchanged).
2. wgpu runs over D3D12; the frame is copied into a **shared D3D11 texture**
   (keyed mutex handshake), which Flutter's Windows embedder accepts as a
   `GpuSurfaceTexture` through the texture registrar.
3. Dart shows it with a `Texture(textureId: …)` widget inside the Viewer panel;
   the pasteboard around it is `viewer_surround`, drawn by Flutter.
4. Frame pacing stays engine-side (the K-171 cached/realtime scheduler);
   Flutter just marks the texture frame available.

The CPU fallback (no GPU) mirrors today's path: the bridge hands RGBA bytes and
Dart blits them through a `ui.Image` — slower, but the slate/placeholder path
already works that way.

This is the only part of the port with real platform-specific plumbing; it is
why the Viewer is its own phase.

## Text, fonts, icons

- Inter Medium ships as a bundled Flutter font family, same OFL licence file.
- Iconoir arrives via the maintained `iconoir_flutter` package (same set the
  Rust side embeds); the drawn motion-blur mark becomes a `CustomPainter`
  reproducing the 24×24 artwork.

## Persistence

The egui frontend persists the workspace through eframe's storage and the
project session through egui's data map. The Flutter side writes one JSON file
(`workspace.json`) in the platform config directory carrying the §9 inventory
state, and per-project session files next to it. Migration from the eframe
store is not attempted — the alternative frontend starts with defaults, which
is acceptable for an experiment (logged in the checklist).

## Testing strategy

- Pure Dart logic (dock tree, settings, theme tables, palette filtering,
  shortcut routing) — plain unit tests, the bulk of coverage.
- Widgets — `flutter_test` widget tests: settings pages render every control,
  menu items dispatch, tab pills switch, shortcuts fire actions.
- Bridge (F1+) — Rust-side integration tests on `lumit-bridge` (no Flutter
  needed), plus one Dart smoke test loading the real cdylib.
- Golden-image tests are deferred until the theme stabilises — they are brittle
  while chrome is still landing.
