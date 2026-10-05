# Release validation — Swift 6.4 / Xcode 27

A release is complete only when these checks pass on the target toolchain. Do not lower `swift-tools-version`, macOS deployment target, or dependency versions to accommodate an older validation host.

1. Confirm `swift --version` reports Swift 6.4.x and Xcode 27 is selected.
2. From the repository root, run `swift test`. This includes unit/golden tests and Swift-native end-to-end `CyclomaticComplexityBuildPlugin` builds.
3. Run `swift run swift-complexity Tests/CyclomaticComplexityTests/Fixtures/SyncCoordinator.swift --format json` and verify schema 1 / `swift-mccabe` / Swift 6.4 output.
4. Open/build a representative Xcode 27 project target with `CyclomaticComplexityBuildPlugin` enabled and verify source-located warning at score 3 and build-breaking error at score 7.
5. Change the repository `.swift-complexity.json` thresholds and rebuild; verify the plugin command is invalidated and diagnostics reflect the new policy.
6. Restore the repository default 3/7 policy before release.
