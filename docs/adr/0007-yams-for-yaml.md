# 0007. The Swift app reads frontmatter with Yams, but decides what values mean itself

- **Date:** 2026-11-24
- **Status:** Accepted

## Context

`NowboardKit`, the Swift package behind the new app ([ADR 0006](0006-native-swiftui-app.md)), has to read and write the YAML frontmatter of task files exactly as [docs/task-format.md](../task-format.md) says, and pass the same fixtures as the Rust code. That needs:

- refusing invalid YAML (fixture 07), so a broken file is never overwritten;
- keeping unknown fields, in order, with their values (fixtures 08, 18);
- reading values the way Rust's `serde_yaml` does, which follows YAML 1.2.

Swift has no YAML parser built in.

## Decision

Use **[Yams](https://github.com/jpsim/Yams)** (`from: "6.0.0"`, pinned to 6.2.2 in `Package.resolved`), the standard Swift YAML library built on libyaml. It's the only dependency of `NowboardKit`.

We only use Yams to **parse YAML into nodes and write nodes back**. What a value *means* is decided in `Frontmatter.swift` (`YAMLValue`), from the raw text and its quoting, following YAML 1.2. Yams' own interpretation follows the older YAML 1.1, where `yes` and `on` are booleans and `2026-11-22` is a date: that would turn `focus: yes` on and break `done:` dates. The strings we write ourselves are quoted by our own rule too, because Yams would write the title `true` or the category id `2026` without quotes.

## Alternatives considered

- **A hand-written frontmatter parser:** no dependency, and unknown fields could be kept as raw text (even comments). But it can't tell valid YAML from invalid YAML, so it couldn't refuse a broken file the way Rust does, and nested values (lists, maps) would need their own parser.
- **Using Yams' `Decodable` support or its default value interpretation:** less code, but the YAML 1.1 rules above would quietly disagree with the Rust app.

## Consequences

- Both apps refuse the same broken files and keep unknown fields the same way. All fixtures pass in Swift.
- A dependency to keep up to date (it's small, mature and widely used).
- Values that Yams re-writes may change their quoting (`"[[X]]"` → `'[[X]]'`) and lose YAML comments, the same as in Rust. The spec allows this.
- We'd revisit this if Yams stops being maintained, or if keeping unknown fields as raw text (with comments) becomes important.
