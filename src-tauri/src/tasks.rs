//! Tasks are plain markdown files (format v1, see DESIGN.md). This module turns
//! a file into a `Task` and writes a `Task` back. No database: the folder *is*
//! the database, and other programs (Obsidian, MEGA sync, AI agents) write to
//! it too. So we follow three rules when saving:
//!
//! 1. Frontmatter fields we don't know are kept exactly as they are.
//! 2. The body is kept byte-for-byte unless you actually edited the checklist or notes.
//! 3. Writes are atomic: write `.<name>.tmp`, then rename it over the original,
//!    so nobody ever reads a half-written file.
//!
//! ```markdown
//! ---
//! status: today          # today | backlog | done | suggested
//! area: work             # category id (= card colour)
//! order: 1024.5          # float, smaller = higher
//! created: 2026-11-22T09:40
//! done:
//! project:
//! ---
//! - [ ] optional checklist item
//! Free notes.
//! ```
//!
//! The title is the file name: `Fix k6 nightly token.md`. When the title can't
//! be a file name exactly (longer than 80 characters, or it has characters like
//! `:` or `?`), the full title is also kept in the frontmatter as `title:`.

use serde::{Deserialize, Serialize};
use serde_yaml::{Mapping, Value};
use std::fs;
use std::path::{Path, PathBuf};

/// One line of the checklist: `- [ ] text` or `- [x] text`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChecklistItem {
    pub text: String,
    pub done: bool,
}

/// Which list a task is in. An enum instead of a `String`, so a typo like
/// `"tody"` is a compile error. `rename_all = "lowercase"` makes serde read and
/// write it as `today`, `backlog`… in both the frontmatter and the JSON.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Today,
    /// Also what a missing or unknown `status:` becomes.
    #[default]
    Backlog,
    Done,
    Suggested,
}

/// What the frontend sees. `serde` converts it to/from JSON automatically;
/// `rename_all = "camelCase"` makes `done_on` arrive in TypeScript as `doneOn`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Task {
    /// The file name inside the Tasks folder, e.g. `Fix k6 nightly token.md`.
    /// Empty for a task that has not been saved yet.
    #[serde(default)]
    pub id: String,
    /// The file name without `.md`, or the full title from `title:` when the file
    /// name had to be shortened. (For a new task: the title to name the file after.)
    pub title: String,
    pub status: Status,
    /// Category id from the settings, e.g. "work".
    pub area: String,
    /// The one card you're working on (an extra field of this app, not in the spec).
    #[serde(default)]
    pub focus: bool,
    /// Position within its status; smaller = higher. `f64` = a decimal number.
    #[serde(default)]
    pub order: f64,
    #[serde(default)]
    pub created: Option<String>,
    /// Timestamp of completion (`done:` in the file).
    #[serde(default)]
    pub done_on: Option<String>,
    #[serde(default)]
    pub project: Option<String>,
    #[serde(default)]
    pub from: Option<String>,
    /// `#private` appears somewhere in the body. Read-only: computed when loading.
    #[serde(default)]
    pub private: bool,
    #[serde(default)]
    pub items: Vec<ChecklistItem>,
    #[serde(default)]
    pub notes: String,
}

// ---------- reading ----------

/// Splits `---\nyaml\n---\nbody` into (Some(yaml), body). No frontmatter → (None, whole text).
fn split_frontmatter(text: &str) -> (Option<&str>, &str) {
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    if let Some(rest) = text.strip_prefix("---\n").or_else(|| text.strip_prefix("---\r\n")) {
        // The closing `---` may come right away (empty frontmatter) or after some lines.
        let end = if rest.starts_with("---") { Some(0) } else { rest.find("\n---").map(|i| i + 1) };
        if let Some(end) = end {
            let yaml = &rest[..end];
            let after = &rest[end + 3..];
            let body = after.strip_prefix("\r\n").or_else(|| after.strip_prefix('\n')).unwrap_or(after);
            return (Some(yaml), body);
        }
    }
    (None, text)
}

