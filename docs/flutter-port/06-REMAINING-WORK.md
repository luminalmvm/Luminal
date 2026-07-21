# 06 — Remaining work (delete-on-done ledger)

Every partially finished (◐/◑) or not-started (☐) item extracted from
05-PARITY-CHECKLIST.md on 2026-07-22 (owner request). **Rows are deleted as they
land** — an empty section gets deleted too; an empty file means the transfer is
complete. 05 stays the permanent record; this file is the burn-down.

Excluded on purpose (not parity work): flutter_rust_bridge codegen (deferred by
design until the API stabilises), the macOS pass, the post-parity design changes
in 05 §post-parity, and the two recorded behavioural deviations (export
queue-snapshot timing; share-export VBR cap).

## A — bridge ops (Rust + Dart plumbing)

- Razor: `cut_clip_at_playhead` / `delete_clip_at_playhead` + sequence-layer
  sub-clip editing (menu stubs today)
- Beat detection: `detect_beats(comp, sensitivity)` / `clear_beat_markers`
  (menu + empty-lane-menu stubs today; lumit-audio, media feature)
- Project item ops: `delete_item`, `rename_item`, `move_to_root`,
  `relink(item, path)` (project context-menu stubs today)
- Layer ops: `rename_layer`, `convert_to_sequenced`, `trim_to_source_end`
  (layer context-menu stubs today)
- Retime setters: `set_retime_reverse`, `set_retime_interpolation`
  (Nearest/Flow/Blend) — read-back exists, no setters
- Dedicated `lumit_bridge_autosave` (write a copy WITHOUT re-pointing the
  loaded path — the known autosave drift gap)
- Text/solid/camera property ops: set text content, solid colour/size,
  camera zoom (no editors exist because no ops exist)
- Recovery ops: list autosaves, restore-from-journal (for the recovery modal)
- Boot log: expose the engine's real boot lines for the splash
- Effect params: enum/bool/seed/point setters; param **ranges** in the
  snapshot (unclamped drags today); registry **categories** (flat list today);
  effect **reorder**
- Keyframe batch op (linked x/y pairs currently cost one undo step per axis)

## B — performance follow-ups (K-176/K-177 remainders)

- Bridge-side rendered-frame cache keyed like egui's `comp_frame_cache`
  (comp+frame+scale → frame) — the highest-leverage scrub fix still open
- Engine-side render cancellation (a superseded render still runs to
  completion in the worker, blocking the lock)
- Settings cache controls: "Clear cache" / "Choose cache root folder" land on
  the new cache (stubs today)
- Fence/keyed-mutex handshake for the shared texture — only if the owner's
  live run shows tearing (verify first)
- Footage probing off-thread + Project-panel thumbnails (probe is synchronous;
  no thumbnails)

## C — timeline and graph UI

- Keyframe right-click interpolation menu: Easy ease / Linear / Hold / Unify
  handles / Delete (lane keys remove-only today; graph keys have no menu)
- Empty-lane context menu: Composition settings · Reveal in project · Show
  time grid · Beat sensitivity slider + Detect · Clear beat markers
- Comp-tab-strip right-click: Pop out timeline (routes to the multi-window
  notice until E lands)
- Graph editor: the Retime **Time**/value lens + transform value/speed graph;
  RATE/MAP type chips + ease labels; kink badges; overrun hatching; numeric
  % and t·s entry fields; boundary beat/frame snapping; Vegas default-lens
  preference; speed-keyframe drag handles
- Timeline remainder: beat markers + cache bar; sequence sub-bars; overrun
  HOLD hatch on clip bars; resizable outline column; keyframe copy/paste
  (Ctrl+C/V); move the MB master into the top row
- Transport: loop the **work area** when one is set (loops the whole comp
  today; `work_area` is in the snapshot now)
- Layer context menu: wire Rename (in-place editor), Add effect (categorised
  picker), Convert to sequenced, Trim to source end (ops from A)

## D — editors, viewer and panels

- Property editors beyond Transform: **text content** (the sharp one), solid
  colour/size, camera properties (ops from A)
- Viewer toolbar: the tool row (select/hand/shape/pen tools per the egui
  toolbar) with the Shape tool's right-click mask-shape picker
- Viewer transform overlays/gizmos for the selected layer; the eyedropper
  magnifier (sample the shown pixels, commit through the colour ops)
- Resolution picker + realtime tier readout (engine ladder; scale plumbing
  exists in the bridge render call)
- Project panel: thumbnails, missing-footage badge, rename, and the four
  context-menu ops wiring (ops from A)
- Hierarchy: adopt `source_comp_id` (id-based nesting instead of by-name);
  comp-scoped selection of nested layers
- Effects & presets: `.lumfx` preset save/load; category grouping (registry
  categories from A); drag-an-effect-onto-a-layer application
- Effect controls: per-parameter stopwatch/navigator on effect params

## E — chrome and shell

- Value-field context menu: Reset / Copy / Paste on every DragValueField
- UI-scale setting actually applied to the window (persisted but inert today)
- Tooltip breadth pass: layer switches, transport, ruler, scopes header —
  every egui `on_hover_text` surface
- Splash shows the engine's real boot log (op from A)
- Recovery modal: restore journal / last save / open an autosave (ops from A)
- Pop out a panel into its own OS window (multi-window — the one item with
  real platform risk; attempt last, record the outcome either way)

## Stale rows to reconcile in 05 while burning down

- The graph-lens "→Rate drift figure dropped by BridgeReply" remainder is
  stale — `driftSeconds` is threaded and the notice reads "fitted, N ms
  drift" since 2026-07-22; update 05 when section C lands.
