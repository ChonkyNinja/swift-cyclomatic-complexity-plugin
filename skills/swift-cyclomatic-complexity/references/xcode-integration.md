# Xcode and build integration

The analyzer participates in normal builds, not only ad-hoc lint runs.

## Default severity contract

- score 1...2: clean; no Xcode issue
- score 3...6: warning; build continues
- score 7+: error; build fails

Thresholds are inclusive.

## Xcode diagnostics

`--format xcode` emits source-located compiler-style diagnostics at the callable declaration. Every warning/error contains a compact contribution breakdown, for example:

```text
/path/File.swift:42:5: warning: cyclomatic complexity 4 for 'Loader.load' [+1 guard, +1 if, +1 &&]; budget: warning >= 3, error >= 7
```

Error-level findings automatically emit source-located `note:` diagnostics for every contributing decision when `explainErrors` is enabled (the default). `--explain` does the same for warnings.

## Shared configuration

Put `.swift-complexity.json` at the repository/project root. The executable and build plugin discover policy upward from inputs, but require a single resolved configuration per invocation/target. If nested configuration files would produce multiple policies, analysis is rejected instead of silently applying different thresholds to different files.

```json
{
  "warningThreshold": 3,
  "errorThreshold": 7,
  "excludedPathComponents": [".build", "DerivedData", "Generated"],
  "warningsAsErrors": false,
  "explainErrors": true
}
```

## Build-tool plugin

`CyclomaticComplexityBuildPlugin` supports Swift package targets and Xcode project targets through `BuildToolPlugin` and `XcodeBuildToolPlugin`.

It creates an incremental build command per Swift source. A successful analysis writes a stamp in the plugin work directory; changing that source invalidates the command. The plugin does not hard-code policy values. It resolves one target-wide `.swift-complexity.json`, passes it explicitly to every per-file command, and declares it as a build input so policy edits invalidate the checks. Multiple applicable configuration files for one target are diagnosed as an error.

For a Swift package target:

```swift
.target(
    name: "MyTarget",
    plugins: [
        .plugin(name: "CyclomaticComplexityBuildPlugin", package: "swift-cyclomatic-complexity-plugin")
    ]
)
```

For an Xcode project target, add the package dependency and enable `CyclomaticComplexityBuildPlugin` in the target's Build Tool Plug-ins section.

## Command plugin and CI

Explicit package-wide check:

```sh
swift package complexity --format xcode
```

Direct CI invocation:

```sh
swift run swift-complexity Sources Tests --format xcode
swift run swift-complexity Sources Tests --format xcode --warnings-as-errors
```

Error-level findings exit nonzero. With `warningsAsErrors`/`--warnings-as-errors`, warning-level findings also fail.

## Baseline regression checks

Create a portable baseline from the repository root:

```sh
swift run swift-complexity Sources --write-baseline complexity-baseline.json --root .
```

Then check for regressions:

```sh
swift run swift-complexity Sources --baseline complexity-baseline.json --fail-on-regression --root . --format xcode
```

A baseline does not replace the 3/7 absolute gate. Baseline information is merged into the callable’s normal diagnostic. A 2→4 change is one warning with the baseline delta; a 1→2 change stays clean unless `--fail-on-regression` is explicitly enabled.

## Parse failures

Parser-error source is not assigned a complexity score. The Xcode renderer emits an `error:` at each parser diagnostic and the complexity command exits nonzero. This avoids treating SwiftParser recovery trees as trustworthy quality-gate input.

## Conditional compilation

The current source analyzer checks all `#if` branches rather than claiming active-build-only semantics. Machine identities include `#if`/`#elseif`/`#else` ancestry so mutually exclusive declarations remain distinct in baselines.


## Integration acceptance suite

`PluginIntegrationTests` builds temporary Swift 6.4 fixture packages through the real `CyclomaticComplexityBuildPlugin` and verifies the end-to-end contract: score 2 is silent/successful, score 3 is a warning/successful, score 7 is an error/failure, invalid configuration fails cleanly, configuration edits invalidate/re-run diagnostics, and generated/excluded source is not gated.

The `XcodeBuildToolPlugin` conformance is compiled as part of the package on macOS. Release validation must additionally run the package and plugin suite under Xcode 27 / Swift 6.4; do not claim Xcode 27 execution from an environment that does not contain Xcode 27.

## Versioned machine output

Baseline and JSON report formats are versioned. A baseline declares `schemaVersion`, `metric`, and `swiftLanguageVersion`; incompatible values are rejected. JSON analysis output carries the same envelope so CI/agents can fail explicitly on unsupported future schemas instead of silently misreading fields.
