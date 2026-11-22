//! The Rust side of Nowboard. The React frontend calls the functions marked
//! `#[tauri::command]` with `invoke("list_tasks")` and friends; everything
//! that touches the disk happens here.

mod settings;
mod tasks;

use settings::Settings;
use std::path::PathBuf;
use std::sync::Mutex;
use tasks::Task;
use tauri::{AppHandle, Emitter, Manager, State};

/// Shared state. `Mutex` because Tauri may run commands on several threads.
struct AppState {
    config_dir: PathBuf,
    settings: Mutex<Settings>,
    /// Kept alive here; dropping a watcher stops it.
    watcher: Mutex<Option<notify::RecommendedWatcher>>,
}

impl AppState {
    fn settings(&self) -> Settings {
        self.settings.lock().unwrap().clone()
    }
}

// ---------- commands the frontend can call ----------

#[tauri::command]
fn get_settings(state: State<AppState>) -> Settings {
    state.settings()
}

#[tauri::command]
fn save_settings(app: AppHandle, state: State<AppState>, settings: Settings) -> Result<(), String> {
    settings::save(&state.config_dir, &settings)?;
    *state.settings.lock().unwrap() = settings;
    restart_watcher(&app, &state);
    Ok(())
}

#[tauri::command]
fn list_tasks(state: State<AppState>) -> Result<Vec<Task>, String> {
    tasks::load_all(&state.settings().tasks_dir()?)
}

#[tauri::command]
fn save_task(state: State<AppState>, task: Task) -> Result<Task, String> {
    let mut task = task;
    if task.created.is_none() {
        task.created = Some(now());
    }
    tasks::save(&state.settings().tasks_dir()?, task)
}

#[tauri::command]
fn complete_task(state: State<AppState>, id: String) -> Result<Task, String> {
    let s = state.settings();
    let dir = s.tasks_dir()?;
    let mut task = tasks::load_one(&dir, &id)?;
    task.status = "done".into();
    task.focus = false;
    task.done_on = Some(now());
    let task = tasks::save(&dir, task)?;
    // Logging is a bonus: never fail the "done" because the daily note failed.
    let _ = tasks::log_to_daily_note(&PathBuf::from(&s.vault_path), &s.daily_folder, &task.title);
    Ok(task)
}

/// Renames a task's file to match its new title (the title *is* the file name).
#[tauri::command]
fn rename_task(state: State<AppState>, id: String, title: String, order: f64) -> Result<Task, String> {
    tasks::rename(&state.settings().tasks_dir()?, &id, &title, order)
}

#[tauri::command]
fn delete_task(state: State<AppState>, id: String) -> Result<(), String> {
    tasks::delete(&state.settings().tasks_dir()?, &id)
}

/// The full path of a task file, so the frontend can build an
/// `obsidian://open?path=…` link.
#[tauri::command]
fn task_path(state: State<AppState>, id: String) -> Result<String, String> {
    Ok(state.settings().tasks_dir()?.join(id).to_string_lossy().to_string())
}

/// Opens the task's file in Obsidian through its `obsidian://open` link.
#[tauri::command]
fn open_in_obsidian(app: AppHandle, state: State<AppState>, id: String) -> Result<(), String> {
    use tauri_plugin_opener::OpenerExt;
    let path = state.settings().tasks_dir()?.join(&id);
    let url = format!("obsidian://open?path={}", percent_encode(&path.to_string_lossy()));
    app.opener().open_url(url, None::<&str>).map_err(|e| e.to_string())
}

/// Minimal URL encoding for a file path (spaces, accents, `&`…).
fn percent_encode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' | b'/' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

/// Opens the native "choose a folder" window (Finder on macOS) and returns
/// the folder you picked, or `None` if you pressed Cancel. `title` is shown in
/// the window; `start` is the folder it opens in (e.g. the vault).
///
/// `async` matters here: Tauri runs async commands on a background thread.
/// `blocking_pick_folder` waits until you close the window, and waiting on the
/// main thread would freeze the whole app.
#[tauri::command]
async fn pick_folder(app: AppHandle, title: Option<String>, start: Option<String>) -> Option<String> {
    use tauri_plugin_dialog::DialogExt;
    let mut dialog = app.dialog().file().set_title(title.unwrap_or_else(|| "Choose your Obsidian vault".into()));
    // `if let Some(dir) = …`: only set a start folder if one was given and it exists.
    if let Some(dir) = start.filter(|d| std::path::Path::new(d).is_dir()) {
        dialog = dialog.set_directory(dir);
    }
    let picked = dialog.blocking_pick_folder()?;
    // `?` on an Option: if it's None (cancelled), return None right away.
    let path = picked.into_path().ok()?;
    Some(path.to_string_lossy().to_string())
}

