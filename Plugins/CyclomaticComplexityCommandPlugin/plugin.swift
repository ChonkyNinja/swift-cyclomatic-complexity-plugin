import Foundation
import PackagePlugin

@main struct CyclomaticComplexityCommandPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String])
        async throws
    {
        let sourcePaths = context.package.targets.compactMap {
            $0 as? SourceModuleTarget
        }.flatMap { $0.sourceFiles(withSuffix: "swift") }.map { $0.url.path }
        guard !sourcePaths.isEmpty else {
            Diagnostics.warning(
                "No Swift source files found in package targets."
            )
            return
        }
        try run(
            tool: context.tool(named: "swift-complexity").url,
            sourcePaths: sourcePaths,
            arguments: arguments
        )
    }
    private func run(tool: URL, sourcePaths: [String], arguments: [String])
        throws
    {
        let process = Process()
        process.executableURL = tool
        process.arguments = sourcePaths + arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw ComplexityCommandFailure(status: process.terminationStatus)
        }
    }
}
private struct ComplexityCommandFailure: Error, CustomStringConvertible {
    let status: Int32
    var description: String {
        "Cyclomatic complexity check failed with status \(status)."
    }
}