/// The frontmatter as an ordered key → value map. `Mapping` remembers key
/// order, which is what lets us write unknown fields back where they were.
fn parse_yaml(yaml: &str) -> Result<Mapping, String> {
    if yaml.trim().is_empty() {
        return Ok(Mapping::new());
    }
    match serde_yaml::from_str::<Value>(yaml).map_err(|e| e.to_string())? {
        Value::Mapping(m) => Ok(m),
        Value::Null => Ok(Mapping::new()),
        _ => Err("frontmatter is not a list of `key: value` fields".into()),
    }
}

/// A frontmatter value as text: `work` → "work", `1024` → "1024", empty → None.
fn text_of(v: Option<&Value>) -> Option<String> {
    match v? {
        Value::Null => None,
        Value::String(s) if s.trim().is_empty() => None,
        Value::String(s) => Some(s.clone()),
        Value::Bool(b) => Some(b.to_string()),
        Value::Number(n) => Some(n.to_string()),
        // e.g. `project: [[Wiki/X]]` written without quotes parses as a nested list.
        // Show it the way it was meant: as the wiki link text.
        other => serde_yaml::to_string(other).ok().map(|s| s.trim().to_string()),
    }
}

/// Splits the body into checklist items and the remaining free text.
fn parse_body(body: &str) -> (Vec<ChecklistItem>, String) {
    let mut items = Vec::new();
    let mut notes = Vec::new();
    for line in body.lines() {
        let trimmed = line.trim_start();
        if let Some(t) = trimmed.strip_prefix("- [ ] ") {
            items.push(ChecklistItem { text: t.to_string(), done: false });
        } else if let Some(t) = trimmed.strip_prefix("- [x] ").or_else(|| trimmed.strip_prefix("- [X] ")) {
            items.push(ChecklistItem { text: t.to_string(), done: true });
        } else {
            notes.push(line);
        }
    }
    (items, notes.join("\n").trim().to_string())
}

/// Parses one file. `id` is its file name. If it has no `order`, the order is
/// NaN ("not a number") for now; `load_all` then puts it on top.
pub fn parse(id: &str, text: &str) -> Task {
    let (yaml, body) = split_frontmatter(text);
    // Broken YAML → treat like no frontmatter, so the task still shows up.
    let fm = yaml.and_then(|y| parse_yaml(y).ok()).unwrap_or_default();
    let get = |k: &str| fm.get(k);
    let (items, notes) = parse_body(body);

    Task {
        id: id.to_string(),
        title: title_of(id, text_of(get("title"))),
        // Let serde turn `today` into `Status::Today`; anything it doesn't know → Backlog.
        status: get("status").and_then(|v| serde_yaml::from_value(v.clone()).ok()).unwrap_or_default(),
        // `colour:` was this app's old name for the field; still read it.
        area: text_of(get("area")).or_else(|| text_of(get("colour"))).unwrap_or_else(|| "personal".into()),
        focus: matches!(get("focus"), Some(Value::Bool(true))),
        order: get("order").and_then(|v| v.as_f64()).unwrap_or(f64::NAN),
        created: text_of(get("created")),
        done_on: text_of(get("done")),
        project: text_of(get("project")),
        from: text_of(get("from")),
        private: body.contains("#private"),
        items,
        notes,
    }
}

/// Ignored files: hidden ones (including our own `.tmp` files) and README.md.
fn ignored(name: &str) -> bool {
    name.starts_with('.') || name.eq_ignore_ascii_case("README.md") || !name.ends_with(".md")
}

