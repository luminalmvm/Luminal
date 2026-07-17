//! `shell::dock` — split out of the monolithic shell.rs (mechanical,
//! no logic changes). Shared names resolve through the parent module
//! via `use super::*` and the glob re-exports in `shell/mod.rs`.

use super::*;

/// The default workspace: a full-width Timeline strip along the bottom, beneath a
/// band of slim tool columns flanking a tall Viewer. Only the left column is a
/// tab group (Project + the effect panels); the Viewer, Scopes and the Timeline
/// sit alone, and a solo pane renders bare — no tab bar — until other panels are
/// stacked onto it (K-086). The editing-suite default.
pub fn default_layout() -> egui_tiles::Tree<Panel> {
    let mut tiles = egui_tiles::Tiles::default();
    let viewer = tiles.insert_pane(Panel::Viewer);

    let project = tiles.insert_pane(Panel::Project);
    let fx = tiles.insert_pane(Panel::EffectControls);
    let fxp = tiles.insert_pane(Panel::EffectsAndPresets);
    let left = tiles.insert_tab_tile(vec![project, fx, fxp]);
    let scopes = tiles.insert_pane(Panel::Scopes);

    // Upper band: the tool columns either side of the Viewer.
    let upper = tiles.insert_horizontal_tile(vec![left, viewer, scopes]);
    if let Some(egui_tiles::Tile::Container(egui_tiles::Container::Linear(lin))) =
        tiles.get_mut(upper)
    {
        lin.shares.set_share(left, 0.22);
        lin.shares.set_share(viewer, 0.58);
        lin.shares.set_share(scopes, 0.20);
    }

    // The Timeline is a direct child of the vertical root, so it spans the full
    // window width along the bottom rather than only the Viewer's column.
    let timeline = tiles.insert_pane(Panel::Timeline);
    let root = tiles.insert_vertical_tile(vec![upper, timeline]);
    if let Some(egui_tiles::Tile::Container(egui_tiles::Container::Linear(lin))) =
        tiles.get_mut(root)
    {
        lin.shares.set_share(upper, 0.68);
        lin.shares.set_share(timeline, 0.32);
    }

    egui_tiles::Tree::new("lumit-dock", root, tiles)
}

/// The dock's simplification rules, shared with the layout tests. A pane that
/// sits alone renders bare — no tab bar, the Viewer's look on every solo panel
/// (K-086) — because single-child tab groups are pruned; stacking panels into a
/// tab group brings the bar (and its pop-out button) back for that group. The
/// pruning runs on every draw, so a workspace saved back when solo panels kept
/// a tab wrapper is tidied the first time it is shown, keeping its pane sizes.
pub(crate) fn dock_simplification_options() -> egui_tiles::SimplificationOptions {
    egui_tiles::SimplificationOptions {
        prune_empty_tabs: true,
        prune_empty_containers: true,
        prune_single_child_tabs: true,
        prune_single_child_containers: true,
        all_panes_must_have_tabs: false,
        join_nested_linear_containers: true,
    }
}

/// Render one panel's body. Shared by the docked panes and the pop-out windows
/// so a panel looks the same wherever it lives. Only the Viewer needs the live
/// preview texture; it never pops out, so floating windows pass `None`.
pub(crate) fn render_panel(
    ui: &mut egui::Ui,
    theme: &Theme,
    app: &mut AppState,
    preview_display: Option<(egui::TextureId, egui::Vec2)>,
    panel: Panel,
) {
    match panel {
        Panel::Viewer => viewer_panel(ui, theme, app, preview_display),
        Panel::Project => project_panel(ui, theme, app),
        Panel::Timeline => timeline_panel(ui, theme, app),
        Panel::EffectControls => empty_hint(
            ui,
            theme,
            "Effect controls",
            "For now, edit a layer's effect stack on its own row in the Timeline.",
        ),
        Panel::EffectsAndPresets => effects_panel(ui, theme),
        Panel::Scopes => empty_hint(
            ui,
            theme,
            "Scopes",
            "Waveform, vectorscope and histogram arrive with the render pipeline.",
        ),
    }
}

