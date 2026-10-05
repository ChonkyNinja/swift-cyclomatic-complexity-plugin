---
name: swift-cyclomatic-complexity
description: Measure, explain, prevent, and reduce cyclomatic complexity in Swift 6.4 code. Use proactively while writing, reviewing, building, or refactoring Swift; when control flow changes; when Xcode/build diagnostics report complexity; or when the user asks about cyclomatic complexity. Uses the bundled Swift 6.4 + SwiftSyntax 604 analyzer and Xcode/SwiftPM build integration; never estimates complexity by eyeballing or regex.
---

# Swift 6.4 Cyclomatic Complexity

Treat cyclomatic complexity as a design constraint during implementation, not a cleanup metric after the code is finished.

## Non-negotiable baseline

- Target Swift 6.4 and macOS 27 only.
- Use current official Swift 6.4 tooling and SwiftSyntax 604.x.
- Do not add backward-compatibility scaffolding.
- The analyzer, plugins, configuration handling, and helpers are Swift 6.4.
- Measure from SwiftSyntax's source-accurate syntax tree; never use regex or line-count approximations.
- Report **Swift McCabe cyclomatic complexity**, not cognitive complexity.
- Never claim a score that the analyzer did not produce.

## Default quality gate

- **1...2 — clean:** no diagnostic.
- **3...6 — warning:** emit an Xcode/build warning and reconsider structure before adding another decision.
- **7+ — error:** emit an Xcode/build error and fail the quality gate/build.

Thresholds are inclusive. Do not raise thresholds merely to silence generated-code diagnostics. Configuration exists for deliberate repository policy, not metric gaming.

## Required coding loop

For any material control-flow change:

1. **Measure** the affected callable before changing it when a before-score is available.
2. **Identify** the dominant contributors using the summary or `--explain`.
3. **Understand responsibility** before extracting code; find a real domain/responsibility boundary.
4. **Refactor/write** using the simplest structure that expresses the behavior.
5. **Compile and test** the behavioral change.
6. **Remeasure** the changed callables.
7. **Reject** a refactor that lowers the score by damaging cohesion, duplicating behavior, hiding state, or creating meaningless helpers.
8. Report the before/after score when complexity drove the change.

A function split into several arbitrary complexity-2 helpers is not automatically an improvement. Optimize design, not only the number.

## Metric

Every callable starts at **1**. Add one for each `if`, `guard`, `for`/`for await`, `while`, `repeat ... while`, `catch`, ternary `?:`, short-circuit `&&`, short-circuit `||`, nil-coalescing `??`, each additional comma-separated `if`/`guard`/`while` condition element, each executable `where` predicate on `for` or `case`, and each `switch` alternative beyond the first.

For `switch`, comma-separated patterns sharing one body are one alternative. `default` is an alternative. A switch with N alternatives contributes `max(0, N - 1)`. A case `where` predicate adds +1 because it independently gates the alternative; `for ... where` follows the same rule.

Do not add points for `else`, `defer`, `do`, `return`, `throw`, `break`, `continue`, optional chaining, `try?`, `try!`, ordinary calls, `async`, `await`, or `throws`/typed `throws` declarations.

Functions, initializers, deinitializers, closures, explicit accessors, shorthand computed-property getters, and shorthand subscript getters are independent scopes. Nested callable decisions must never inflate their enclosing callable.

See `references/scoring.md` for the frozen scoring contract.

## Stable identities and diagnostics

Keep human-facing names compact, but use signature-aware machine identities for baselines, such as `Worker.load(_:Int)` and `Worker.load(_:String)`. Nested closures are hierarchical. Closures bound to a structural name use it (`Worker.load(_:Int).closure[completion]`); otherwise ordinal fallback is used (`closure#1`). Conditional-compilation ancestry is included in machine identities to prevent collisions across `#if` branches. Diagnostics must point to the callable declaration; contribution notes point to the actual decision syntax.