/// Vaults Obsidian already knows about, so Settings can list them.
#[tauri::command]
fn known_vaults(app: AppHandle) -> Vec<String> {
    match app.path().config_dir() {
        Ok(dir) => settings::obsidian_vaults(&dir),
        Err(_) => vec![],
    }
}

/// Local time as `2026-11-22T09:40`, the timestamp format of `created:` and `done:`.
fn now() -> String {
    chrono::Local::now().format("%Y-%m-%dT%H:%M").to_string()
}

// ---------- file watcher ----------

/// Watches the Tasks folder. Any change (from this app or from Obsidian)
/// sends a `tasks-changed` event; the frontend then reloads the list.
fn restart_watcher(app: &AppHandle, state: &AppState) {
    use notify::{RecursiveMode, Watcher};
    let mut slot = state.watcher.lock().unwrap();
    *slot = None; // stop the old one
    let Ok(dir) = state.settings().tasks_dir() else { return };
    if std::fs::create_dir_all(&dir).is_err() {
        return;
    }
    let handle = app.clone();
    let watcher = notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
        if res.is_ok() {
            let _ = handle.emit("tasks-changed", ());
        }
    });
    if let Ok(mut w) = watcher {
        if w.watch(&dir, RecursiveMode::NonRecursive).is_ok() {
            *slot = Some(w);
        }
    }
}

// ---------- quick add from anywhere (⌥ Space) ----------
//
// ⌥ Space opens a small, separate window with only the "new task" box, centred
// a little above the middle of the screen you're on. The board window stays
// where it is. On macOS that window is turned into an NSPanel (the kind of
// window Spotlight/Raycast use): it takes your typing *without* activating the
// whole app, which is what would otherwise pull the board window to the front.

// Describes our panel type for the `tauri-nspanel` plugin. `tauri_panel!` is a
// macro: it writes the Objective-C glue for us at compile time.
#[cfg(target_os = "macos")]
tauri_nspanel::tauri_panel! {
    panel!(QuickPanel {
        config: {
            can_become_key_window: true,
            is_floating_panel: true
        }
    })

    // Listens to macOS window events for the panel. "Resign key" = the panel
    // stopped receiving keyboard input because you clicked somewhere else.
    panel_event!(QuickPanelEvents {
        window_did_become_key(notification: &NSNotification) -> (),
        window_did_resign_key(notification: &NSNotification) -> ()
    })
}

/// Turns the hidden "quick" window into a floating, non-activating panel (macOS only).
fn setup_quick_window(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(target_os = "macos")]
    {
        use tauri_nspanel::{CollectionBehavior, PanelLevel, StyleMask, WebviewWindowExt};
        let Some(window) = app.get_webview_window("quick") else { return Ok(()) };
        let panel = window.to_panel::<QuickPanel>()?;
        // Borderless + "nonactivating": no title bar, and focusing it doesn't activate the app.
        panel
            .set_style_mask(StyleMask::empty().borderless().nonactivating_panel().into())
            .map_err(|e| e.to_string())?;
        panel.set_level(PanelLevel::ModalPanel.value()); // above normal windows
        // Show on whichever desktop (Space) you're on, even over full-screen apps.
        panel.set_collection_behavior(CollectionBehavior::new().can_join_all_spaces().full_screen_auxiliary().into());
        panel.set_transparent(true); // the rounded box draws itself; the rest of the window is see-through
        panel.set_has_shadow(false); // the box has its own CSS shadow

        // Close when you click anywhere else. We use macOS's own signal for this:
        // the web page's "blur" event fires unreliably inside a non-activating panel.
        let events = QuickPanelEvents::new();
        events.window_did_become_key(|_| {
            #[cfg(debug_assertions)]
            eprintln!("quick window became key");
        });
        let handle = app.handle().clone();
        events.window_did_resign_key(move |_| {
            #[cfg(debug_assertions)]
            eprintln!("quick window hidden: resigned key (clicked elsewhere)");
            let _ = handle.emit_to("quick", "quick-closed", ()); // page empties itself
            hide_quick_window(&handle);
        });
        panel.set_event_handler(Some(events.as_ref())); // the panel keeps `events` alive
    }
    #[cfg(not(target_os = "macos"))]
    let _ = app; // nothing to set up elsewhere
    Ok(())
}