/// Reads every task file in the Tasks folder (flat: subfolders are ignored).
pub fn load_all(dir: &Path) -> Result<Vec<Task>, String> {
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let mut tasks = Vec::new();
    for entry in fs::read_dir(dir).map_err(|e| e.to_string())?.filter_map(Result::ok) {
        let name = entry.file_name().to_string_lossy().to_string();
        if ignored(&name) || !entry.path().is_file() {
            continue;
        }
        if let Ok(text) = fs::read_to_string(entry.path()) {
            let mut task = parse(&name, &text);
            if task.status == Status::Done {
                // `.ok()` turns the Result into an Option, so a file system that can't
                // tell us the modified time simply gives None (and nothing changes).
                let modified = entry
                    .metadata()
                    .and_then(|m| m.modified())
                    .ok()
                    .map(|t| chrono::DateTime::<chrono::Local>::from(t).format("%Y-%m-%dT%H:%M").to_string());
                task.done_on = done_time(task.done_on, modified);
            }
            tasks.push(task);
        }
    }
    // Files without an `order` go on top of their list (smallest order - 1024).
    // We don't write that back; it's only how they're shown until they're moved.
    let top = tasks.iter().map(|t| t.order).filter(|o| o.is_finite()).fold(f64::INFINITY, f64::min);
    let top = if top.is_finite() { top - 1024.0 } else { 0.0 };
    for t in tasks.iter_mut().filter(|t| !t.order.is_finite()) {
        t.order = top;
    }
    Ok(tasks)
}

pub fn load_one(dir: &Path, id: &str) -> Result<Task, String> {
    load_all(dir)?.into_iter().find(|t| t.id == id).ok_or_else(|| format!("Task file not found: {id}"))
}

// ---------- file names ----------

/// When someone else (Obsidian, an agent) marks a task done, they often write
/// `done: 2026-11-22` without a time, or no `done:` at all. Without a time the
/// task would sort below everything finished today; without a date it wouldn't
/// count as done today at all. So we borrow the time the file was last saved
/// (`modified`, same "YYYY-MM-DDTHH:MM" shape). Like a missing `order`, this is
/// only how it's shown: the file isn't rewritten.
fn done_time(done_on: Option<String>, modified: Option<String>) -> Option<String> {
    match (done_on, modified) {
        (None, m) => m,
        // A bare date that matches the day the file was saved → add that time.
        (Some(d), Some(m)) if d.len() == 10 && m.starts_with(&d) => Some(m),
        (d, _) => d,
    }
}

/// `Fix token (2).md` → `Fix token (2)`.
fn stem_of(id: &str) -> &str {
    id.strip_suffix(".md").unwrap_or(id)
}

/// `Fix token (2)` → `Fix token`: the stem without the ` (n)` added on a name clash.
fn without_counter(stem: &str) -> &str {
    // `if let Some(x) = …` only runs the block when the value is there.
    if let Some(open) = stem.rfind(" (") {
        if let Some(num) = stem[open + 2..].strip_suffix(')') {
            if !num.is_empty() && num.chars().all(|c| c.is_ascii_digit()) {
                return &stem[..open];
            }
        }
    }
    stem
}

/// Does a frontmatter `title:` belong to this file? Only if this file name is
/// what that title would produce. If someone renamed the file in Obsidian, the
/// old `title:` no longer matches and the new file name wins.
fn title_matches_file(title: &str, id: &str) -> bool {
    let stem = file_stem_for(title);
    stem == stem_of(id) || stem == without_counter(stem_of(id))
}

/// The title to show: the `title:` field if it belongs to this file, else the file name.
fn title_of(id: &str, field: Option<String>) -> String {
    // `.filter(…)` turns Some(x) into None when the check fails.
    field.filter(|t| title_matches_file(t, id)).unwrap_or_else(|| stem_of(id).to_string())
}

