# Build plugins

The package ships two plugins. Both run `swift-complexity`.

## Build tool plugin: CyclomaticComplexityBuildPlugin

Adds a complexity check for every Swift file of a target to each build, and reports results as Xcode-style warnings and errors.

In a Swift package, add the plugin to the target:

```swift
.target(
    name: "MyTarget",
    plugins: [
        .plugin(name: "CyclomaticComplexityBuildPlugin", package: "swift-cyclomatic-complexity-plugin")
    ]
)
```

In an Xcode project, add the package dependency, then add `CyclomaticComplexityBuildPlugin` under the target's Build Phases, in Run Build Tool Plug-ins.

How it behaves:

- One check per Swift file. A check reruns only when that file or the target's `.swift-complexity.json` changes.
- A file whose callables are at most warnings counts as passing. Its warnings appear on the build that checks it and disappear on later builds until the file changes. A quiet incremental build is not evidence of clean code; run `scripts/measure.sh` instead.
- A file with an error-level callable or a parse error fails the build, and fails every build until it is fixed.
- If the target's files resolve to more than one `.swift-complexity.json`, or only some of them resolve to one, the plugin reports an error and adds no checks.

## Command plugin: swift package complexity

```sh
swift package complexity --format text
```

- Measures every Swift source file in every target of the package, test targets included. Paths added after `complexity` are measured in addition to those files, not instead of them.
- Other arguments pass through to `swift-complexity`.
- Its output appears on `swift package`'s stdout, xcode-format diagnostics included. A failing check adds `error: Cyclomatic complexity check failed with status 1.` on stderr.
- The plugin can't write into the package directory, so `--write-baseline` with a path inside the package fails with "You don't have permission to save the file". Write baselines with the CLI.
- It works only on Swift packages. For Xcode projects, use the build tool plugin or the CLI.