/// The tile holding `panel`, if it is in the tree (each panel appears once).
pub(crate) fn tile_id_of(
    tree: &egui_tiles::Tree<Panel>,
    panel: Panel,
) -> Option<egui_tiles::TileId> {
    tree.tiles.iter().find_map(|(id, tile)| match tile {
        egui_tiles::Tile::Pane(p) if *p == panel => Some(*id),
        _ => None,
    })
}

/// Every pane rendering bare this frame (K-086): a pane is bare unless its
/// parent tile is a Tabs container — single-child Tabs get pruned by
/// [`dock_simplification_options`], so this is exactly the condition
/// `render_panel` draws without a surrounding tab bar. Bare panes get
/// `DockBehavior::bare_pane_ui`'s pop-out and drag-grip affordances; tabbed
/// panes already have both, via the tab bar's own button and tab drag.
pub(crate) fn bare_tile_ids(
    tree: &egui_tiles::Tree<Panel>,
) -> std::collections::HashSet<egui_tiles::TileId> {
    tree.tiles
        .iter()
        .filter(|(_, tile)| matches!(tile, egui_tiles::Tile::Pane(_)))
        .map(|(id, _)| *id)
        .filter(|id| match tree.tiles.parent_of(*id) {
            None => true,
            Some(parent) => !matches!(
                tree.tiles.get(parent),
                Some(egui_tiles::Tile::Container(egui_tiles::Container::Tabs(_)))
            ),
        })
        .collect()
}

/// Bridges the tiling tree to Lumit's panels and house styling.
pub(crate) struct DockBehavior<'a> {
    pub(crate) theme: &'a Theme,
    pub(crate) app: &'a mut AppState,
    pub(crate) preview_display: Option<(egui::TextureId, egui::Vec2)>,
    /// Set when the user clicks a tab group's pop-out button; applied after the
    /// tree is drawn (the panel is hidden here and shown in its own window).
    pub(crate) pop_out: Option<Panel>,
    /// Every docked pane's rect this frame, for the active-panel highlight.
    pub(crate) panel_rects: Vec<(Panel, egui::Rect)>,
    /// The dock's own id (`Tree::id`), needed to build the same `egui::Id`
    /// egui_tiles uses to track a dragged tile (`TileId::egui_id`) — a bare
    /// pane's home-grown drag handle hands off to that same machinery, so a
    /// dragged bare pane re-docks exactly like a dragged tab.
    pub(crate) tree_id: egui::Id,
    /// Panes with no tab bar (K-086): only these get the generic pop-out and
    /// drag-to-move affordances `pane_ui` adds. Tabbed panes already have
    /// both, via the tab bar's own pop-out button and tab drag.
    pub(crate) bare_tiles: std::collections::HashSet<egui_tiles::TileId>,
}

/// The drag-grip's footprint in the top-right corner of a bare pane (a
/// square this many points on a side).
pub(crate) const BARE_PANE_GRIP_SIZE: f32 = 16.0;

/// Paint the drag grip: a small 2×3 dot grid, the house convention for "grab
/// here", `text_muted` normally and brightening to `text_secondary` on
/// hover/drag so it reads as interactive without shouting (K-015 calm UI).
pub(crate) fn paint_bare_pane_grip(ui: &egui::Ui, theme: &Theme, rect: egui::Rect, lit: bool) {
    let colour = if lit {
        theme.text_secondary
    } else {
        theme.text_muted.gamma_multiply(0.5)
    };
    let pad = 4.0;
    let inner = rect.shrink(pad);
    for col in 0..2 {
        for row in 0..3 {
            let x = inner.left() + col as f32 * (inner.width());
            let y = inner.top() + row as f32 * (inner.height() / 2.0);
            ui.painter().circle_filled(egui::pos2(x, y), 1.0, colour);
        }
    }
}

