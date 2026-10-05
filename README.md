# Swift Cyclomatic Complexity Plugin

A Swift-native analyzer and build gate for keeping cyclomatic complexity low
in Swift 6.4, with a bundled agent skill.

## Included

- Swift 6.4 / macOS 27-only SwiftPM package; no compatibility scaffolding
- SwiftSyntax 604.x source-accurate AST analysis
- frozen **Swift McCabe** scoring contract
- strict default gate: **1–2 clean, 3–6 warning, 7+ error**
- Xcode + SwiftPM incremental build-tool plugin
- SwiftPM command plugin
- source-located Xcode warnings/errors and contributor notes
- text, versioned JSON, and Xcode diagnostic output
- signature-aware callable identities, hierarchical/structurally named closures, and `#if` ancestry
- functions, initializers/deinitializers, closures, accessors, computed properties, and subscripts
- comma-separated Swift condition-chain and executable `where` predicate scoring
- validated shared `.swift-complexity.json` repository configuration
- versioned portable baselines with added/changed/removed/unchanged deltas
- parse-error rejection instead of scoring recovery trees
- informational aggregate/max/callable-count anti-gaming context
- Swift Testing unit/golden coverage plus end-to-end build-tool-plugin integration tests

The authoritative agent behavior is
`.agents/skills/swift-cyclomatic-complexity/SKILL.md`; the Swift package is
at the repository root.

## Default policy

- complexity 1–2: clean, silent
- complexity 3–6: warning
- complexity 7+: error and failed quality gate/build

Do not raise thresholds merely to make generated code pass.

## Validate with the target toolchain

From the repository root under Swift 6.4 / Xcode 27:

```sh
swift test
swift run swift-complexity Sources --format xcode
```

`PluginIntegrationTests` invokes real temporary SwiftPM builds using `CyclomaticComplexityBuildPlugin`, covering clean/warning/error builds, invalid configuration, configuration invalidation, and generated-source exclusion.

## Baseline compatibility

Baselines and JSON output are explicit versioned protocols. Current values are schema 1, metric `swift-mccabe`, Swift language `6.4`. Incompatible baselines are rejected. Regenerate baselines from pre-versioned revisions.
