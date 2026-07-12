//! The application shell: menu bar, docked panels, status line.
//!
//! Layout per docs/07-UI-SPEC.md (Edit workspace): Project left, Viewer centre,
//! Effect Controls / Effects & Presets right, Timeline across the bottom.

use crate::theme::Theme;
use egui_dock::{DockArea, DockState, NodeIndex, Style as DockStyle};
use serde::{Deserialize, Serialize};

/// The dockable panels. Names are glossary names (docs/01-GLOSSARY.md §7).
#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Panel {
    Project,
    Viewer,
    Timeline,
    EffectControls,
    EffectsAndPresets,
    Scopes,
}

impl Panel {
    fn title(&self) -> &'static str {
        match self {
            Panel::Project => "Project",
            Panel::Viewer => "Viewer",
            Panel::Timeline => "Timeline",
            Panel::EffectControls => "Effect controls",
            Panel::EffectsAndPresets => "Effects & presets",
            Panel::Scopes => "Scopes",
        }
    }
}

/// Build the default Edit workspace arrangement.
pub fn default_layout() -> DockState<Panel> {
    let mut state = DockState::new(vec![Panel::Viewer]);
    let surface = state.main_surface_mut();
    // Bottom: Timeline (35% height).
    let [centre, _timeline] =
        surface.split_below(NodeIndex::root(), 0.65, vec![Panel::Timeline]);
    // Left of the Viewer: Project (20% width).
    let [centre, _project] = surface.split_left(centre, 0.22, vec![Panel::Project]);
    // Right of the Viewer: Effect controls with Effects & presets and Scopes tabbed.
    let [_centre, _right] = surface.split_right(
        centre,
        0.78,
        vec![Panel::EffectControls, Panel::EffectsAndPresets, Panel::Scopes],
    );
    state
}

struct PanelViewer<'a> {
    theme: &'a Theme,
}

impl egui_dock::TabViewer for PanelViewer<'_> {
    type Tab = Panel;

    fn title(&mut self, tab: &mut Panel) -> egui::WidgetText {
        tab.title().into()
    }

    fn ui(&mut self, ui: &mut egui::Ui, tab: &mut Panel) {
        match tab {
            Panel::Viewer => viewer_panel(ui, self.theme),
            Panel::Project => empty_hint(
                ui,
                self.theme,
                "No footage yet",
                "Drag files anywhere in the window, or use File → Import.",
            ),
            Panel::Timeline => empty_hint(
                ui,
                self.theme,
                "No composition open",
                "Create one with Composition → New, or drop footage here.",
            ),
            Panel::EffectControls => empty_hint(
                ui,
                self.theme,
                "No layer selected",
                "Select a layer to see its effect stack.",
            ),
            Panel::EffectsAndPresets => effects_panel(ui, self.theme),
            Panel::Scopes => empty_hint(
                ui,
                self.theme,
                "Scopes",
                "Waveform, vectorscope and histogram arrive with the render pipeline.",
            ),
        }
    }
}

/// The Viewer: neutral surround + the empty-project card (docs/07-UI-SPEC.md §13.2).
fn viewer_panel(ui: &mut egui::Ui, theme: &Theme) {
    let rect = ui.available_rect_before_wrap();
    ui.painter().rect_filled(rect, 0.0, theme.viewer_surround);

    ui.scope_builder(egui::UiBuilder::new().max_rect(rect), |ui| {
        ui.centered_and_justified(|ui| {
            ui.vertical_centered(|ui| {
                ui.add_space(rect.height() * 0.32);
                egui::Frame::group(ui.style())
                    .fill(theme.surface_1)
                    .stroke(egui::Stroke::new(1.0, theme.hairline_strong))
                    .corner_radius(egui::CornerRadius::same(8))
                    .inner_margin(egui::Margin::symmetric(28, 20))
                    .show(ui, |ui| {
                        ui.set_max_width(340.0);
                        ui.label(
                            egui::RichText::new("Kiriko")
                                .heading()
                                .color(theme.text_primary),
                        );
                        ui.add_space(2.0);
                        ui.label(
                            egui::RichText::new("Start with footage or a composition.")
                                .color(theme.text_muted),
                        );
                        ui.add_space(12.0);
                        ui.vertical_centered_justified(|ui| {
                            let b = |t: &str| egui::Button::new(t).min_size(egui::vec2(0.0, 28.0));
                            if ui.add(b("Import footage")).clicked()
                                || ui.add(b("New composition")).clicked()
                                || ui.add(b("Open project")).clicked()
                            {
                                // Wired in slice 3 (project) and slice 4 (import).
                            }
                        });
                        ui.add_space(6.0);
                        ui.label(
                            egui::RichText::new("Footage can be dropped anywhere in the window.")
                                .small()
                                .color(theme.text_disabled),
                        );
                    });
            });
        });
    });

    // Viewer bar placeholder (bottom): preview resolution + magnification stubs.
    let bar = egui::Rect::from_min_max(
        egui::pos2(rect.min.x, rect.max.y - 26.0),
        rect.max,
    );
    ui.scope_builder(egui::UiBuilder::new().max_rect(bar), |ui| {
        egui::Frame::new()
            .fill(theme.surface_1)
            .stroke(egui::Stroke::new(1.0, theme.hairline))
            .inner_margin(egui::Margin::symmetric(8, 3))
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.label(egui::RichText::new("Full").small().color(theme.text_secondary));
                    ui.label(egui::RichText::new("·").small().color(theme.text_disabled));
                    ui.label(egui::RichText::new("Fit").small().color(theme.text_secondary));
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        ui.label(
                            egui::RichText::new("sRGB display")
                                .small()
                                .color(theme.text_muted),
                        );
                    });
                });
            });
    });
}

