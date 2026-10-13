# Running swift-complexity directly

`scripts/measure.sh` covers normal checks. Use the CLI directly for JSON output, Xcode-style diagnostics, or baselines.

## Invocation

From the plugin repository: `swift run swift-complexity <paths> [options]`.

From any other directory: `swift run --package-path <plugin checkout> swift-complexity <paths> [options]`.

`swift run` writes build progress to stderr, so stdout carries only the analyzer's output. Paths can be `.swift` files or directories.

| Option | Effect |
|---|---|
| `--format text\|json\|xcode` | Output format; `text` is the default |
| `--explain` | One line (text) or `note:` (xcode) per decision |
| `--config FILE` | Use this configuration instead of discovering one |
| `--warning-threshold N`, `--error-threshold N` | Override the thresholds for one run |
| `--warnings-as-errors` | Fail on warnings too |
| `--write-baseline FILE`, `--baseline FILE`, `--fail-on-regression`, `--root DIR` | See Baselines |

## Output formats

**text** goes to stdout. Each callable gets one line with its severity (`ACCEPTABLE`, `WARNING`, `ERROR`), `path:line:column`, display name, `[identity]`, `complexity=N`, and a summary by kind, or `baseline only` when it has no decisions. Each file with callables gets an `INFO` line with `aggregate`, `max` and `callables`. A parse error prints `ERROR path:line:column parse-error: message`. This is the only format that confirms which callables were measured.

**json** goes to stdout. The envelope has `schemaVersion: 1`, `metric: "swift-mccabe"` and `swiftLanguageVersion: "6.4"`; treat any other values as unsupported. Scores are in `reports[].results[]`, with `identity`, `name`, `kind`, `location`, `complexity` and `contributions[]`. Parse errors are in `reports[].parseIssues[]`, and `deltas[]` is filled only with `--baseline`. JSON has no severity field, so derive severity from the thresholds in effect.

**xcode** goes to stderr only, and stdout stays empty. It prints `path:line:column: warning|error: cyclomatic complexity N for 'name' [summary]; budget: warning >= W, error >= E`. Acceptable callables print nothing, so a clean run and a run that measured nothing look the same.

## Exit status

| Status | Meaning |
|---|---|
| 0 | No error-level callable and every file parsed. Also returned when nothing was measured. |
| 1, report printed | An error-level callable, a parse error, a warning under `--warnings-as-errors`, or a regression under `--fail-on-regression`. |
| 1, `Error: …` on stderr | Operational failure, such as a `.swift-complexity.json` that is not valid JSON, or a baseline that is unreadable or from an incompatible version. No scores. |
| 64, usage text on stderr | Invalid invocation or policy: a missing path, a non-`.swift` file, invalid thresholds, or conflicting configuration files. |

## Which files are measured

Directories are searched recursively, skipping hidden files and package bundles. A file is skipped silently when any component of its absolute path matches `excludedPathComponents`, even if you named the file explicitly. The defaults are `.build`, `DerivedData` and `Generated`.

## Configuration

For each measured file, the analyzer walks up the directory tree and uses the first `.swift-complexity.json` it finds. All inputs in one run must resolve to the same file, or all to none; otherwise the run exits 64. Keys that are missing take their defaults:

```json
{
  "warningThreshold": 3,
  "errorThreshold": 7,
  "excludedPathComponents": [".build", "DerivedData", "Generated"],
  "warningsAsErrors": false,
  "explainErrors": true
}
```

`explainErrors` adds `note:` lines to error-level xcode diagnostics.

## Baselines

- `--write-baseline FILE` saves every score, even when the run fails.
- `--baseline FILE` compares against a saved baseline. Changed callables show the change in text output, such as `(baseline 2, +2)`, and removed callables print as `INFO … removed from current source` lines.
- `--fail-on-regression` makes any increase exit 1.
- `--root DIR` makes baseline paths relative. It defaults to the current directory, so compare with the same root that wrote the baseline.

Unnamed closures are identified by position (`closure#1`, `closure#2`), so inserting a closure renames the ones after it, and they show as removed and added. A closure assigned to a name (`let work = { … }`) is identified as `closure[work]` and keeps its identity.