Xcode error diagnostics automatically include contributor notes by default. Warning diagnostics include a compact contributor summary and can emit full notes with `--explain`.

## Repository configuration

Prefer a repository-root `.swift-complexity.json`. The CLI and build plugin discover configuration upward from analyzed Swift files, but one invocation/target must resolve to exactly one configuration file. Ambiguous nested policies are rejected; use one repository policy or pass `--config` explicitly.

Default configuration:

```json
{
  "warningThreshold": 3,
  "errorThreshold": 7,
  "excludedPathComponents": [".build", "DerivedData", "Generated"],
  "warningsAsErrors": false,
  "explainErrors": true
}
```

CLI threshold options may override configuration for an intentional one-off check. Do not use overrides to bypass repository policy during normal coding.

## Tools

From the repository root:

```sh
swift run swift-complexity Sources --format xcode
swift run swift-complexity Sources --explain
swift run swift-complexity Sources --format json
swift run swift-complexity Sources --write-baseline complexity-baseline.json --root .
swift run swift-complexity Sources --baseline complexity-baseline.json --fail-on-regression --root .
swift package complexity --format xcode
swift test
```

Use `CyclomaticComplexityBuildPlugin` for automatic incremental Xcode/SwiftPM build feedback. Error-level scores fail the build. `--warnings-as-errors` is available for stricter CI.

## Baseline/diff policy

Absolute thresholds remain authoritative. Baselines are supplementary: use them to expose a change such as `2 -> 4` even when the new score is only warning-level. `--fail-on-regression` is an explicitly strict mode and fails on any positive regression. Without it, regressions are folded into the normal threshold diagnostic: clean 1–2 code remains silent, warning/error code reports one combined issue rather than a duplicate regression warning.

Commit baselines only when the repository intentionally wants debt tracking. Generate them with a stable `--root` so paths remain portable across machines.

## Versioned external contracts

Treat baseline and JSON output as APIs. Both carry `schemaVersion`, `metric: "swift-mccabe"`, and `swiftLanguageVersion: "6.4"`. Reject unsupported baseline schemas/metrics/language versions rather than comparing incompatible data. Added, changed, removed, and unchanged callable states are represented explicitly in baseline deltas; removed callables are informational, not complexity regressions.

## Aggregate metrics

File aggregate and maximum complexity are **informational context only**. Do not fail a build merely because a large file contains many simple callables. Use aggregates to spot concentration and decomposition opportunities; use per-callable complexity for the quality gate.

## Refactoring guidance

Prefer removing redundant decisions and impossible states, representing domain variants with types, consolidating duplicated branch bodies, extracting coherent responsibilities, and using table-driven/polymorphic dispatch when behavior genuinely varies by data/type. `guard` can flatten nesting but remains a decision and still counts.

Never replace readable branching with obscure cleverness solely to lower the score.

## Output expectations

When this skill affects a code change, report changed warning/error callables with identity, score, severity, source location, and dominant contributors. When refactoring, include the post-refactor score, verify compile/tests before declaring success, and compare callable count when a baseline is available. A large callable-count increase is a prompt to inspect whether complexity was merely scattered into meaningless helpers.

See `references/xcode-integration.md` for build/Xcode behavior.

## Parse validity and conditional compilation

Do not score malformed Swift. Parser errors make the file unscorable and must fail the check until the source parses cleanly.

This version analyzes all `#if`/`#elseif`/`#else` source branches. Do not describe that as active-build-only analysis. Machine identities include conditional-compilation ancestry so mutually exclusive declarations remain distinct.

## Regression anti-gaming check

When baseline data is available, compare both callable scores and callable counts. A complexity reduction accompanied by a large callable-count increase requires a cohesion review before calling the refactor successful. Prefer meaningful responsibility boundaries over scattering branches across tiny helpers.

## Release validation

Before declaring a release of the analyzer/build integration complete, follow `references/release-validation.md` on Swift 6.4 / Xcode 27. Never weaken the manifest or target merely to make an older worker execute the suite.