/// Writes or removes `title:` so the full title survives. Needed only when the
/// file name isn't exactly the title. A `title:` we didn't write (one that
/// doesn't match the file name) is left alone, like any other unknown field.
/// Returns true if the frontmatter changed.
fn apply_title(fm: &mut Mapping, id: &str, title: &str) -> bool {
    let key = Value::from("title");
    if title != stem_of(id) && title != without_counter(stem_of(id)) {
        let new = Value::from(title);
        if fm.get(&key) == Some(&new) {
            return false;
        }
        fm.insert(key, new);
        return true;
    }
    let ours = text_of(fm.get(&key)).is_some_and(|t| title_matches_file(&t, id));
    ours && fm.remove(&key).is_some()
}

/// "Fix k6: nightly/token?" → "Fix k6- nightly-token-". Characters that macOS
/// or Obsidian can't have in a file name become `-`; at most 80 characters.
pub fn file_stem_for(title: &str) -> String {
    const BAD: &[char] = &['/', '\\', ':', '*', '?', '"', '<', '>', '|', '#', '^', '[', ']'];
    let clean: String = title.chars().map(|c| if BAD.contains(&c) || c.is_control() { '-' } else { c }).collect();
    // `.chars().take(80)` counts characters, not bytes, so "é" can't be cut in half.
    let short: String = clean.trim().chars().take(80).collect();
    // A leading dot would hide the file (and we'd ignore it), so strip dots and spaces at the ends.
    let stem = short.trim_matches(|c: char| c == '.' || c.is_whitespace()).to_string();
    if stem.is_empty() {
        "Untitled".into()
    } else {
        stem
    }
}

/// A free file name for `title`: `Name.md`, else `Name (2).md`, `Name (3).md`…
/// `current` is the task's own file (when renaming), which doesn't count as taken.
fn free_name(dir: &Path, title: &str, current: Option<&str>) -> String {
    let stem = file_stem_for(title);
    let mut n = 1;
    loop {
        let name = if n == 1 { format!("{stem}.md") } else { format!("{stem} ({n}).md") };
        // Comparing lowercase: macOS treats "Fix.md" and "fix.md" as the same file,
        // so a rename that only changes capitals must not count as a clash with itself.
        let is_self = current.is_some_and(|c| c.to_lowercase() == name.to_lowercase());
        if is_self || (!ignored(&name) && !dir.join(&name).exists()) {
            return name;
        }
        n += 1;
    }
}

/// Refuses ids like `../../.ssh/config.md`: a task may only touch files
/// directly inside the Tasks folder.
fn safe_path(dir: &Path, id: &str) -> Result<PathBuf, String> {
    let rel = Path::new(id);
    let mut parts = rel.components();
    let single = matches!(parts.next(), Some(std::path::Component::Normal(_))) && parts.next().is_none();
    if !single || ignored(id) {
        return Err(format!("Not a task file: {id}"));
    }
    Ok(dir.join(rel))
}

// ---------- writing ----------

/// Writes the file via a temporary file + rename, so it's never half-written.
fn write_atomic(path: &Path, content: &str) -> Result<(), String> {
    let name = path.file_name().ok_or("bad path")?.to_string_lossy();
    let tmp = path.with_file_name(format!(".{name}.tmp"));
    fs::write(&tmp, content).map_err(|e| e.to_string())?;
    fs::rename(&tmp, path).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        e.to_string()
    })
}

/// Turns the frontmatter map back into text, one `key: value` per line.
/// Empty values are written as a bare `key:`, like in the spec.
fn render_yaml(fm: &Mapping) -> Result<String, String> {
    let mut out = String::new();
    for (k, v) in fm {
        if v.is_null() {
            let key = serde_yaml::to_string(k).map_err(|e| e.to_string())?;
            out.push_str(key.trim());
            out.push_str(":\n");
        } else {
            // serde_yaml adds quotes where needed, e.g. "[[Wiki/X]]" stays a string.
            let mut one = Mapping::new();
            one.insert(k.clone(), v.clone());
            out.push_str(&serde_yaml::to_string(&one).map_err(|e| e.to_string())?);
        }
    }
    Ok(out)
}

