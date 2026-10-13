# Scoring rules

How `swift-complexity` turns Swift source into scores. The unit tests in `Tests/CyclomaticComplexityTests` enforce these rules.

## What gets a score

Each of these is a separate callable. Each starts at 1:

- `func` declarations with a body, operator functions included
- `init` and `deinit`
- accessors with a body: `get`, `set`, `willSet`, `didSet`, `_read`, `_modify`
- shorthand computed properties, such as `var body: some View { … }`, scored as `body.get`
- shorthand subscript getters, scored as `subscript(…).get`
- every closure, wherever it appears, including SwiftUI view-builder closures and closures in property initializers

A callable nested inside another one is scored separately and adds nothing to the outer callable.

Code outside any callable gets no score: top-level statements in `main.swift` or scripts, stored-property initializers, and default argument values. Moving a check into one of these places hides it from the analyzer; it does not remove it.

## What adds a point

| Construct | Points |
|---|---|
| `if`, including each `else if` | +1 each |
| `guard` | +1 |
| `for`, `for await`, `for try await` | +1 |
| `while` | +1 |
| `repeat { } while` | +1 |
| each `catch` clause | +1 |
| `?:` | +1 |
| `&&`, `\|\|`, `??` | +1 per operator |
| each extra comma-separated condition in `if`, `guard`, or `while` | +1 |
| `where` on a `for` loop or on a `case` item | +1 |
| `switch` with N case bodies | N − 1 |

`if a && b || c { }` adds 3 to its callable: +1 `if`, +1 `&&`, +1 `||`.

`if let x, x > 0 { }` adds 2: +1 `if`, +1 for the second condition.

## Switches

Count case bodies, not patterns. `case .a, .b:` is one body. `default` is a body. A switch statement and a switch expression follow the same rule. Cases inside `#if`, `#elseif` or `#else` within the switch count like any other case.

## What adds nothing

`else`, `defer`, `do`, `return`, `throw`, `break`, `continue`, `fallthrough`, optional chaining, `try?`, `try!`, `await`, `async`, `throws`, typed `throws`, and plain calls.

## Conditional compilation

`#if` conditions add nothing, even when they contain `&&` or `||`. The code in every branch is scored, so a callable with one `if` under `#if DEBUG` and another under `#else` scores 3, even though a build only compiles one of them.

## Parse errors

A file with a parse error gets no scores. The report lists each parse error, and the run fails until the file parses.

## Severity

| Score | Default severity | Effect |
|---|---|---|
| 1–2 | acceptable | silent in builds |
| 3–6 | warning | build continues |
| 7 or more | error | build fails |

Both thresholds are inclusive. `.swift-complexity.json` can change them with `warningThreshold` and `errorThreshold`, and `warningsAsErrors: true` turns warnings into errors.
