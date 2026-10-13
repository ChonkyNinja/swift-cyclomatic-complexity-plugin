---
name: checking-swift-complexity
description: Measures and reduces cyclomatic complexity in Swift 6.4 code with the SwiftSyntax-based swift-complexity analyzer from swift-cyclomatic-complexity-plugin. Use after writing or changing Swift control flow (if, guard, loops, switch, catch, ?:, &&, ||, ??), before calling Swift work done, when Xcode or SwiftPM reports a cyclomatic complexity warning or error, or when asked how complex a Swift function is.
---

# Checking Swift complexity

The analyzer scores every Swift callable (function, initializer, accessor, computed property, closure) by its decision points. Every callable starts at 1. By default a score of 3–6 is a warning, and 7 or more is an error that fails the build.

## Rules

- MUST report only scores the analyzer printed. Never estimate a score by reading code.
- MUST NOT edit `.swift-complexity.json`, add excluded paths, or pass threshold or `--config` options to make code pass. Thresholds change only when the user decides.
- MUST NOT restructure code to hide decisions from the analyzer. See "Fixing a warning or error".
- The analyzer needs Swift 6.4 (Xcode 27). Without it, say the check could not run and give no scores. Never lower the package's tools version or platform to make it build.

## Workflow

Copy this checklist and track it:

```
Complexity check:
- [ ] 1. Measure the files you will change; note the scores of the callables you will touch
- [ ] 2. Make the change
- [ ] 3. Build and run any tests
- [ ] 4. Measure the same files again
- [ ] 5. Fix every ERROR on a callable you changed, then repeat step 4
- [ ] 6. Fix each WARNING on a callable you changed, or state why its branching is essential
- [ ] 7. Report
```

Only move past step 5 when no callable you changed is at ERROR.

## Measuring

Run the bundled script with the Swift files or directories to check. The script path is relative to this skill's directory; the Swift paths are relative to your working directory.

```sh
scripts/measure.sh Sources/App/Pricing.swift
```

The first run builds the analyzer, including swift-syntax, so it is slow; later runs reuse the build. The script prints the report, then one result line:

| Last line | Exit | Meaning |
|---|---|---|
| `RESULT=pass` | 0 | No ERROR line. Warnings may remain. |
| `RESULT=fail` | 1 | At least one callable at the error threshold, a file that failed to parse, or a regression under `--fail-on-regression`. |
| `RESULT=nothing-measured` | 3 | No callables were measured: the paths are excluded, hold no Swift files, or have no callables. This is not a pass; say which applies. |
| `RESULT=setup-error` | 2 | No scores: missing toolchain, failed build, bad arguments, or an invalid `.swift-complexity.json`. Report the message. |

Read the `RESULT=` line. Piping the script's output through another command loses its exit status.

When this skill is installed outside the plugin repository, set `SWIFT_COMPLEXITY_PACKAGE` to a checkout of swift-cyclomatic-complexity-plugin.

The result covers every callable in the files passed, including code you did not touch. Judge a change by the before and after scores of the callables you changed.

## Reading the report

For this function:

```swift
func classify(_ value: Int?) -> String {
    guard let value, value >= 0 else { return "invalid" }
    return value.isMultiple(of: 2) ? "even" : "odd"
}
```

the script prints:

```
WARNING /path/Classify.swift:1:1 classify(_:) [classify(_:Int?)->String] complexity=4 +1 guard, +1 ternary, +1 condition-chain
  +1 guard @ 2:5  guard
  +1 condition-chain @ 2:22  value
  +1 ternary @ 3:36  ?
INFO /path/Classify.swift aggregate=4 max=4 callables=1
RESULT=pass
```

- Each callable line gives severity, location, name, `[identity]`, score, and the points grouped by kind. A callable with no decisions shows `baseline only`.
- Each indented line is one decision and its `line:column`.
- One `INFO` line per file with callables. `aggregate` is the sum of the file's scores. A callable you changed that has no line was not measured.

## Fixing a warning or error

Remove decisions; don't move them.

- Delete checks that can't change the result, such as a condition an earlier branch already ruled out.
- Replace combinations of flags and optionals with an enum whose cases are the real states.
- Replace a `switch` that maps cases to constants with data stored on the type.
- Merge `switch` cases that share a body: `case .a, .b:`.
- Extract a type or SwiftUI view only when it names a real concept, such as one view per screen state.

Reject these even when the score drops:

- Swapping `if`, `guard` and `?:`. Each is one decision.
- Moving a check where the analyzer doesn't look: default argument values, stored-property initializers, or top-level code.
- Splitting a callable into helpers or closures that name nothing. When `callables=` rises and `aggregate` doesn't fall, check that every new callable names something real.

Keep branching that is essential, such as a `guard` that validates input or a `switch` over the cases of a domain enum, and say why it stays.

## Reporting

For each callable you changed that ends at WARNING or ERROR, give its name, `file:line`, the before and after scores, the severity, and the kinds that contribute most. If the check could not run, say why and give no scores.

## Reference files

| Read | When |
|---|---|
| [references/refactoring-examples.md](references/refactoring-examples.md) | Before refactoring to lower a score: three measured before-and-after examples, one of them a rejected trick. |
| [references/scoring-rules.md](references/scoring-rules.md) | You need exactly what adds a point, what counts as a callable, or how `#if` is scored. |
| [references/analyzer-cli.md](references/analyzer-cli.md) | You run `swift-complexity` directly: output formats, exit statuses, configuration, baselines. |
| [references/build-plugins.md](references/build-plugins.md) | You add the analyzer to a package or Xcode target, or read complexity diagnostics in a build log. |
| [references/maintaining-the-analyzer.md](references/maintaining-the-analyzer.md) | Only when changing the analyzer, its plugins, or this skill in the plugin repository. Not needed to measure or fix code. |
