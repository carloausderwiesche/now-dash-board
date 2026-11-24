//! Runs the shared conformance cases in `fixtures/task-format/` against this
//! module. The same folder will be run by the Swift port, so both apps read and
//! write task files the same way. What a case looks like: see
//! `fixtures/task-format/README.md`.
//!
//! Rust note: this file is `src/tasks/conformance.rs` and `tasks.rs` declares
//! `mod conformance;`, which makes it a *child* module of `tasks`. A child can
//! use its parent's private functions (`done_time`, `split_frontmatter`…)
//! through `super::`, which a test in the separate `tests/` folder couldn't.

use super::*;
use serde_json::{json, Value as Json};

/// `fixtures/task-format`, found from this crate's folder (`src-tauri/`).
/// `env!` reads an environment variable while compiling; Cargo always sets
/// `CARGO_MANIFEST_DIR` to the folder that holds `Cargo.toml`.
fn fixtures() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../fixtures/task-format")
}

/// A fresh empty folder for one case.
fn temp_dir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("nowboard-fixture-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&d);
    fs::create_dir_all(&d).unwrap();
    d
}

/// A task in the fixtures' JSON shape: the file format's own field names
/// (`done`, not `doneOn`), and `null` for an order the file doesn't have.
fn to_json(t: &Task) -> Json {
    json!({
        "title": t.title,
        "status": t.status,
        "area": t.area,
        "focus": t.focus,
        // `then` turns a bool into an Option: Some(order) only if it's a real number.
        "order": t.order.is_finite().then_some(t.order),
        "created": t.created,
        "done": t.done_on,
        "project": t.project,
        "from": t.from,
        "private": t.private,
        "items": t.items,
        "notes": t.notes,
    })
}

/// JSON has two kinds of number (`-1024` and `-1024.0` aren't equal as JSON),
/// so turn every `order` into a decimal before comparing.
fn normalise(mut task: Json) -> Json {
    if let Some(o) = task.get("order").and_then(Json::as_f64) {
        task["order"] = json!(o);
    }
    task
}

/// Applies a case's `save`/`new` changes to a task, field by field.
fn apply(task: &mut Task, changes: &Json) {
    // `as_object()` gives the JSON object as a map; `into_iter().flatten()` means
    // "loop over it if it's there, else loop over nothing".
    for (key, v) in changes.as_object().into_iter().flatten() {
        let text = || v.as_str().map(str::to_string);
        match key.as_str() {
            "title" => task.title = v.as_str().unwrap().into(),
            "status" => task.status = serde_json::from_value(v.clone()).unwrap(),
            "area" => task.area = v.as_str().unwrap().into(),
            "focus" => task.focus = v.as_bool().unwrap(),
            "order" => task.order = v.as_f64().unwrap(),
            "created" => task.created = text(),
            "done" => task.done_on = text(),
            "project" => task.project = text(),
            "from" => task.from = text(),
            "items" => task.items = serde_json::from_value(v.clone()).unwrap(),
            "notes" => task.notes = v.as_str().unwrap().into(),
            other => panic!("unknown field in fixture: {other}"),
        }
    }
}

/// Compares a written file with the expected one the way the spec defines
/// "kept": same frontmatter keys in the same order with the same values (quoting
/// may differ), and the body byte-for-byte.
fn assert_same_file(case: &str, actual: &str, expected: &str) {
    assert!(actual.starts_with("---\n"), "{case}: written file must start with `---\\n`:\n{actual}");
    let (ay, ab) = split_frontmatter(actual);
    let (ey, eb) = split_frontmatter(expected);
    let parse = |y: Option<&str>| parse_yaml(y.unwrap_or("")).unwrap();
    let (af, ef) = (parse(ay), parse(ey));
    let keys = |m: &Mapping| m.keys().map(|k| k.as_str().unwrap_or("?").to_string()).collect::<Vec<_>>();
    assert_eq!(keys(&af), keys(&ef), "{case}: frontmatter field order\n--- written:\n{actual}");
    assert_eq!(af, ef, "{case}: frontmatter values\n--- written:\n{actual}");
    assert_eq!(ab, eb, "{case}: body must match byte-for-byte");
}