/// Checklist first, then a blank line, then the notes.
fn render_body(items: &[ChecklistItem], notes: &str) -> String {
    let mut out = String::new();
    for it in items {
        out.push_str(&format!("- [{}] {}\n", if it.done { "x" } else { " " }, it.text));
    }
    if !notes.trim().is_empty() {
        if !out.is_empty() {
            out.push('\n');
        }
        out.push_str(notes.trim());
        out.push('\n');
    }
    out
}

/// Whole numbers are written without ".0": `1024`, but `1024.5` stays.
fn order_value(o: f64) -> Value {
    if o.fract() == 0.0 && o.abs() < 1e15 {
        Value::from(o as i64)
    } else {
        Value::from(o)
    }
}

/// Saves a task. A new task (empty id) gets a file named after its title.
/// An existing file keeps its unknown fields and, unless you edited the
/// checklist or notes, its body exactly as it was. Renaming is separate (`rename`).
pub fn save(dir: &Path, mut task: Task) -> Result<Task, String> {
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let is_new = task.id.is_empty();
    if is_new {
        task.id = free_name(dir, &task.title, None);
    }
    let path = safe_path(dir, &task.id)?;

    // Start from what's on disk right now (another program may have changed it).
    let existing = if is_new { None } else { fs::read_to_string(&path).ok() };
    let (mut fm, old_body) = match &existing {
        Some(text) => {
            let (yaml, body) = split_frontmatter(text);
            let fm = match yaml {
                Some(y) => parse_yaml(y).map_err(|e| {
                    format!("Not saving {}: its frontmatter isn't valid YAML ({e}). Fix it in Obsidian first.", task.id)
                })?,
                None => Mapping::new(),
            };
            (fm, Some(body.to_string()))
        }
        None => (Mapping::new(), None),
    };

    // Set the fields this app owns. `insert` on an existing key keeps its position.
    let set = |fm: &mut Mapping, k: &str, v: Value| {
        fm.insert(Value::from(k), v);
    };
    let opt = |s: &Option<String>| s.as_ref().map(|x| Value::from(x.as_str())).unwrap_or(Value::Null);
    set(&mut fm, "status", serde_yaml::to_value(task.status).map_err(|e| e.to_string())?);
    set(&mut fm, "area", Value::from(task.area.as_str()));
    fm.remove("colour"); // old name of `area`
    if task.order.is_finite() {
        set(&mut fm, "order", order_value(task.order));
    }
    if task.created.is_some() || is_new {
        set(&mut fm, "created", opt(&task.created));
    }
    set(&mut fm, "done", opt(&task.done_on));
    if task.focus {
        set(&mut fm, "focus", Value::Bool(true));
    } else {
        fm.remove("focus");
    }
    if is_new && !fm.contains_key("project") {
        set(&mut fm, "project", opt(&task.project));
    }
    apply_title(&mut fm, &task.id, &task.title);

    // Keep the body untouched unless the checklist or notes actually changed.
    let body = match old_body {
        Some(b) if parse_body(&b) == (task.items.clone(), task.notes.trim().to_string()) => b,
        _ => render_body(&task.items, &task.notes),
    };

    let text = format!("---\n{}---\n{}", render_yaml(&fm)?, body);
    write_atomic(&path, &text)?;
    Ok(parse_with_order(&task.id, &text, task.order))
}

/// `parse`, but keeping the order we already know (for files without one).
fn parse_with_order(id: &str, text: &str, order: f64) -> Task {
    let mut t = parse(id, text);
    if !t.order.is_finite() {
        t.order = if order.is_finite() { order } else { 0.0 };
    }
    t
}

