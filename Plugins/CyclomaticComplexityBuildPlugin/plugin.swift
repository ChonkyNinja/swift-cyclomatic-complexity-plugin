import Foundation
import PackagePlugin

@main
struct CyclomaticComplexityBuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target)
        async throws -> [Command]
    {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }
        return try makeCommands(
            tool: context.tool(named: "swift-complexity").url,
            inputFiles: sourceTarget.sourceFiles(withSuffix: "swift").map(
                \.url
            ),
            workDirectory: context.pluginWorkDirectoryURL,
            targetName: target.name
        )
    }

    private func makeCommands(
        tool: URL,
        inputFiles: [URL],
        workDirectory: URL,
        targetName: String
    ) throws -> [Command] {
        let resolutions = inputFiles.map {
            configurationFile(for: $0)?.standardizedFileURL.path
        }
        let configurations = Set(resolutions.compactMap { $0 })
        guard configurations.count <= 1 else {
            Diagnostics.error(
                "Multiple .swift-complexity.json files apply to target \(targetName). Use one repository policy. Found: \(configurations.sorted().joined(separator: ", "))"
            )
            return []
        }
        if !configurations.isEmpty && resolutions.contains(where: { $0 == nil })
        {
            Diagnostics.error(
                "Complexity policy is ambiguous for target \(targetName): some Swift files resolve .swift-complexity.json and others do not."
            )
            return []
        }
        let configuration = configurations.first.map {
            URL(fileURLWithPath: $0)
        }
        return inputFiles.map { input in
            let stamp =
                workDirectory
                .appending(
                    path: sanitize(targetName),
                    directoryHint: .isDirectory
                )
                .appending(path: sanitize(input.path) + ".complexity-stamp")
            var arguments = [
                input.path, "--format", "xcode", "--stamp", stamp.path,
            ]
            if let configuration {
                arguments += ["--config", configuration.path]
            }
            return .buildCommand(
                displayName:
                    "Cyclomatic complexity: \(input.lastPathComponent)",
                executable: tool,
                arguments: arguments,
                inputFiles: [input] + (configuration.map { [$0] } ?? []),
                outputFiles: [stamp]
            )
        }
    }

    private func configurationFile(for input: URL) -> URL? {
        var directory = input.deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appending(path: ".swift-complexity.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    private func sanitize(_ value: String) -> String {
        value.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : "_"
        }.joined()
    }
}

#if canImport(XcodeProjectPlugin)
    import XcodeProjectPlugin

    extension CyclomaticComplexityBuildPlugin: XcodeBuildToolPlugin {
        func createBuildCommands(
            context: XcodePluginContext,
            target: XcodeTarget
        ) throws -> [Command] {
            try makeCommands(
                tool: context.tool(named: "swift-complexity").url,
                inputFiles: target.inputFiles.filter {
                    $0.type == .source && $0.url.pathExtension == "swift"
                }.map(\.url),
                workDirectory: context.pluginWorkDirectoryURL,
                targetName: target.displayName
            )
        }
    }
#endif