/// One `NN-name.expected.json` case.
fn run_case(name: &str) {
    let base = fixtures();
    let spec: Json =
        serde_json::from_str(&fs::read_to_string(base.join(format!("{name}.expected.json"))).unwrap()).unwrap();
    let file = spec["file"].as_str().expect("`file` is required");
    let input = fs::read_to_string(base.join(format!("{name}.input.md"))).ok();
    let modified = spec["modified"].as_str().map(str::to_string);

    // Reading: parse the file the way `load_all` does when it's the only file in the folder.
    let loaded = input.as_ref().map(|text| {
        let mut t = parse(file, text);
        if t.status == Status::Done {
            t.done_on = done_time(t.done_on, modified.clone());
        }
        t
    });
    if let Some(expected) = spec.get("task") {
        let t = loaded.as_ref().expect("a `task` case needs an input file");
        assert_eq!(normalise(to_json(t)), normalise(expected.clone()), "{name}: parsed task");
    }

    // Writing: only for cases with `save`, `new` or `rename`.
    let after = fs::read_to_string(base.join(format!("{name}.after-save.md"))).ok();
    let writes = ["save", "new", "rename"].iter().any(|k| spec.get(*k).is_some());
    assert_eq!(
        writes,
        after.is_some() || spec["save_error"] == true,
        "{name}: `.after-save.md` and `save`/`new`/`rename` go together"
    );
    if !writes {
        return;
    }

    let dir = temp_dir(name);
    let existing: Vec<String> = serde_json::from_value(spec.get("existing").cloned().unwrap_or(json!([]))).unwrap();
    for other in &existing {
        fs::write(dir.join(other), "x").unwrap();
    }
    if let Some(text) = &input {
        fs::write(dir.join(file), text).unwrap();
    }

    let result = if let Some(changes) = spec.get("new") {
        let mut t = Task {
            id: String::new(),
            title: String::new(),
            status: Status::Backlog,
            area: "personal".into(),
            focus: false,
            order: 0.0,
            created: None,
            done_on: None,
            project: None,
            from: None,
            private: false,
            items: vec![],
            notes: String::new(),
        };
        apply(&mut t, changes);
        save(&dir, t)
    } else {
        let mut t = loaded.expect("`save` and `rename` need an input file");
        if !t.order.is_finite() {
            t.order = 0.0; // the only task in its folder: "on top" is 0
        }
        match spec.get("rename").and_then(Json::as_str) {
            Some(title) => rename(&dir, file, title, t.order),
            None => {
                apply(&mut t, &spec["save"]);
                save(&dir, t)
            }
        }
    };

    if spec["save_error"] == true {
        assert!(result.is_err(), "{name}: saving must be refused");
        assert_eq!(
            fs::read_to_string(dir.join(file)).unwrap(),
            input.unwrap(),
            "{name}: a refused file stays as it was"
        );
        return;
    }
    let saved = result.unwrap_or_else(|e| panic!("{name}: save failed: {e}"));
    let saved_as = spec.get("saved_as").and_then(Json::as_str).unwrap_or(file);
    assert_eq!(saved.id, saved_as, "{name}: file name");
    assert_same_file(name, &fs::read_to_string(dir.join(saved_as)).unwrap(), &after.unwrap());

    // Nothing else is left behind: no `.tmp` file, no old name after a rename.
    let mut left: Vec<String> =
        fs::read_dir(&dir).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into()).collect();
    left.sort();
    let mut want: Vec<String> = existing.into_iter().chain([saved_as.to_string()]).collect();
    want.sort();
    assert_eq!(left, want, "{name}: files in the folder after saving");
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn every_fixture_case_passes() {
    let mut names: Vec<String> = fs::read_dir(fixtures())
        .unwrap()
        .filter_map(|e| e.unwrap().file_name().to_str()?.strip_suffix(".expected.json").map(str::to_string))
        .filter(|n| n != "folder")
        .collect();
    names.sort();
    assert!(names.len() >= 20, "found only {} fixture cases", names.len());

    // Every `.input.md` and `.after-save.md` must belong to a case, so a typo in a
    // file name can't quietly turn a case off.
    for entry in fs::read_dir(fixtures()).unwrap() {
        let file = entry.unwrap().file_name().to_string_lossy().to_string();
        if let Some(case) = file.strip_suffix(".input.md").or_else(|| file.strip_suffix(".after-save.md")) {
            assert!(names.iter().any(|n| n == case), "{file} has no {case}.expected.json");
        }
    }
    for name in &names {
        run_case(name);
    }
}

#[test]
fn file_names_fixture() {
    let spec: Json = serde_json::from_str(&fs::read_to_string(fixtures().join("file-names.json")).unwrap()).unwrap();
    for case in spec["cases"].as_array().unwrap() {
        let title = case["title"].as_str().unwrap();
        assert_eq!(file_stem_for(title), case["stem"].as_str().unwrap(), "title {title:?}");
    }
}

#[test]
fn folder_fixture() {
    let spec: Json =
        serde_json::from_str(&fs::read_to_string(fixtures().join("folder.expected.json")).unwrap()).unwrap();
    // `load_all` only reads, so it can run on the fixture folder itself.
    let mut tasks = load_all(&fixtures().join("folder")).unwrap();
    tasks.sort_by(|a, b| a.id.cmp(&b.id));
    let actual: Vec<Json> = tasks.iter().map(|t| json!({ "file": t.id, "order": t.order })).collect();
    let expected: Vec<Json> = spec["tasks"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| json!({ "file": t["file"], "order": t["order"].as_f64() }))
        .collect();
    assert_eq!(actual, expected);
}