impl DockBehavior<'_> {
    /// A bare (tabless) pane's body: the same content, plus two affordances
    /// a tabbed pane gets from its tab bar instead.
    ///
    /// Right-click anywhere offers "pop out into its own window": a
    /// whole-pane `Sense::click()` background, registered *before* the
    /// content is drawn, so anything the panel renders on top still claims
    /// its own clicks first (the comp-tab-strip background trick,
    /// generalised — pinned by
    /// `strip_background_takes_the_right_click_only_off_the_buttons` and
    /// `bare_pane_background_right_click_pops_out_only_off_content`).
    ///
    /// A small grip in the top-right corner drags the pane: on
    /// `drag_started` it hands off to egui_tiles' own tile-drag machinery
    /// (`Tree::dragged_id`/`move_tile`) via the tile's own `egui::Id`, so
    /// the pane re-docks exactly like a dragged tab. It is interacted
    /// *after* the content, winning its own tiny footprint the way a later,
    /// smaller widget wins over an earlier, larger one — deliberately NOT a
    /// drag sense shared with a wider "near the top" region: proven the
    /// hard way that a drag-sensing region does not yield to overlapping
    /// click-only content the way two click-only widgets do
    /// (`Response::dragged()` needs `Sense::drag`; egui_tiles' own tab
    /// buttons sense `click_and_drag` too, which is *why* a background drag
    /// there correctly steps aside — a plain click-only button has nothing
    /// to contest the drag with, so a shared region always loses it to the
    /// background). See
    /// `bare_pane_drag_grip_moves_the_pane_only_from_its_own_corner`.
    fn bare_pane_ui(&mut self, ui: &mut egui::Ui, tile_id: egui_tiles::TileId, pane: &mut Panel) {
        let pane_rect = ui.max_rect();
        let bg = ui.scope_builder(egui::UiBuilder::new().sense(egui::Sense::click()), |ui| {
            render_panel(ui, self.theme, self.app, self.preview_display, *pane);
            // Claim the full pane rect regardless of what content used,
            // so leftover empty space still answers to `bg` below.
            ui.expand_to_include_rect(pane_rect);
        });
        bg.response.context_menu(|ui| {
            if ui.button("Pop out into its own window").clicked() {
                self.pop_out = Some(*pane);
                ui.close_menu();
            }
        });
        let grip = egui::Rect::from_min_size(
            egui::pos2(pane_rect.right() - BARE_PANE_GRIP_SIZE, pane_rect.top()),
            egui::vec2(BARE_PANE_GRIP_SIZE, BARE_PANE_GRIP_SIZE),
        );
        let handle = ui
            .interact(
                grip,
                ui.id().with("bare-pane-grip"),
                egui::Sense::click_and_drag(),
            )
            .on_hover_cursor(egui::CursorIcon::Grab);
        if handle.drag_started() {
            ui.ctx().set_dragged_id(tile_id.egui_id(self.tree_id));
        }
        paint_bare_pane_grip(ui, self.theme, grip, handle.hovered() || handle.dragged());
    }
}