fn effects_panel(ui: &mut egui::Ui, theme: &Theme) {
    ui.add_space(6.0);
    let mut search = String::new();
    ui.add(
        egui::TextEdit::singleline(&mut search)
            .hint_text("Search effects and presets")
            .desired_width(f32::INFINITY),
    );
    ui.add_space(8.0);
    ui.label(
        egui::RichText::new("The effect suite arrives in phase 3.")
            .small()
            .color(theme.text_muted),
    );
}

fn empty_hint(ui: &mut egui::Ui, theme: &Theme, title: &str, hint: &str) {
    ui.add_space(10.0);
    ui.vertical_centered(|ui| {
        ui.label(egui::RichText::new(title).color(theme.text_secondary));
        ui.add_space(2.0);
        ui.label(egui::RichText::new(hint).small().color(theme.text_muted));
    });
}

/// Persisted UI state.
#[derive(Serialize, Deserialize)]
pub struct Shell {
    dock: DockState<Panel>,
    #[serde(skip, default)]
    theme: Theme,
}

impl Default for Shell {
    fn default() -> Self {
        Self { dock: default_layout(), theme: Theme::dark() }
    }
}

impl Shell {
    pub fn new(ctx: &egui::Context, restored: Option<Self>) -> Self {
        let shell = restored.unwrap_or_default();
        shell.theme.apply(ctx);
        ctx.style_mut(|s| s.visuals.panel_fill = shell.theme.surface_0);
        shell
    }

    pub fn ui(&mut self, ctx: &egui::Context) {
        egui::TopBottomPanel::top("menu").show(ctx, |ui| {
            egui::menu::bar(ui, |ui| {
                ui.menu_button("File", |ui| {
                    let _ = ui.button("New project");
                    let _ = ui.button("Open project…");
                    let _ = ui.button("Import footage…");
                    ui.separator();
                    let _ = ui.button("Save");
                });
                ui.menu_button("Edit", |ui| {
                    let _ = ui.button("Undo");
                    let _ = ui.button("Redo");
                });
                ui.menu_button("Composition", |ui| {
                    let _ = ui.button("New composition…");
                    let _ = ui.button("Composition settings…");
                });
                ui.menu_button("Window", |ui| {
                    if ui.button("Reset workspace").clicked() {
                        self.dock = default_layout();
                        ui.close_menu();
                    }
                });
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.label(
                        egui::RichText::new("Edit")
                            .small()
                            .color(self.theme.text_muted),
                    )
                    .on_hover_text("Workspace — presets arrive with the panel set");
                });
            });
        });

        egui::TopBottomPanel::bottom("status").show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.label(
                    egui::RichText::new("Ready")
                        .small()
                        .color(self.theme.text_muted),
                );
            });
        });

        let mut style = DockStyle::from_egui(&ctx.style());
        style.tab_bar.bg_fill = self.theme.surface_0;
        style.tab_bar.hline_color = self.theme.hairline;

        DockArea::new(&mut self.dock)
            .style(style)
            .show(ctx, &mut PanelViewer { theme: &self.theme });
    }
}