/// Renames the task's file to match a new title. Returns the task with its new id.
pub fn rename(dir: &Path, id: &str, title: &str, order: f64) -> Result<Task, String> {
    let from = safe_path(dir, id)?;
    let name = free_name(dir, title, Some(id));
    let to = safe_path(dir, &name)?;
    if name != id {
        fs::rename(&from, &to).map_err(|e| e.to_string())?;
    }
    let mut text = fs::read_to_string(&to).map_err(|e| e.to_string())?;
    // The file name may be a shortened title: keep the full one in `title:`.
    let (yaml, body) = split_frontmatter(&text);
    // No frontmatter yet → start an empty one (it's only written if `title:` is needed).
    // Broken YAML → leave the file alone; the title is then just the file name.
    if let Ok(mut fm) = yaml.map(parse_yaml).unwrap_or(Ok(Mapping::new())) {
        // A `title:` that belonged to the *old* file name was ours: drop it first,
        // `apply_title` writes a new one if the new name needs it.
        let mut changed = false;
        if text_of(fm.get("title")).is_some_and(|t| title_matches_file(&t, id)) {
            fm.remove("title");
            changed = true;
        }
        // `|` (not `||`) so `apply_title` always runs, even when `changed` is already true.
        if apply_title(&mut fm, &name, title.trim()) | changed {
            let new_text = format!("---\n{}---\n{}", render_yaml(&fm)?, body);
            write_atomic(&to, &new_text)?;
            text = new_text;
        }
    }
    Ok(parse_with_order(&name, &text, order))
}

/// Marks a task done at `now` and ends its focus. Only the task's own file is
/// written, never a daily note (you may be typing in it): daily notes list
/// finished tasks with a query instead, see docs/adr/0003.
pub fn complete(dir: &Path, id: &str, now: &str) -> Result<Task, String> {
    let mut task = load_one(dir, id)?;
    task.status = Status::Done;
    task.focus = false;
    task.done_on = Some(now.to_string());
    save(dir, task)
}

