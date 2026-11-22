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
/// the folder you picked, or `None` if you pressed Cancel.
///
/// `async` matters here: Tauri runs async commands on a background thread.
/// `blocking_pick_folder` waits until you close the window, and waiting on the
/// main thread would freeze the whole app.
#[tauri::command]
async fn pick_folder(app: AppHandle) -> Option<String> {
    use tauri_plugin_dialog::DialogExt;
    let picked = app.dialog().file().set_title("Choose your Obsidian vault").blocking_pick_folder()?;
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

// ---------- app start ----------

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init()) // native folder picker
        .setup(|app| {
            let config_dir = app.path().app_config_dir()?;
            let state = AppState {
                settings: Mutex::new(settings::load(&config_dir)),
                config_dir,
                watcher: Mutex::new(None),
            };
            app.manage(state);
            restart_watcher(app.handle(), &app.state::<AppState>());

            // ⌥ Space from anywhere: bring the window forward and open quick add.
            #[cfg(desktop)]
            {
                use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};
                let quick_add = Shortcut::new(Some(Modifiers::ALT), Code::Space);
                app.handle().plugin(
                    tauri_plugin_global_shortcut::Builder::new()
                        .with_handler(move |app, shortcut, event| {
                            if shortcut == &quick_add && event.state() == ShortcutState::Pressed {
                                if let Some(w) = app.get_webview_window("main") {
                                    let _ = w.unminimize();
                                    let _ = w.show();
                                    let _ = w.set_focus();
                                }
                                let _ = app.emit("quick-add", ());
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
            known_vaults
        ])
        .run(tauri::generate_context!())
        .expect("error while running Nowboard");
}