/// Puts the quick window centred on the screen under the mouse, a bit above the middle.
fn place_quick_window(app: &AppHandle, window: &tauri::WebviewWindow) {
    // Which screen? The one the mouse is on; if that fails, the main screen.
    let monitor = app
        .cursor_position()
        .ok()
        .and_then(|p| app.monitor_from_point(p.x, p.y).ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten());
    let (Some(m), Ok(size)) = (monitor, window.outer_size()) else { return };
    // Physical pixels (not points), so it works the same on Retina screens.
    let x = m.position().x + (m.size().width as i32 - size.width as i32) / 2;
    let y = m.position().y + ((m.size().height as i32 - size.height as i32) as f64 * 0.32) as i32;
    let _ = window.set_position(tauri::PhysicalPosition::new(x, y));
}

/// ⌥ Space: show the quick window, or hide it if it's already open.
fn toggle_quick(app: &AppHandle) {
    let Some(window) = app.get_webview_window("quick") else { return };
    if window.is_visible().unwrap_or(false) {
        hide_quick_window(app);
        return;
    }
    place_quick_window(app, &window);
    #[cfg(debug_assertions)]
    eprintln!("quick window shown");
    // Tell the page to reset and play its pop-in animation.
    let _ = app.emit_to("quick", "quick-open", ());
    #[cfg(target_os = "macos")]
    {
        use tauri_nspanel::ManagerExt;
        if let Ok(panel) = app.get_webview_panel("quick") {
            panel.order_front_regardless(); // on top, without activating the app
            panel.make_key_window(); // keyboard input goes to this window
            // Inside the window, give keyboard focus to the web page itself.
            // (`show_and_make_key` would focus the window's container view instead;
            // the page then gets a "blur" right away and the box closes again.)
            let _ = window.with_webview(|wv| unsafe {
                use tauri_nspanel::objc2::{msg_send, runtime::AnyObject};
                // Raw Objective-C pointers to the WKWebView and its NSWindow.
                let webview = wv.inner() as *mut AnyObject;
                let ns_window = wv.ns_window() as *mut AnyObject;
                if !webview.is_null() && !ns_window.is_null() {
                    let _: bool = msg_send![&*ns_window, makeFirstResponder: webview];
                }
            });
            return;
        }
    }
    let _ = window.show();
    let _ = window.set_focus();
}

fn hide_quick_window(app: &AppHandle) {
    #[cfg(target_os = "macos")]
    {
        use tauri_nspanel::ManagerExt;
        if let Ok(panel) = app.get_webview_panel("quick") {
            panel.hide();
            return;
        }
    }
    if let Some(w) = app.get_webview_window("quick") {
        let _ = w.hide();
    }
}

/// The quick window calls this when you add a task, press Esc or click elsewhere.
/// Not `async`, so Tauri runs it on the main thread, where macOS wants window changes.
#[tauri::command]
fn hide_quick(app: AppHandle, reason: String) {
    // Only in development builds: print why it closed (Esc, added, clicked elsewhere…).
    #[cfg(debug_assertions)]
    eprintln!("quick window hidden: {reason}");
    let _ = reason;
    hide_quick_window(&app);
}

// ---------- app start ----------

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init()); // native folder picker
    // `let builder = builder.plugin(...)` inside `#[cfg]`: add the panel plugin on macOS only.
    #[cfg(target_os = "macos")]
    let builder = builder.plugin(tauri_nspanel::init());
    builder
        .setup(|app| {
            let config_dir = app.path().app_config_dir()?;
            let state = AppState {
                settings: Mutex::new(settings::load(&config_dir)),
                config_dir,
                watcher: Mutex::new(None),
            };
            app.manage(state);
            restart_watcher(app.handle(), &app.state::<AppState>());
            setup_quick_window(app)?;

            // ⌥ Space from anywhere: open the separate quick-add window.
            #[cfg(desktop)]
            {
                use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};
                let quick_add = Shortcut::new(Some(Modifiers::ALT), Code::Space);
                app.handle().plugin(
                    tauri_plugin_global_shortcut::Builder::new()
                        .with_handler(move |app, shortcut, event| {
                            if shortcut == &quick_add && event.state() == ShortcutState::Pressed {
                                toggle_quick(app);
                            }
                        })
                        .build(),
                )?;
                // If another app already owns ⌥ Space this fails; the app still runs.
                if let Err(e) = app.global_shortcut().register(quick_add) {
                    eprintln!("Could not register ⌥ Space: {e}");
                }
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            save_settings,
            list_tasks,
            save_task,
            complete_task,
            rename_task,
            delete_task,
            task_path,
            open_in_obsidian,
            pick_folder,
            known_vaults,
            hide_quick
        ])
        .run(tauri::generate_context!())
        .expect("error while running Nowboard");
}
