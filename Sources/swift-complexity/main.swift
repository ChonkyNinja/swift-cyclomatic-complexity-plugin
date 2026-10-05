import ArgumentParser
import CyclomaticComplexity
import Foundation

@main
struct SwiftComplexity: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-complexity",
        abstract: "Measure Swift 6.4 cyclomatic complexity using SwiftSyntax 604."
    )

    @Argument(help: "Swift source files or directories to analyze.")
    var paths: [String]

    @Option(name: .long, help: "Override the warning threshold (default/config: 3).")
    var warningThreshold: Int?

    @Option(name: .long, help: "Override the error threshold (default/config: 7).")
    var errorThreshold: Int?

    @Option(name: .long, help: "Configuration file. If omitted, exactly one .swift-complexity.json may be discovered across all analyzed inputs.")
    var config: String?

    @Option(name: .long, help: "Project root used to make baseline paths portable.")
    var root = FileManager.default.currentDirectoryPath

    @Option(name: .long, help: "Output format: text, json, or xcode.")
    var format = "text"

    @Flag(name: .long, help: "Show every decision contributing to each score.")
    var explain = false

    @Flag(name: .long, help: "Treat warning-range scores as build failures.")
    var warningsAsErrors = false

    @Option(name: .long, help: "Compare scores against a baseline JSON file.")
    var baseline: String?

    @Option(name: .long, help: "Write current scores as a baseline JSON file.")
    var writeBaseline: String?

    @Flag(name: .long, help: "Fail on any positive callable regression relative to the baseline.")
    var failOnRegression = false

    @Option(name: .long, help: "Write a stamp file after successful analysis; used by build plugins.")
    var stamp: String?

    mutating func validate() throws {
        guard !paths.isEmpty else { throw ValidationError("Provide at least one Swift source file or directory.") }
        guard ["text", "json", "xcode"].contains(format) else { throw ValidationError("--format must be text, json, or xcode.") }
        if let warningThreshold, warningThreshold < 1 { throw ValidationError("--warning-threshold must be at least 1.") }
        if let warningThreshold, let errorThreshold, errorThreshold <= warningThreshold {
            throw ValidationError("--error-threshold must be greater than --warning-threshold.")
        }
    }

    mutating func run() throws {
        let inputURLs = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
        let candidateFiles = try inputURLs.flatMap(swiftFiles(at:)).uniquedByPath().sorted { $0.path < $1.path }
        var configuration = try loadConfiguration(explicitPath: config, inputs: candidateFiles.isEmpty ? inputURLs : candidateFiles)
        if let warningThreshold { configuration.warningThreshold = warningThreshold }
        if let errorThreshold { configuration.errorThreshold = errorThreshold }
        if warningsAsErrors { configuration.warningsAsErrors = true }
        let policy: ComplexityPolicy
        do { policy = try configuration.validatedPolicy() }
        catch { throw ValidationError("Invalid complexity configuration: \(error)") }
        let files = candidateFiles.filter { configuration.includes(path: $0.path) }

        let analyzer = CyclomaticComplexityAnalyzer()
        let reports = try files.map { file in
            let source = try String(contentsOf: file, encoding: .utf8)
            return analyzer.analyze(source: source, path: file.path)
        }

        let baselineData = try baseline.map(loadBaseline(at:))
        let deltas = makeDeltas(reports: reports, baseline: baselineData)
        let output = ComplexityAnalysisOutput(reports: reports, deltas: deltas)

        switch format {
        case "json": try renderJSON(output)
        case "xcode": renderXcode(output, configuration: configuration)
        default: renderText(output, configuration: configuration, baseline: baselineData)
        }

        if let writeBaseline { try saveBaseline(from: reports, at: writeBaseline) }

        let hasParseFailure = reports.contains { !$0.isScorable }
        let hasThresholdFailure = reports.flatMap(\.results).contains { result in
            let severity = policy.severity(for: result.complexity)
            return severity == .error || (configuration.warningsAsErrors && severity == .warning)
        }
        let hasRegressionFailure = failOnRegression && deltas.contains { ($0.change ?? 0) > 0 }
        if hasParseFailure || hasThresholdFailure || hasRegressionFailure { throw ExitCode.failure }
        if let stamp { try writeStamp(at: stamp) }
    }

    private func loadConfiguration(explicitPath: String?, inputs: [URL]) throws -> ComplexityConfiguration {
        let decoder = JSONDecoder()
        if let explicitPath {
            return try decoder.decode(ComplexityConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: explicitPath)))
        }
        let resolutions = inputs.map { discoverConfigurationFile(for: $0)?.standardizedFileURL.path }
        let discovered = Set(resolutions.compactMap { $0 })
        guard discovered.count <= 1 else {
            throw ValidationError("Multiple .swift-complexity.json files apply to this invocation. Use one repository policy or pass --config explicitly. Found: \(discovered.sorted().joined(separator: ", "))")
        }
        if !discovered.isEmpty && resolutions.contains(where: { $0 == nil }) {
            throw ValidationError("Repository complexity policy is ambiguous: some analyzed files resolve .swift-complexity.json and others do not. Move to one shared repository policy or pass --config explicitly.")
        }
        guard let path = discovered.first else { return ComplexityConfiguration() }
        return try decoder.decode(ComplexityConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    private func discoverConfigurationFile(for input: URL) -> URL? {
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory)
        var directory = isDirectory.boolValue ? input : input.deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appending(path: ".swift-complexity.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    private func swiftFiles(at url: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ValidationError("Path does not exist: \(url.path)")
        }
        if !isDirectory.boolValue {
            guard url.pathExtension == "swift" else { throw ValidationError("Expected a .swift file: \(url.path)") }
            return [url]
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private func renderJSON(_ output: ComplexityAnalysisOutput) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(output), as: UTF8.self))
    }

    private func renderText(_ output: ComplexityAnalysisOutput, configuration: ComplexityConfiguration, baseline: ComplexityBaseline?) {
        let deltaByKey = Dictionary(uniqueKeysWithValues: output.deltas.map { ($0.key, $0) })
        for report in output.reports {
            for issue in report.parseIssues {
                print("ERROR \(report.path):\(issue.location.line):\(issue.location.column) parse-error: \(issue.message)")
            }
            for result in report.results.sorted(by: sourceOrder) {
                let severity = effectiveSeverity(for: result.complexity, configuration: configuration)
                let key = baselineKey(path: report.path, identity: result.identity)
                let delta = deltaByKey[key]
                let baselineSuffix = regressionSuffix(delta)
                print("\(severity.rawValue.uppercased()) \(report.path):\(result.location.line):\(result.location.column) \(result.name) [\(result.identity)] complexity=\(result.complexity)\(baselineSuffix) \(summary(result))")
                if explain { renderContributions(result) }
            }
            if !report.results.isEmpty {
                let prefix = baselineKey(path: report.path, identity: "")
                let baselineCallables = baseline?.entries.keys.filter { $0.hasPrefix(prefix) }.count
                let countSuffix = baselineCallables.map { " baselineCallables=\($0) callableDelta=\(report.results.count - $0)" } ?? ""
                print("INFO \(report.path) aggregate=\(report.aggregateComplexity) max=\(report.maximumComplexity) callables=\(report.results.count)\(countSuffix)")
            }
        }
        for delta in output.deltas where delta.state == .removed {
            print("INFO \(delta.path) [\(delta.identity)] removed from current source (baseline complexity=\(delta.previous ?? 0))")
        }
    }

    private func renderXcode(_ output: ComplexityAnalysisOutput, configuration: ComplexityConfiguration) {
        let deltaByKey = Dictionary(uniqueKeysWithValues: output.deltas.map { ($0.key, $0) })
        for report in output.reports {
            for issue in report.parseIssues {
                emitDiagnostic("\(report.path):\(issue.location.line):\(issue.location.column): error: cyclomatic complexity analysis skipped because source could not be parsed: \(issue.message)")
            }
            for result in report.results.sorted(by: sourceOrder) {
                let key = baselineKey(path: report.path, identity: result.identity)
                let delta = deltaByKey[key]
                let positiveRegression = (delta?.change ?? 0) > 0
                var severity = effectiveSeverity(for: result.complexity, configuration: configuration)
                if failOnRegression && positiveRegression { severity = .error }
                guard severity != .acceptable else { continue }

                let level = severity == .error ? "error" : "warning"
                emitDiagnostic("\(report.path):\(result.location.line):\(result.location.column): \(level): cyclomatic complexity \(result.complexity) for '\(result.name)'\(regressionSuffix(delta)) [\(summary(result))]; budget: warning >= \(configuration.warningThreshold), error >= \(configuration.errorThreshold)")
                if explain || (severity == .error && configuration.explainErrors) {
                    for item in result.contributions {
                        emitDiagnostic("\(report.path):\(item.location.line):\(item.location.column): note: +\(item.increment) \(item.kind.rawValue): \(item.excerpt)")
                    }
                }
            }
        }
    }

    private func regressionSuffix(_ delta: ComplexityDelta?) -> String {
        guard let delta, let previous = delta.previous, let change = delta.change, change != 0 else { return "" }
        return " (baseline \(previous), \(change > 0 ? "+" : "")\(change))"
    }

    private func effectiveSeverity(for complexity: Int, configuration: ComplexityConfiguration) -> ComplexitySeverity {
        let policy = try! configuration.validatedPolicy() // run() validates once before rendering.
        let severity = policy.severity(for: complexity)
        if configuration.warningsAsErrors && severity == .warning { return .error }
        return severity
    }

    private func summary(_ result: ComplexityResult) -> String {
        let grouped = Dictionary(grouping: result.contributions, by: \.kind)
        let pieces = DecisionKind.allCases.compactMap { kind -> String? in
            guard let items = grouped[kind], !items.isEmpty else { return nil }
            return "+\(items.reduce(0) { $0 + $1.increment }) \(kind.rawValue)"
        }
        return pieces.isEmpty ? "baseline only" : pieces.joined(separator: ", ")
    }

    private func renderContributions(_ result: ComplexityResult) {
        for item in result.contributions {
            print("  +\(item.increment) \(item.kind.rawValue) @ \(item.location.line):\(item.location.column)  \(item.excerpt)")
        }
    }

    private func baselineKey(path: String, identity: String) -> String {
        let absolute = URL(fileURLWithPath: path).standardizedFileURL.path
        let rootPath = URL(fileURLWithPath: root).standardizedFileURL.path
        let relative: String
        if absolute == rootPath { relative = "." }
        else if absolute.hasPrefix(rootPath + "/") { relative = String(absolute.dropFirst(rootPath.count + 1)) }
        else { relative = absolute }
        return "\(relative)::\(identity)"
    }

    private func loadBaseline(at path: String) throws -> ComplexityBaseline {
        let baseline = try JSONDecoder().decode(ComplexityBaseline.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        try baseline.validate()
        return baseline
    }

    private func saveBaseline(from reports: [FileComplexityReport], at path: String) throws {
        var entries: [String: Int] = [:]
        for report in reports { for result in report.results { entries[baselineKey(path: report.path, identity: result.identity)] = result.complexity } }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(ComplexityBaseline(entries: entries)).write(to: url, options: .atomic)
    }

    private func makeDeltas(reports: [FileComplexityReport], baseline: ComplexityBaseline?) -> [ComplexityDelta] {
        guard let baseline else { return [] }
        let observations = reports.flatMap { report in report.results.map { result in
            BaselineObservation(key: baselineKey(path: report.path, identity: result.identity), identity: result.identity, path: report.path, location: result.location, complexity: result.complexity)
        } }
        return baseline.deltas(comparedTo: observations)
    }

    private func sourceOrder(_ lhs: ComplexityResult, _ rhs: ComplexityResult) -> Bool {
        (lhs.location.line, lhs.location.column) < (rhs.location.line, rhs.location.column)
    }

    private func emitDiagnostic(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }

    private func writeStamp(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "ok\n".write(to: url, atomically: true, encoding: .utf8)
    }
}

private extension Array where Element == URL {
    func uniquedByPath() -> [URL] {
        var seen = Set<String>()
        return filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
