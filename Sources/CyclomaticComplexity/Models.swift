import Foundation

public let swiftMcCabeMetric = "swift-mccabe"
public let swiftMcCabeSchemaVersion = 1
public let swiftMcCabeLanguageVersion = "6.4"

public struct SourceLocation: Codable, Hashable, Sendable {
    public let line: Int
    public let column: Int
    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}
public struct ParseIssue: Codable, Hashable, Sendable {
    public let message: String
    public let location: SourceLocation
    public init(message: String, location: SourceLocation) {
        self.message = message
        self.location = location
    }
}

public enum DecisionKind: String, Codable, Sendable, CaseIterable {
    case ifStatement = "if"
    case guardStatement = "guard"
    case forLoop = "for"
    case whileLoop = "while"
    case repeatWhileLoop = "repeat-while"
    case catchClause = "catch"
    case ternary = "ternary"
    case logicalAnd = "&&"
    case logicalOr = "||"
    case nilCoalescing = "??"
    case switchAlternative = "switch-alternative"
    case conditionChain = "condition-chain"
    case wherePredicate = "where"
}

public struct ComplexityContribution: Codable, Hashable, Sendable {
    public let kind: DecisionKind
    public let increment: Int
    public let location: SourceLocation
    public let excerpt: String
}
public struct ComplexityResult: Codable, Hashable, Sendable {
    public let identity: String
    public let name: String
    public let kind: String
    public let location: SourceLocation
    public let complexity: Int
    public let contributions: [ComplexityContribution]
}
public struct FileComplexityReport: Codable, Sendable {
    public let path: String
    public let results: [ComplexityResult]
    public let parseIssues: [ParseIssue]
    public init(
        path: String,
        results: [ComplexityResult],
        parseIssues: [ParseIssue] = []
    ) {
        self.path = path
        self.results = results
        self.parseIssues = parseIssues
    }
    public var isScorable: Bool { parseIssues.isEmpty }
    public var aggregateComplexity: Int {
        results.reduce(0) { $0 + $1.complexity }
    }
    public var maximumComplexity: Int { results.map(\.complexity).max() ?? 0 }
}
public enum ComplexitySeverity: String, Codable, Sendable {
    case acceptable, warning, error
}

public enum ComplexityConfigurationError: Error, CustomStringConvertible,
    Equatable, Sendable
{
    case invalidWarningThreshold(Int)
    case invalidThresholdOrder(warning: Int, error: Int)
    case emptyExcludedPathComponent
    public var description: String {
        switch self {
        case .invalidWarningThreshold(let v):
            return "warningThreshold must be >= 1; got \(v)."
        case .invalidThresholdOrder(let w, let e):
            return
                "errorThreshold must be greater than warningThreshold; got warning=\(w), error=\(e)."
        case .emptyExcludedPathComponent:
            return "excludedPathComponents must not contain an empty component."
        }
    }
}

public struct ComplexityPolicy: Codable, Hashable, Sendable {
    public let warningThreshold: Int
    public let errorThreshold: Int
    public init(warningThreshold: Int = 3, errorThreshold: Int = 7) throws {
        guard warningThreshold >= 1 else {
            throw ComplexityConfigurationError.invalidWarningThreshold(
                warningThreshold
            )
        }
        guard errorThreshold > warningThreshold else {
            throw ComplexityConfigurationError.invalidThresholdOrder(
                warning: warningThreshold,
                error: errorThreshold
            )
        }
        self.warningThreshold = warningThreshold
        self.errorThreshold = errorThreshold
    }
    public func severity(for complexity: Int) -> ComplexitySeverity {
        complexity >= errorThreshold
            ? .error : (complexity >= warningThreshold ? .warning : .acceptable)
    }
}

public struct ComplexityConfiguration: Codable, Hashable, Sendable {
    public var warningThreshold: Int
    public var errorThreshold: Int
    public var excludedPathComponents: [String]
    public var warningsAsErrors: Bool
    public var explainErrors: Bool
    public init(
        warningThreshold: Int = 3,
        errorThreshold: Int = 7,
        excludedPathComponents: [String] = [
            ".build", "DerivedData", "Generated",
        ],
        warningsAsErrors: Bool = false,
        explainErrors: Bool = true
    ) {
        self.warningThreshold = warningThreshold
        self.errorThreshold = errorThreshold
        self.excludedPathComponents = excludedPathComponents
        self.warningsAsErrors = warningsAsErrors
        self.explainErrors = explainErrors
    }
    private enum CodingKeys: String, CodingKey {
        case warningThreshold, errorThreshold, excludedPathComponents,
            warningsAsErrors, explainErrors
    }
    public init(from decoder: Decoder) throws {
        let d = Self()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        warningThreshold =
            try c.decodeIfPresent(Int.self, forKey: .warningThreshold)
            ?? d.warningThreshold
        errorThreshold =
            try c.decodeIfPresent(Int.self, forKey: .errorThreshold)
            ?? d.errorThreshold
        excludedPathComponents =
            try c.decodeIfPresent(
                [String].self,
                forKey: .excludedPathComponents
            ) ?? d.excludedPathComponents
        warningsAsErrors =
            try c.decodeIfPresent(Bool.self, forKey: .warningsAsErrors)
            ?? d.warningsAsErrors
        explainErrors =
            try c.decodeIfPresent(Bool.self, forKey: .explainErrors)
            ?? d.explainErrors
    }
    public func validatedPolicy() throws -> ComplexityPolicy {
        if excludedPathComponents.contains(where: { $0.isEmpty }) {
            throw ComplexityConfigurationError.emptyExcludedPathComponent
        }
        return try ComplexityPolicy(
            warningThreshold: warningThreshold,
            errorThreshold: errorThreshold
        )
    }
    public func includes(path: String) -> Bool {
        !excludedPathComponents.contains {
            path.split(separator: "/").contains(Substring($0))
        }
    }
}

