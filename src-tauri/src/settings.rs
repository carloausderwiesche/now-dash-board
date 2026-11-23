//! App settings, saved as JSON in the app's config folder
//! (on macOS: ~/Library/Application Support/com.nestoririondo.nowboard/settings.json).

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Category {
    /// Written into each task's frontmatter as `colour: <id>`.
    pub id: String,
    pub name: String,
    /// One of the palette keys in `PALETTE` in src/themes.ts, e.g. "rose" or "indigo".
    pub color: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    /// Absolute path of the Obsidian vault. Empty until you set it.
    pub vault_path: String,
    /// Folder inside the vault that holds one .md file per task.
    pub tasks_folder: String,
    pub theme: String,
    pub categories: Vec<Category>,
    /// Smaller cards. `#[serde(default)]` on the struct means an older settings
    /// file without this field still loads, with `false` (Rust's default for bool).
    pub compact: bool,
}

impl Default for Settings {
    fn default() -> Self {
        let cat =
            |id: &str, name: &str, color: &str| Category { id: id.into(), name: name.into(), color: color.into() };
        Settings {
            // Handy during development: NOWBOARD_VAULT=/path/to/vault npm run app
            vault_path: std::env::var("NOWBOARD_VAULT").unwrap_or_default(),
            tasks_folder: "Notes/Tasks".into(),
            theme: "braun".into(),
            categories: vec![
                cat("personal", "Personal", "rose"),
                cat("work", "Work", "blue"),
                cat("freelance", "Freelance", "amber"),
            ],
            compact: false,
        }
    }
}

impl Settings {
    pub fn tasks_dir(&self) -> Result<PathBuf, String> {
        if self.vault_path.trim().is_empty() {
            return Err("Choose your vault folder in Settings first.".into());
        }
        Ok(PathBuf::from(&self.vault_path).join(&self.tasks_folder))
    }
}

pub fn load(config_dir: &Path) -> Settings {
    let file = config_dir.join("settings.json");
    let mut s: Settings = fs::read_to_string(file).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default();
    // Task format v1 moved tasks from `Tasks/` to `Notes/Tasks/`. Settings saved
    // with the old default follow along; a folder you chose yourself is left alone.
    if s.tasks_folder == "Tasks" {
        s.tasks_folder = "Notes/Tasks".into();
    }
    s
}

pub fn save(config_dir: &Path, s: &Settings) -> Result<(), String> {
    fs::create_dir_all(config_dir).map_err(|e| e.to_string())?;
    let json = serde_json::to_string_pretty(s).map_err(|e| e.to_string())?;
    fs::write(config_dir.join("settings.json"), json).map_err(|e| e.to_string())
}

// ---------- vaults Obsidian already knows ----------

/// Obsidian keeps a list of every vault you've opened in `obsidian.json`
/// (on macOS: ~/Library/Application Support/obsidian/obsidian.json).
/// We read it so Settings can offer those vaults instead of making you type a path.
/// `config_root` is the OS config folder (`app.path().config_dir()` in lib.rs).
pub fn obsidian_vaults(config_root: &Path) -> Vec<String> {
    // `.map(...).unwrap_or_default()`: if the file is missing or unreadable we
    // simply return an empty list — not having Obsidian installed isn't an error.
    fs::read_to_string(config_root.join("obsidian").join("obsidian.json"))
        .map(|json| parse_obsidian_vaults(&json))
        .unwrap_or_default()
}

/// Pulls the vault paths out of obsidian.json, most recently used first.
/// The file looks like `{"vaults": {"<id>": {"path": "...", "ts": 1700000000000}}}`.
pub fn parse_obsidian_vaults(json: &str) -> Vec<String> {
    // `serde_json::Value` is "any JSON"; we don't need a full struct for two fields.
    let Ok(root) = serde_json::from_str::<serde_json::Value>(json) else { return vec![] };
    let Some(vaults) = root.get("vaults").and_then(|v| v.as_object()) else { return vec![] };
    // Collect (timestamp, path) pairs, skipping anything that isn't shaped as expected.
    let mut found: Vec<(i64, String)> = vaults
        .values()
        .filter_map(|v| {
            let path = v.get("path")?.as_str()?.to_string(); // `?` = "give up on this one if missing"
            let ts = v.get("ts").and_then(|t| t.as_i64()).unwrap_or(0);
            Some((ts, path))
        })
        .collect();
    found.sort_by_key(|(ts, _)| std::cmp::Reverse(*ts)); // newest first
    found.into_iter().map(|(_, path)| path).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_obsidian_vault_list_newest_first() {
        let json = r#"{"vaults":{
            "a":{"path":"/Users/me/Old","ts":100},
            "b":{"path":"/Users/me/New","ts":200,"open":true},
            "c":{"ts":300}
        }}"#;
        assert_eq!(parse_obsidian_vaults(json), vec!["/Users/me/New", "/Users/me/Old"]);
    }

    #[test]
    fn settings_from_an_older_version_still_load() {
        let old = r#"{"vaultPath":"/v","tasksFolder":"Notes/Tasks","dailyFolder":"Daily","theme":"walnut"}"#;
        let s: Settings = serde_json::from_str(old).unwrap();
        assert_eq!((s.vault_path.as_str(), s.theme.as_str()), ("/v", "walnut"));
        assert_eq!(s.categories.len(), 3); // missing fields get their defaults
    }

    #[test]
    fn broken_obsidian_json_gives_empty_list() {
        assert!(parse_obsidian_vaults("not json").is_empty());
        assert!(parse_obsidian_vaults("{}").is_empty());
    }
}
