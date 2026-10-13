# Maintaining the analyzer

Read this only when changing the analyzer, the plugins, or this skill in the swift-cyclomatic-complexity-plugin repository.

## Requirements

`Package.swift` declares the Swift tools version, the macOS platform and the swift-syntax version. Don't lower any of them to build on an older machine: the analyzer parses with that swift-syntax release, so tests and scores only mean something against the declared versions. If that toolchain isn't available, say the change could not be built or tested.

## Testing

Run `swift test` from the repository root. It runs:

- `CyclomaticComplexityTests`: unit tests of the scoring rules, identities, configuration, baselines and JSON output, including a golden fixture.
- `PluginIntegrationTests`: builds temporary packages through `CyclomaticComplexityBuildPlugin` to check a clean build, a warning, a failing error, invalid configuration, excluded generated sources, and rebuilds after a configuration change.

## Changing the scoring rules

A change to what counts must update, in the same change:

1. `Sources/CyclomaticComplexity/Analyzer.swift`
2. a unit test that pins the new behavior
3. `skills/swift-cyclomatic-complexity/references/scoring-rules.md`

If the change could alter the scores shown in `references/refactoring-examples.md`, measure those examples again and update the printed output.

## Output and file formats

`scripts/measure.sh` parses the text format: it relies on the `INFO … callables=` line and on operational failures starting with `Error:`. JSON output and baselines carry `schemaVersion`, `metric` and `swiftLanguageVersion`, and a baseline with different values is rejected.

## Evaluations

`evals/evals.json` holds realistic tasks for this skill, with the files each one starts from under `evals/files/` and verifiable expectations. After changing the skill, run each task in a fresh copy of its files with an agent that has the skill loaded, grade every expectation with evidence from the run, and compare against the previous results.

For a baseline without the skill, give the agent a copy of the plugin without `skills/` and without git history. Agents given a full checkout find and read this skill, and can read the evaluations from git.