public struct ComplexityBaseline: Codable, Sendable {
    public var schemaVersion: Int
    public var metric: String
    public var swiftLanguageVersion: String
    public var entries: [String: Int]
    public init(
        schemaVersion: Int = swiftMcCabeSchemaVersion,
        metric: String = swiftMcCabeMetric,
        swiftLanguageVersion: String = swiftMcCabeLanguageVersion,
        entries: [String: Int] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.metric = metric
        self.swiftLanguageVersion = swiftLanguageVersion
        self.entries = entries
    }
    public func validate() throws {
        guard schemaVersion == swiftMcCabeSchemaVersion else {
            throw BaselineError.unsupportedSchema(schemaVersion)
        }
        guard metric == swiftMcCabeMetric else {
            throw BaselineError.unsupportedMetric(metric)
        }
        guard swiftLanguageVersion == swiftMcCabeLanguageVersion else {
            throw BaselineError.unsupportedSwiftLanguage(swiftLanguageVersion)
        }
    }
}
public enum BaselineError: Error, CustomStringConvertible, Sendable {
    case unsupportedSchema(Int)
    case unsupportedMetric(String)
    case unsupportedSwiftLanguage(String)
    public var description: String {
        switch self {
        case .unsupportedSchema(let v):
            return
                "Unsupported baseline schemaVersion \(v); expected \(swiftMcCabeSchemaVersion)."
        case .unsupportedMetric(let v):
            return
                "Unsupported baseline metric '\(v)'; expected '\(swiftMcCabeMetric)'."
        case .unsupportedSwiftLanguage(let v):
            return
                "Unsupported baseline Swift language '\(v)'; expected '\(swiftMcCabeLanguageVersion)'."
        }
    }
}

public struct BaselineObservation: Hashable, Sendable {
    public let key: String
    public let identity: String
    public let path: String
    public let location: SourceLocation
    public let complexity: Int
    public init(
        key: String,
        identity: String,
        path: String,
        location: SourceLocation,
        complexity: Int
    ) {
        self.key = key
        self.identity = identity
        self.path = path
        self.location = location
        self.complexity = complexity
    }
}

public enum ComplexityDeltaState: String, Codable, Sendable {
    case added, changed, removed, unchanged
}
public struct ComplexityDelta: Codable, Hashable, Sendable {
    public let key: String
    public let identity: String
    public let path: String
    public let location: SourceLocation?
    public let previous: Int?
    public let current: Int?
    public init(
        key: String,
        identity: String,
        path: String,
        location: SourceLocation?,
        previous: Int?,
        current: Int?
    ) {
        self.key = key
        self.identity = identity
        self.path = path
        self.location = location
        self.previous = previous
        self.current = current
    }
    public var state: ComplexityDeltaState {
        switch (previous, current) {
        case (nil, .some): return .added
        case (.some, nil): return .removed
        case (.some(let a), .some(let b)): return a == b ? .unchanged : .changed
        case (nil, nil): return .unchanged
        }
    }
    public var change: Int? {
        guard let previous = previous, let current = current else { return nil }
        return current - previous
    }
}

extension ComplexityBaseline {
    public func deltas(comparedTo observations: [BaselineObservation])
        -> [ComplexityDelta]
    {
        var deltas: [ComplexityDelta] = []
        var currentKeys = Set<String>()
        for item in observations {
            currentKeys.insert(item.key)
            deltas.append(
                ComplexityDelta(
                    key: item.key,
                    identity: item.identity,
                    path: item.path,
                    location: item.location,
                    previous: entries[item.key],
                    current: item.complexity
                )
            )
        }
        for (key, previous) in entries where !currentKeys.contains(key) {
            let parts = key.components(separatedBy: "::")
            deltas.append(
                ComplexityDelta(
                    key: key,
                    identity: parts.dropFirst().joined(separator: "::"),
                    path: parts.first ?? "<baseline>",
                    location: nil,
                    previous: previous,
                    current: nil
                )
            )
        }
        return deltas.sorted { $0.key < $1.key }
    }
}

public struct ComplexityAnalysisOutput: Codable, Sendable {
    public let schemaVersion: Int
    public let metric: String
    public let swiftLanguageVersion: String
    public let reports: [FileComplexityReport]
    public let deltas: [ComplexityDelta]
    public init(reports: [FileComplexityReport], deltas: [ComplexityDelta] = [])
    {
        schemaVersion = swiftMcCabeSchemaVersion
        metric = swiftMcCabeMetric
        swiftLanguageVersion = swiftMcCabeLanguageVersion
        self.reports = reports
        self.deltas = deltas
    }
}
