# 0015. Classify captures with the `claude` command-line tool

- **Date:** 2026-11-26
- **Status:** Proposed

## Context

The Focus Dashboard takes free-text captures ("call the dentist", "idea: …", "what's the capital of Peru") and files them: a suggested task, a note in the vault, an answer, or a question back when it can't tell ([capture format](../capture-format.md)). Something has to decide which. Rules and keywords won't cope with free text, so a language model is needed, and the owner already has a Claude subscription and the `claude` command-line tool on the Mac.

Before building on it, a spike ran 30 inputs through the tool and compared the answers with hand-made labels.

## Decision

Classify captures by running the `claude` tool as a child process and reading its JSON answer. The call is:

```
claude -p --output-format json --json-schema '<schema>' --no-session-persistence --tools ""
```

run in an **empty folder**, with the prompt built by `CapturePrompt` and the schema from `CaptureSchema` (both in `NowboardKit`). The answer is read from the `structured_output` field of the tool's JSON output and then checked by `CaptureResult.decode`.

- `--json-schema` makes the answer fit the result schema.
- `--no-session-persistence` keeps these calls out of the session history.
- `--tools ""` and the empty folder mean the model can read nothing on the disk: it only sees the prompt. The capture text is data, and the prompt says not to follow instructions inside it.
- No `--bare`: that flag skips the subscription login, so the call would need an API key instead.

What the spike found:

| | |
|---|---|
| Inputs | 30 |
| Matched the label | 28 |
| Failed calls | 0 |
| Time per call | median 2.6 s, p90 3.8 s, max 4.2 s |
| Confidence | unclear inputs scored 0.2 to 0.4, a wrongly filed note 0.55, a correct note 0.60 |

From the confidence numbers, answers below **0.65** are treated as unclear and the person is asked (`CaptureResult.confidenceThreshold`). It's a starting value and sits above the correct note's 0.60, so even a correct note would be asked about. It will need tuning.

**The inputs were synthetic.** Accuracy on real captures is not known yet. The first weeks of real use are the real test; the threshold and the prompt should be revisited then.

The classifier call itself (starting the process, timeouts, reading the output) is not part of the capture core and comes in a later change. The core never runs a process.

## Alternatives considered

- **A local model through Ollama (the fallback):** keeps the text on the machine and needs no subscription, but it needs a model downloaded and running, and wasn't measured in the spike. We keep it as the fallback if the CLI turns out to be too slow, too costly or unavailable. Because the prompt and the result format don't depend on who answers, switching only changes the call.
- **The Anthropic API with a key:** works anywhere and is faster to wire, but means storing an API key in the app and paying per call next to the subscription. `--bare`, which needs it, is the reason it came up.
- **Keywords and rules:** no external dependency, but free text defeats them, and a wrong guess silently files things in the wrong place.

## Consequences

- Capture text, today's date, category ids, the folder map and `_vault-guide.md` leave the machine, because they're in the prompt. The size limits (spec 7) cap how much, and the map lists only folder names.
- The Mac needs the `claude` tool installed and signed in. An iPhone can't start a command-line tool, so a capture typed there can only be saved as a raw file (it is, first, always) and classified later by a Mac. How that hand-over works is not decided here.
- About 3 to 4 seconds per capture is fine for a background step, not for waiting on. The raw file is written first, so the wait never loses text.
- A wrong or low-confidence answer costs one question or one misfiled note, not lost text: the raw capture stays in the Inbox either way.
- Revisit when real captures show worse accuracy than the spike, or when the tool's flags or login behaviour change.