impl egui_tiles::Behavior<Panel> for DockBehavior<'_> {
    fn pane_ui(
        &mut self,
        ui: &mut egui::Ui,
        tile_id: egui_tiles::TileId,
        pane: &mut Panel,
    ) -> egui_tiles::UiResponse {
        match self.theme.shape {
            // Byte-identical to the pre-K-092 code: no Frame, no behaviour
            // change.
            crate::theme::ThemeShape::Sharp => {
                self.panel_rects.push((*pane, ui.max_rect()));
                if self.bare_tiles.contains(&tile_id) {
                    self.bare_pane_ui(ui, tile_id, pane);
                } else {
                    render_panel(ui, self.theme, self.app, self.preview_display, *pane);
                }
            }
            // Every pane — the Viewer included, per the owner's call — floats
            // as its own rounded, shadowed card. `bare_pane_ui` needs no
            // changes of its own: it derives the click-sensing scope and the
            // grip's corner purely from whatever `ui` it's handed, so it
            // automatically operates on the smaller, padded interior the
            // Frame gives it.
            crate::theme::ThemeShape::Round => {
                let t = self.theme.tokens;
                let resp = egui::Frame::new()
                    .fill(self.theme.surface_1)
                    .corner_radius(t.card_radius)
                    .shadow(t.card_shadow)
                    .inner_margin(t.card_padding)
                    .show(ui, |ui| {
                        if self.bare_tiles.contains(&tile_id) {
                            self.bare_pane_ui(ui, tile_id, pane);
                        } else {
                            render_panel(ui, self.theme, self.app, self.preview_display, *pane);
                        }
                    });
                self.panel_rects.push((*pane, resp.response.rect));
            }
        }
        egui_tiles::UiResponse::None
    }

    fn top_bar_right_ui(
        &mut self,
        tiles: &egui_tiles::Tiles<Panel>,
        ui: &mut egui::Ui,
        _tile_id: egui_tiles::TileId,
        tabs: &egui_tiles::Tabs,
        _scroll_offset: &mut f32,
    ) {
        // A pop-out button for the active tab. Only tab groups have a tab bar
        // (a solo pane renders bare, K-086), so a lone panel offers this
        // elsewhere — the Timeline through its comp strip's context menu.
        // Detaches the panel into its own window.
        if let Some(active) = tabs.active {
            if let Some(egui_tiles::Tile::Pane(panel)) = tiles.get(active) {
                if ui
                    .add(egui::Button::new(crate::icons::text(Icon::PopOut, 12.0)).frame(false))
                    .on_hover_text("Pop out into its own window")
                    .clicked()
                {
                    self.pop_out = Some(*panel);
                }
            }
        }
    }

    fn tab_title_for_pane(&mut self, pane: &Panel) -> egui::WidgetText {
        // The Timeline carries its own in-panel tab strip — one tab per open
        // comp (07-UI-SPEC §4) — so the dock tab keeps the plain panel name.
        pane.title().into()
    }

    fn tab_bar_height(&self, _style: &egui::Style) -> f32 {
        26.0
    }

    fn gap_width(&self, _style: &egui::Style) -> f32 {
        self.theme.tokens.tile_gap
    }

    // The inter-pane divider (K-092): Sharp reproduces egui_tiles' own
    // default exactly (a `tab_bar_color`-toned line at `gap_width`); Round
    // paints the idle gap as the canvas colour instead, at the widened
    // `tile_gap` — since the stroke width equals the gap width, this fills
    // the whole gap with canvas colour with no extra painting. Deliberately
    // NOT done by repointing `tab_bar_color` at the canvas colour: that
    // colour is also the real tab-bar background for stacked groups, and
    // doing so would paint those wrong.
    fn resize_stroke(
        &self,
        style: &egui::Style,
        resize_state: egui_tiles::ResizeState,
    ) -> egui::Stroke {
        let gap = self.theme.tokens.tile_gap;
        match self.theme.shape {
            crate::theme::ThemeShape::Sharp => match resize_state {
                egui_tiles::ResizeState::Idle => {
                    egui::Stroke::new(gap, self.tab_bar_color(&style.visuals))
                }
                egui_tiles::ResizeState::Hovering => style.visuals.widgets.hovered.fg_stroke,
                egui_tiles::ResizeState::Dragging => style.visuals.widgets.active.fg_stroke,
            },
            crate::theme::ThemeShape::Round => match resize_state {
                egui_tiles::ResizeState::Idle => egui::Stroke::new(gap, self.theme.surface_0),
                egui_tiles::ResizeState::Hovering => {
                    egui::Stroke::new(gap, self.theme.hairline_strong)
                }
                egui_tiles::ResizeState::Dragging => egui::Stroke::new(gap, self.theme.accent),
            },
        }
    }

    // Rerun-style panel chrome (K-084): the tab bar sits one surface step above
    // the panel; the active tab takes the panel's own fill so it reads as part
    // of the content below; inactive tabs melt into the bar until hovered.
    fn tab_bar_color(&self, _visuals: &egui::Visuals) -> egui::Color32 {
        self.theme.surface_2
    }

    fn tab_bg_color(
        &self,
        _visuals: &egui::Visuals,
        _tiles: &egui_tiles::Tiles<Panel>,
        _tile_id: egui_tiles::TileId,
        state: &egui_tiles::TabState,
    ) -> egui::Color32 {
        if state.active {
            self.theme.surface_1
        } else {
            self.theme.surface_2
        }
    }

    fn tab_text_color(
        &self,
        _visuals: &egui::Visuals,
        _tiles: &egui_tiles::Tiles<Panel>,
        _tile_id: egui_tiles::TileId,
        state: &egui_tiles::TabState,
    ) -> egui::Color32 {
        if state.active {
            self.theme.text_primary
        } else {
            self.theme.text_muted
        }
    }

    fn simplification_options(&self) -> egui_tiles::SimplificationOptions {
        dock_simplification_options()
    }
}
