# Maintaining the analyzer

Read this only when changing the analyzer, the plugins, or this skill in the swift-cyclomatic-complexity-plugin repository.

## Requirements

The package targets `swift-tools-version: 6.4`, macOS 27 and swift-syntax 604. Never lower the tools version, the platform, or dependency versions to run on an older machine. If Swift 6.4 is not available, say the change could not be built or tested.

## Testing

Run `swift test` from the repository root. It runs:

- `CyclomaticComplexityTests`: unit tests of the scoring rules, identities, configuration, baselines and JSON output, including a golden fixture.
- `PluginIntegrationTests`: builds temporary packages through `CyclomaticComplexityBuildPlugin` to check a clean build, a warning, a failing error, invalid configuration, excluded generated sources, and rebuilds after a configuration change.

## Changing the scoring rules

A change to what counts must update, in the same change:

1. `Sources/CyclomaticComplexity/Analyzer.swift`
2. a unit test that pins the new behavior
3. `skills/checking-swift-complexity/references/scoring-rules.md`

If the change could alter the scores shown in `references/refactoring-examples.md`, measure those examples again and update the printed output.

## Output and file formats

`scripts/measure.sh` parses the text format: it relies on the `INFO … callables=` line and on operational failures starting with `Error:`. JSON output and baselines carry `schemaVersion`, `metric` and `swiftLanguageVersion`, and a baseline with different values is rejected.

## Evaluations

`evals/evals.json` holds realistic tasks for this skill, with the files each one starts from under `evals/files/` and verifiable expectations. After changing the skill, run each task in a fresh copy of its files with an agent that has the skill loaded, grade every expectation with evidence from the run, and compare against the previous results.
