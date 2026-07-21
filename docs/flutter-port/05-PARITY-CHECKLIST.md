# 05 — Parity checklist (living)

The tick-list for the one-for-one port. Updated in the same commit as the work,
newest state wins. ☐ to do · ◐ partial (remainder named) · ☑ done (with tests
where the row is logic).

## Phase F0 — scaffold and chrome

- ☑ Flutter project scaffolded (`flutter_ui/`, package `lumit_flutter`), analyzer clean
- ☑ Theme port: all 7 colour schemes digit-for-digit, ShapeTokens SHARP/ROUND,
  `with_accent` hover shift by mode, `label_colour`, `document_colour`,
  AnimationLevel durations — unit-tested against the Rust values
- ☑ Inter Medium bundled; type scale 16/12/12/11/12
- ☑ Icon set: 44 variants mapped to Iconoir, motion-blur mark as a CustomPainter
- ☑ Settings model: Performance / Autosave / Interface / Export defaults matching
  the engine constants — unit-tested
- ☑ Workspace persistence to JSON (schemes, shape, accent, animation, settings,
  dock layout)
- ☑ Dock: tree model (splits/tabs/panes) + default workspace byte-matching
  `default_layout()` shares — unit-tested; resizable dividers; tab pills with
  the three-state styling; solo panes bare
- ☐ Dock: drag a tab / bare-pane grip to re-dock (the tree is serialisable;
  the move ops and the drag interaction arrive together)
- ☐ Bare-pane affordances: right-click "Pop out into its own window" and the
  corner drag grip
- ☐ Pop out a panel into its own OS window (multi-window; deferred, see 04)
- ☑ Menu bar: File / Edit / Composition / Window with the full shipped item set
  (engine-backed items dispatch to the stub state and surface a notice)
- ☑ Status line: notices, error tint rule, export-progress slot
- ☑ Settings window: all five pages, every control, fixed geometry, opens on
  Appearance; scheme/shape/accent/motion apply live
- ☑ Command palette: modal, fuzzy filter, keyboard selection, the shipped
  command list (incl. the hidden export alias)
- ☑ Shortcut routing: the §5 inventory table wired to the stub state, with the
  text-field focus gate
- ☑ Panel stubs: all seven panels with real chrome (Viewer surround, scope
  graticule placeholder, timeline strip skeleton) so the workspace reads right
- ☐ Splash boot card
- ☐ Active-panel accent edge
- ☐ Sharp/Round: Round cards ☑ (fill, radius, padding, gap, shadow); window
  inset ☑; resize-gap hover/drag tinting ☑

## Phase F1 — bridge (not started)

- ☐ `lumit-bridge` crate; flutter_rust_bridge codegen in CI
- ☐ Project open/save/import; document snapshot stream; ops dispatch + undo/redo
- ☐ Project panel live (items, thumbnails, relink, missing badge)
- ☐ Session restore per project path

## Phase F2 — Viewer (not started)

- ☐ Shared-texture path (D3D11 interop) + `Texture` widget
- ☐ CPU RGBA fallback
- ☐ Transport + resolution picker + realtime tier readout
- ☐ Missing-footage slate (generated colour bars + item path)
- ☐ Eyedropper magnifier; transform overlays

## Phase F3 — Timeline (not started)

Comp tabs · ruler/markers/beats · work area · rows/columns/switches · clip bars
(trim/move/razor/overrun hatch) · outline twirls · Audio group (Volume +
waveform lane) · keyframe lanes (glyphs, drag, copy/paste) · graph lens ·
bottom bar (zoom/magnet/grid) · top row (time, search, MB master)

## Phase F4 — editors (not started)

Effect controls rows · keyframe navigators · channel picker · Effects & presets
(.lumfx) · Scopes (waveform/vectorscope/histogram) · Hierarchy · Export
dialogue + queue · Comp settings · Add mask · Recovery modal

## Post-parity fixes (owner's known rough edges — do NOT fix during the port)

Collected here as they come up so parity stays honest. Currently: (owner to
dictate; nothing recorded yet — the port reproduces today's behaviour including
anything that "isn't quite the way I want".)

## Known deliberate deviations

- No migration of the eframe-persisted workspace; the Flutter frontend starts
  from defaults (03-ARCHITECTURE §Persistence).
- Menus animate per AnimationLevel (egui's could not animate at all).
- macOS native menu bar deferred with the rest of the macOS pass.
