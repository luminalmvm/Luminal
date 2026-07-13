//! Kiriko — entry point.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use kiriko_ui::Shell;

const STORAGE_KEY: &str = "kiriko.shell";

struct KirikoApp {
    shell: Shell,
}

impl KirikoApp {
    fn new(cc: &eframe::CreationContext<'_>) -> Self {
        let restored = cc
            .storage
            .and_then(|s| eframe::get_value::<Shell>(s, STORAGE_KEY));
        // Real GPU information for the boot log (K-008).
        let boot_notes = match cc.wgpu_render_state.as_ref() {
            Some(rs) => {
                let info = rs.adapter.get_info();
                vec![format!("GPU: {} via {:?}", info.name, info.backend)]
            }
            None => vec!["GPU: unavailable — software rendering".to_owned()],
        };
        Self {
            shell: Shell::new(
                &cc.egui_ctx,
                restored,
                boot_notes,
                #[cfg(feature = "media")]
                cc.wgpu_render_state.clone(),
            ),
        }
    }
}

impl eframe::App for KirikoApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.shell.ui(ctx);
    }

    fn save(&mut self, storage: &mut dyn eframe::Storage) {
        eframe::set_value(storage, STORAGE_KEY, &self.shell);
    }
}

fn main() -> eframe::Result<()> {
    // Boot begins as the splash card (K-008): small, frameless, centred; the
    // same window expands into the application when the boot log completes.
    let options = eframe::NativeOptions {
        centered: true,
        persist_window: false,
        viewport: egui::ViewportBuilder::default()
            .with_title("Kiriko")
            .with_inner_size([460.0, 300.0])
            .with_min_inner_size([460.0, 300.0])
            .with_decorations(false)
            .with_resizable(false)
            .with_app_id("kiriko"),
        ..Default::default()
    };
    eframe::run_native(
        "kiriko",
        options,
        Box::new(|cc| Ok(Box::new(KirikoApp::new(cc)))),
    )
}
