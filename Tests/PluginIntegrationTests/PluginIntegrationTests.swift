import Foundation
import Testing

@Suite("Build-tool plugin integration", .serialized)
struct PluginIntegrationTests {
    @Test("complexity 2 builds without a complexity diagnostic")
    func cleanBuild() throws {
        let result = try build(source: "func f(_ x: Bool) { if x {} }")
        #expect(result.status == 0)
        #expect(!result.output.contains("cyclomatic complexity 2"))
    }

    @Test("complexity 3 builds with a warning")
    func warningBuild() throws {
        let result = try build(
            source: "func f(_ a: Bool, _ b: Bool) { if a, b {} }"
        )
        #expect(result.status == 0)
        #expect(result.output.contains("warning: cyclomatic complexity 3"))
    }

    @Test("complexity 7 fails the build with an error")
    func errorBuild() throws {
        let result = try build(
            source:
                "func f(_ a: Bool, _ b: Bool, _ c: Bool, _ d: Bool, _ e: Bool, _ f: Bool) { if a, b, c, d, e, f {} }"
        )
        #expect(result.status != 0)
        #expect(result.output.contains("error: cyclomatic complexity 7"))
    }

    @Test("invalid configuration fails cleanly")
    func invalidConfiguration() throws {
        let result = try build(
            source: "func f() {}",
            configuration: #"{"warningThreshold":7,"errorThreshold":7}"#
        )
        #expect(result.status != 0)
        #expect(result.output.contains("Invalid complexity configuration"))
    }

    @Test("excluded generated source is not gated")
    func generatedSourceExclusion() throws {
        let fixture = try Fixture(source: "func clean() {}", configuration: nil)
        let generated = fixture.root.appending(
            path: "Sources/App/Generated",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: generated,
            withIntermediateDirectories: true
        )
        try
            "func generated(_ a: Bool, _ b: Bool, _ c: Bool, _ d: Bool, _ e: Bool, _ f: Bool) { if a, b, c, d, e, f {} }"
            .write(
                to: generated.appending(path: "Generated.swift"),
                atomically: true,
                encoding: .utf8
            )
        let result = try fixture.build()
        #expect(result.status == 0)
        #expect(!result.output.contains("cyclomatic complexity 7"))
    }

    @Test("configuration changes invalidate and change build diagnostics")
    func configurationInvalidation() throws {
        let fixture = try Fixture(
            source: "func f(_ a: Bool, _ b: Bool) { if a, b {} }",
            configuration: #"{"warningThreshold":3,"errorThreshold":7}"#
        )
        var result = try fixture.build()
        #expect(result.output.contains("warning: cyclomatic complexity 3"))
        try fixture.writeConfiguration(
            #"{"warningThreshold":4,"errorThreshold":7}"#
        )
        result = try fixture.build()
        #expect(result.status == 0)
        #expect(!result.output.contains("warning: cyclomatic complexity 3"))
    }

    private func build(source: String, configuration: String? = nil) throws
        -> BuildResult
    {
        try Fixture(source: source, configuration: configuration).build()
    }
}

private struct BuildResult {
    let status: Int32
    let output: String
}

private final class Fixture {
    let root: URL
    private let packageRoot: URL

    init(source: String, configuration: String?) throws {
        packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        root = FileManager.default.temporaryDirectory.appending(
            path: "swift-complexity-plugin-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root.appending(
                path: "Sources/App",
                directoryHint: .isDirectory
            ),
            withIntermediateDirectories: true
        )
        let escapedRoot = packageRoot.path.replacingOccurrences(
            of: "\\",
            with: "\\\\"
        ).replacingOccurrences(of: "\"", with: "\\\"")
        let manifest = """
            // swift-tools-version: 6.4
            import PackageDescription
            let package = Package(
                name: "Fixture",
                platforms: [.macOS(.v27)],
                dependencies: [
                    .package(
                        name: "swift-cyclomatic-complexity-plugin",
                        path: "\(escapedRoot)"
                    )
                ],
                targets: [.executableTarget(name: "App", plugins: [.plugin(name: "CyclomaticComplexityBuildPlugin", package: "swift-cyclomatic-complexity-plugin")])]
            )
            """
        try manifest.write(
            to: root.appending(path: "Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        try (source + "\n@main struct App { static func main() {} }\n").write(
            to: root.appending(path: "Sources/App/main.swift"),
            atomically: true,
            encoding: .utf8
        )
        if let configuration { try writeConfiguration(configuration) }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func writeConfiguration(_ text: String) throws {
        try text.write(
            to: root.appending(path: ".swift-complexity.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    func build() throws -> BuildResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "build", "--package-path", root.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return BuildResult(
            status: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self)
        )
    }
}