pub fn delete(dir: &Path, id: &str) -> Result<(), String> {
    let path = safe_path(dir, id)?;
    fs::remove_file(path).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A fresh empty folder for one test.
    fn temp_dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("nowboard-test-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn parses_spec_example() {
        let text = "---\nstatus: today\narea: work\norder: 1024.5\ncreated: 2026-11-22T09:40\ndone:\nproject: \"[[Wiki/Projects/uKonn-X]]\"\n---\n- [ ] optional checklist item\n- [x] another one\nFree text notes below the checklist are allowed.\n";
        let t = parse("Fix k6 nightly token.md", text);
        assert_eq!(t.title, "Fix k6 nightly token");
        assert_eq!(t.status, Status::Today);
        assert_eq!(t.area, "work");
        assert_eq!(t.order, 1024.5);
        assert_eq!(t.created.as_deref(), Some("2026-11-22T09:40"));
        assert_eq!(t.done_on, None);
        assert_eq!(t.project.as_deref(), Some("[[Wiki/Projects/uKonn-X]]"));
        assert_eq!(t.items.len(), 2);
        assert!(t.items[1].done);
        assert_eq!(t.notes, "Free text notes below the checklist are allowed.");
        assert!(!t.private);
    }

    #[test]
    fn plain_note_without_frontmatter() {
        let t = parse("Buy milk.md", "Remember the oat one #private");
        assert_eq!(t.title, "Buy milk");
        assert_eq!(t.status, Status::Backlog);
        assert_eq!(t.area, "personal");
        assert!(t.order.is_nan());
        assert!(t.private);
    }

    #[test]
    fn unknown_status_falls_back_to_backlog() {
        assert_eq!(parse("A.md", "---\nstatus: suggested\n---\n").status, Status::Suggested);
        assert_eq!(parse("A.md", "---\nstatus: someday\n---\n").status, Status::Backlog);
        assert_eq!(parse("A.md", "---\nstatus: 3\n---\n").status, Status::Backlog);
    }

    #[test]
    fn file_names() {
        assert_eq!(file_stem_for("Fix k6: nightly/token?"), "Fix k6- nightly-token-");
        assert_eq!(file_stem_for("[[link]] #tag ^block"), "--link-- -tag -block");
        assert_eq!(file_stem_for("  .hidden  "), "hidden");
        assert_eq!(file_stem_for("!!!"), "!!!");
        assert_eq!(file_stem_for(""), "Untitled");
        assert_eq!(file_stem_for(&"é".repeat(100)).chars().count(), 80);
    }

    #[test]
    fn rejects_paths_outside_the_folder() {
        let d = Path::new("/vault/Notes/Tasks");
        assert!(safe_path(d, "../secret.md").is_err());
        assert!(safe_path(d, "/etc/passwd.md").is_err());
        assert!(safe_path(d, "sub/x.md").is_err());
        assert!(safe_path(d, ".hidden.md").is_err());
        assert!(safe_path(d, "README.md").is_err());
        assert!(safe_path(d, "Fix it.md").is_ok());
    }

    #[test]
    fn save_keeps_unknown_fields_and_body() {
        let dir = temp_dir("keep");
        let original = "---\nstatus: backlog\narea: work\nagent_note: keep me\norder: 10\ncreated: 2026-11-20T08:00\ndone:\nfrom: \"[[Notes/2026-11-22]]\"\n---\nSome  odd   spacing\n\n- [ ] step\n";
        fs::write(dir.join("Task.md"), original).unwrap();
        let mut t = load_one(&dir, "Task.md").unwrap();
        t.status = Status::Today;
        t.order = 5.5;
        save(&dir, t).unwrap();
        let after = fs::read_to_string(dir.join("Task.md")).unwrap();
        assert_eq!(
            after,
            "---\nstatus: today\narea: work\nagent_note: keep me\norder: 5.5\ncreated: 2026-11-20T08:00\ndone:\nfrom: '[[Notes/2026-11-22]]'\n---\nSome  odd   spacing\n\n- [ ] step\n"
        );
        assert!(!dir.join(".Task.md.tmp").exists());
    }

    #[test]
    fn new_tasks_get_title_file_names() {
        let dir = temp_dir("new");
        let t = |title: &str| Task {
            id: String::new(),
            title: title.into(),
            status: Status::Today,
            area: "work".into(),
            focus: false,
            order: -1024.0,
            created: Some("2026-11-22T09:40".into()),
            done_on: None,
            project: None,
            from: None,
            private: false,
            items: vec![],
            notes: String::new(),
        };
        let a = save(&dir, t("Fix: token")).unwrap();
        let b = save(&dir, t("Fix: token")).unwrap();
        assert_eq!(a.id, "Fix- token.md");
        assert_eq!(b.id, "Fix- token (2).md");
        assert_eq!(a.order, -1024.0);
        let text = fs::read_to_string(dir.join(&a.id)).unwrap();
        // `:` can't be in a file name, so the real title is kept in `title:`.
        assert_eq!(text, "---\nstatus: today\narea: work\norder: -1024\ncreated: 2026-11-22T09:40\ndone:\nproject:\ntitle: 'Fix: token'\n---\n");
        assert_eq!(a.title, "Fix: token");
        assert_eq!(b.title, "Fix: token");
        let c = save(&dir, t("Plain")).unwrap();
        assert!(!fs::read_to_string(dir.join(&c.id)).unwrap().contains("title:"));
    }

    #[test]
    fn long_titles_are_kept_whole() {
        let dir = temp_dir("long");
        let long = "Write the quarterly review summary for the platform team including the k6 nightly results";
        fs::write(dir.join("Short.md"), "---\nstatus: today\n---\nbody\n").unwrap();
        let t = rename(&dir, "Short.md", long, 1.0).unwrap();
        assert_eq!(t.id.chars().count(), 80 + 3);
        assert_eq!(t.title, long);
        assert!(fs::read_to_string(dir.join(&t.id)).unwrap().ends_with("---\nbody\n"));
        // Renaming back to a short title removes the field again.
        let t = rename(&dir, &t.id, "Short", 1.0).unwrap();
        assert_eq!(t.title, "Short");
        assert!(!fs::read_to_string(dir.join("Short.md")).unwrap().contains("title:"));
    }

    #[test]
    fn done_without_a_time_borrows_the_file_time() {
        let m = || Some("2026-11-22T15:07".to_string());
        assert_eq!(done_time(None, m()), m());
        assert_eq!(done_time(Some("2026-11-22".into()), m()), m());
        // A real time is kept, and a bare date from another day isn't touched.
        assert_eq!(done_time(Some("2026-11-22T09:40".into()), m()).as_deref(), Some("2026-11-22T09:40"));
        assert_eq!(done_time(Some("2026-11-20".into()), m()).as_deref(), Some("2026-11-20"));
        assert_eq!(done_time(None, None), None);
    }

    #[test]
    fn completing_a_task_writes_only_its_own_file() {
        let vault = temp_dir("complete");
        let dir = vault.join("Notes/Tasks");
        fs::create_dir_all(&dir).unwrap();
        fs::create_dir_all(vault.join("Daily")).unwrap();
        fs::write(dir.join("Buy milk.md"), "---\nstatus: today\nfocus: true\n---\n").unwrap();
        // A daily note you're in the middle of typing (no line break at the end yet).
        let note = vault.join("Daily/2026-11-22.md");
        fs::write(&note, "# Sunday\nhalf a thought").unwrap();

        let t = complete(&dir, "Buy milk.md", "2026-11-22T10:40").unwrap();
        assert_eq!((t.status, t.focus, t.done_on.as_deref()), (Status::Done, false, Some("2026-11-22T10:40")));
        assert_eq!(fs::read_to_string(&note).unwrap(), "# Sunday\nhalf a thought");
        assert_eq!(fs::read_dir(vault.join("Daily")).unwrap().count(), 1);
        assert_eq!(fs::read_dir(&vault).unwrap().count(), 2); // still only Notes/ and Daily/
    }

    #[test]
    fn stale_or_foreign_title_fields_are_ignored() {
        // Renamed in Obsidian: the old `title:` no longer fits the file name.
        let t = parse("Renamed.md", "---\ntitle: 'Old: name'\n---\n");
        assert_eq!(t.title, "Renamed");
        // A clash counter doesn't stop the field from counting.
        let t = parse("Fix- token (2).md", "---\ntitle: 'Fix: token'\n---\n");
        assert_eq!(t.title, "Fix: token");
    }

    #[test]
    fn rename_moves_the_file() {
        let dir = temp_dir("rename");
        fs::write(dir.join("Old.md"), "---\nstatus: today\narea: work\norder: 1\n---\nbody\n").unwrap();
        fs::write(dir.join("Taken.md"), "x").unwrap();
        let t = rename(&dir, "Old.md", "Taken", 1.0).unwrap();
        assert_eq!(t.id, "Taken (2).md");
        assert_eq!(t.title, "Taken (2)");
        assert!(!dir.join("Old.md").exists());
        let t = rename(&dir, "Taken (2).md", "taken (2)", 1.0).unwrap(); // only capitals change
        assert_eq!(t.id, "taken (2).md");
    }

    #[test]
    fn files_without_order_go_on_top_and_ignored_files_are_skipped() {
        let dir = temp_dir("load");
        fs::write(dir.join("A.md"), "---\nstatus: backlog\norder: 100\n---\n").unwrap();
        fs::write(dir.join("B.md"), "just text").unwrap();
        fs::write(dir.join("README.md"), "about this folder").unwrap();
        fs::write(dir.join(".A.md.tmp"), "half written").unwrap();
        let mut all = load_all(&dir).unwrap();
        all.sort_by(|a, b| a.id.cmp(&b.id));
        assert_eq!(all.len(), 2);
        assert_eq!(all[1].order, 100.0 - 1024.0);
    }
}
