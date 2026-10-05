# Swift 6.4 Swift McCabe scoring contract

This skill uses a deliberately frozen source-level McCabe/basis-path policy over SwiftSyntax 604.x. Keeping the policy explicit prevents scores from silently changing when another lint tool or language heuristic changes.

## Callable boundaries

Each callable starts at 1 and is measured independently:

- functions and operator functions
- initializers and deinitializers
- closures
- explicit `get`, `set`, `_read`, `_modify`, `willSet`, `didSet`, and other accessor declarations with bodies
- shorthand computed-property getters
- shorthand subscript getters

Nested functions, closures, properties, and accessors do not contribute their decisions to an enclosing callable.

## Decisions

| Swift construct | Increment | Policy |
|---|---:|---|
| `if` / `else if` | +1 each | each `if` is a binary decision |
| `guard` | +1 | success vs early exit |
| `for`, `for await`, `for try await` | +1 | zero iterations vs loop path |
| `while` | +1 | condition-controlled loop |
| `repeat ... while` | +1 | repeat vs exit at loop condition |
| each `catch` | +1 | exception-handling alternative |
| `a ? b : c` | +1 | expression-level binary decision |
| `&&`, `||` | +1 each | short-circuit creates another path |
| `??` | +1 | RHS is conditionally evaluated |
| `switch` | alternatives - 1 | N-way branch adds N-1 independent paths |
| extra comma-separated `if` / `guard` / `while` condition | +1 each | Swift condition lists short-circuit left-to-right |
| executable `where` predicate on `for` or `case` | +1 | predicate gates entry to the body/alternative |

An `if` condition containing `a && b || c` contributes 3: +1 for the `if`, +1 for `&&`, +1 for `||`.

## Switches and patterns

Count executable alternatives/bodies, not comma-separated patterns. `case .a, .b`, `case .c`, `default` has three alternatives and contributes 2.

A `case ... where ...` adds +1 for the executable predicate in addition to the case alternative. A `for ... where ...` also adds +1. If a `where` expression itself contains `&&`, `||`, or `??`, those short-circuit operators are counted as additional paths.

Switch statements and switch expressions use the same rule.

## Conditions

The first condition element belongs to the containing `if`, `guard`, or `while`. Every additional comma-separated condition element adds +1 because Swift evaluates the condition list left-to-right and short-circuits on failure. Optional binding/pattern matching does not add another point by itself; its position as an additional condition element does. Explicit `&&`, `||`, and `??` operators are counted independently.

## Declarations that do not add decisions

`async`, `await`, `throws`, typed `throws`, generic constraints, and isolation annotations do not create cyclomatic points by themselves.

## Exclusions

`else` is the second edge of an already-counted `if`. `return`, `throw`, `break`, and `continue` redirect flow but do not create decisions. `defer`, `do`, optional chaining, `try?`, `try!`, and ordinary calls are deliberately excluded.

## Macros and generated code

The analyzer measures the source syntax presented to SwiftSyntax; it does not pretend to measure compiler-expanded macro implementation paths that are absent from the source file. Generated source directories are excluded by default and can be configured explicitly.

## Severity

- 1...2: clean
- 3...6: warning
- 7+: error

Threshold equality is inclusive. Repository configuration can be stricter. Raising thresholds to accommodate a violation requires an explicit design reason.

## Conditional compilation

The source analyzer intentionally measures **all source branches** under `#if` / `#elseif` / `#else`. It does not pretend to know the compiler's complete active-condition environment from source text alone. Conditional-compilation ancestry is part of machine identity so mutually exclusive declarations cannot overwrite one another in a baseline.

## Parse validity

A file with parser error diagnostics is **unscorable**. The analyzer reports the parse errors and emits no callable scores for that file. Never use SwiftParser recovery output as a confident complexity measurement.

## Identity stability boundary

Machine identities are source-syntax identities, not compiler ABI/mangled symbols. They normalize callable structure enough to prevent known overload/static/accessor/closure/conditional-compilation collisions, but semantically equivalent type spellings such as `Int` versus `Swift.Int` may intentionally produce different baseline keys. Do not add compiler-semantic type resolution merely to normalize those spellings; regenerate/migrate a baseline when deliberately changing signature spelling.
