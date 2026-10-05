import CyclomaticComplexity
import Foundation
import Testing

@Suite("Swift 6.4 cyclomatic complexity")
struct CyclomaticComplexityTests {
    private let analyzer = CyclomaticComplexityAnalyzer()

    @Test("straight-line function has baseline complexity one")
    func baseline() throws {
        let result = try #require(
            analyzer.analyze(source: "func f() { print(1) }").results.first
        )
        #expect(result.complexity == 1)
        #expect(result.location.line == 1)
        #expect(result.location.column == 1)
    }

    @Test("severity thresholds are inclusive")
    func severityThresholds() throws {
        let policy = try ComplexityPolicy(
            warningThreshold: 3,
            errorThreshold: 7
        )
        #expect(policy.severity(for: 2) == .acceptable)
        #expect(policy.severity(for: 3) == .warning)
        #expect(policy.severity(for: 6) == .warning)
        #expect(policy.severity(for: 7) == .error)
    }

    @Test("if, guard, loops, and short circuit operators contribute")
    func decisions() throws {
        let source = """
            func f(_ a: Bool, _ b: Bool, _ c: Bool) {
                guard a else { return }
                if b && c { print("yes") }
                while a || b { break }
            }
            """
        let result = try #require(
            analyzer.analyze(source: source).results.first
        )
        #expect(result.complexity == 6)  // baseline + guard + if + && + while + ||
    }

    @Test("else-if is another if decision")
    func elseIf() throws {
        let source = """
            func classify(_ x: Int) {
                if x < 0 { print("negative") }
                else if x == 0 { print("zero") }
                else { print("positive") }
            }
            """
        let result = try #require(
            analyzer.analyze(source: source).results.first
        )
        #expect(result.complexity == 3)
    }

    @Test(
        "switch contributes alternatives minus one and comma patterns share a body"
    )
    func switchAlternatives() throws {
        let source = """
            enum E { case a, b, c, d }
            func f(_ value: E) {
                switch value {
                case .a, .b: print("ab")
                case .c where Bool.random(): print("c")
                default: print("other")
                }
            }
            """
        let result = try #require(
            analyzer.analyze(source: source).results.first {
                $0.name.hasPrefix("f(")
            }
        )
        #expect(result.complexity == 4)
    }

    @Test("switch expressions use the same alternative rule")
    func switchExpression() throws {
        let source = """
            enum E { case a, b, c }
            func f(_ value: E) -> Int {
                switch value {
                case .a: 1
                case .b: 2
                case .c: 3
                }
            }
            """
        let result = try #require(
            analyzer.analyze(source: source).results.first {
                $0.name.hasPrefix("f(")
            }
        )
        #expect(result.complexity == 3)
    }

    @Test("nested closure is independent and receives stable location identity")
    func closureBoundary() throws {
        let source = """
            struct Worker {
                func outer(_ flag: Bool) {
                    let work = {
                        if flag { print("nested") }
                    }
                    work()
                }
            }
            """
        let results = analyzer.analyze(source: source).results
        let outer = try #require(results.first { $0.name.hasPrefix("outer(") })
        let closure = try #require(results.first { $0.kind == "closure" })
        #expect(outer.complexity == 1)
        #expect(closure.complexity == 2)
        #expect(outer.identity == "Worker.outer(_:Bool)")
        #expect(closure.identity == "Worker.outer(_:Bool).closure[work]")
    }

    @Test("nested local function is independent")
    func localFunctionBoundary() throws {
        let source = """
            func outer(_ flag: Bool) {
                func inner() {
                    if flag { print(flag) }
                }
                inner()
            }
            """
        let results = analyzer.analyze(source: source).results
        #expect(
            try #require(results.first { $0.identity == "outer(_:Bool)" })
                .complexity == 1
        )
        #expect(
            try #require(
                results.first { $0.identity == "outer(_:Bool).inner()" }
            ).complexity == 2
        )
    }

    @Test("ternary nil-coalescing repeat and catch contribute")
    func expressionsAndErrors() throws {
        let source = """
            enum E: Error { case bad }
            func f(_ x: Int?, _ flag: Bool) {
                let y = x ?? 0
                let z = flag ? 1 : 2
                for _ in 0..<z { print(y) }
                repeat { print(y) } while flag
                do { throw E.bad } catch { print(error) }
            }
            """
        let result = try #require(
            analyzer.analyze(source: source).results.first {
                $0.name.hasPrefix("f(")
            }
        )
        #expect(result.complexity == 6)
    }

    @Test("for await is one loop decision")
    func forAwait() throws {
        let source = """
            func consume<S: AsyncSequence>(_ stream: S) async throws {
                for try await value in stream { print(value) }
            }
            """
        let result = try #require(
            analyzer.analyze(source: source).results.first
        )
        #expect(result.complexity == 2)
    }

    @Test("multiple catches each contribute and typed throws itself does not")
    func catchesAndTypedThrows() throws {
        let source = """
            enum E: Error { case a, b }
            func f() throws(E) {
                do { throw E.a }
                catch E.a { print("a") }
                catch { print("other") }
            }
            """
        let result = try #require(
            analyzer.analyze(source: source).results.first {
                $0.name.hasPrefix("f(")
            }
        )
        #expect(result.complexity == 3)
    }

    @Test(
        "multi-condition guard counts guard plus explicit short-circuit operators"
    )
    func guardConditions() throws {
        let source = """
            func f(_ x: Int?, _ ready: Bool) {
                guard let x, x > 0 && ready else { return }
                print(x)
            }
            """
        let result = try #require(
            analyzer.analyze(source: source).results.first
        )
        #expect(result.complexity == 4)
    }

    @Test("shorthand computed property getter is an independent callable")
    func shorthandGetter() throws {
        let source = """
            struct S {
                var value: Int {
                    if Bool.random() { return 1 }
                    return 0
                }
            }
            """
        let result = try #require(
            analyzer.analyze(source: source).results.first {
                $0.kind == "getter"
            }
        )
        #expect(result.identity == "S.value.get")
        #expect(result.complexity == 2)
    }

    @Test("explicit property accessors are separate callables")
    func explicitAccessors() throws {
        let source = """
            struct S {
                private var storage = 0
                var value: Int {
                    get { if storage > 0 { return storage }; return 0 }
                    set { if newValue >= 0 { storage = newValue } }
                }
            }
            """
        let results = analyzer.analyze(source: source).results.filter {
            $0.kind == "accessor"
        }
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.complexity == 2 })
    }

    @Test("shorthand subscript getter is measured")
    func shorthandSubscript() throws {
        let source = """
            struct S {
                subscript(index: Int) -> Int {
                    if index >= 0 { return index }
                    return 0
                }
            }
            """
        let result = try #require(
            analyzer.analyze(source: source).results.first {
                $0.kind == "subscript-getter"
            }
        )
        #expect(result.identity == "S.subscript(index:Int)->Int.get")
        #expect(result.complexity == 2)
    }

    @Test("explicit subscript accessors are measured separately")
    func explicitSubscriptAccessors() throws {
        let source = """
            struct S {
                private var storage = [0]
                subscript(index: Int) -> Int {
                    get { if index >= 0 { return storage[index] }; return 0 }
                    set { if index >= 0 { storage[index] = newValue } }
                }
            }
            """
        let results = analyzer.analyze(source: source).results.filter {
            $0.kind == "accessor" && $0.name.hasPrefix("subscript.")
        }
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.complexity == 2 })
    }

    @Test("overloaded functions have distinct stable identities")
    func overloadIdentity() {
        let source = """
            struct S {
                func load(_ value: Int) {}
                func load(named value: String) {}
            }
            """
        let identities = Set(
            analyzer.analyze(source: source).results.map(\.identity)
        )
        #expect(identities.contains("S.load(_:Int)"))
        #expect(identities.contains("S.load(named:String)"))
    }

    @Test("aggregate metrics are informational summaries")
    func aggregates() {
        let report = analyzer.analyze(
            source: "func a() {}\nfunc b(_ x: Bool) { if x {} }"
        )
        #expect(report.aggregateComplexity == 3)
        #expect(report.maximumComplexity == 2)
    }

    @Test("default configuration uses strict 3/7 gate")
    func configurationDefaults() {
        let configuration = ComplexityConfiguration()
        #expect(configuration.warningThreshold == 3)
        #expect(configuration.errorThreshold == 7)
        #expect(configuration.explainErrors)
        #expect(!configuration.warningsAsErrors)
    }

    @Test("configuration excludes generated path components")
    func exclusions() {
        let configuration = ComplexityConfiguration()
        #expect(!configuration.includes(path: "/tmp/DerivedData/Foo.swift"))
        #expect(configuration.includes(path: "/tmp/Sources/Foo.swift"))
    }

    @Test("same-label overloads use signature-safe machine identities")
    func sameLabelOverloadIdentity() {
        let source = """
            struct S {
                func load(_ value: Int) {}
                func load(_ value: String) {}
            }
            """
        let identities = Set(
            analyzer.analyze(source: source).results.map(\.identity)
        )
        #expect(identities.contains("S.load(_:Int)"))
        #expect(identities.contains("S.load(_:String)"))
        #expect(identities.count == 2)
    }

    @Test("nested closures receive hierarchical identities")
    func nestedClosureIdentity() throws {
        let source = """
            func outer() {
                let a = {
                    let b = {
                        if Bool.random() { print("nested") }
                    }
                    b()
                }
                a()
            }
            """
        let closures = analyzer.analyze(source: source).results.filter {
            $0.kind == "closure"
        }
        #expect(closures.map(\.identity).contains("outer().closure[a]"))
        #expect(
            closures.map(\.identity).contains("outer().closure[a].closure[b]")
        )
    }

    @Test("partial configuration inherits defaults")
    func partialConfiguration() throws {
        let configuration = try JSONDecoder().decode(
            ComplexityConfiguration.self,
            from: Data(#"{"errorThreshold":6}"#.utf8)
        )
        #expect(configuration.warningThreshold == 3)
        #expect(configuration.errorThreshold == 6)
        #expect(
            configuration.excludedPathComponents == [
                ".build", "DerivedData", "Generated",
            ]
        )
        #expect(configuration.explainErrors)
    }

    @Test(
        "malformed source is unscorable instead of receiving a confident score"
    )
    func parseFailure() {
        let report = analyzer.analyze(source: "func broken( { if true {}")
        #expect(!report.isScorable)
        #expect(report.results.isEmpty)
        #expect(!report.parseIssues.isEmpty)
    }

    @Test(
        "conditional compilation branches are both analyzed with collision-safe identities"
    )
    func conditionalCompilationIdentity() {
        let source = """
            #if DEBUG
            func mode(_ value: Int) { if value > 0 {} }
            #else
            func mode(_ value: Int) { if value < 0 {} }
            #endif
            """
        let results = analyzer.analyze(source: source).results
        #expect(results.count == 2)
        #expect(Set(results.map(\.identity)).count == 2)
        #expect(
            results.allSatisfy {
                $0.identity.contains("#if") || $0.identity.contains("#else")
            }
        )
    }

    @Test("golden Swift fixture preserves stable scores and identities")
    func goldenFixture() throws {
        let fixture = try #require(
            Bundle.module.url(
                forResource: "SyncCoordinator",
                withExtension: "swift",
                subdirectory: "Fixtures"
            )
        )
        let expectedURL = try #require(
            Bundle.module.url(
                forResource: "SyncCoordinator.expected",
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        )
        let source = try String(contentsOf: fixture, encoding: .utf8)
        let expected = try JSONDecoder().decode(
            [String: Int].self,
            from: Data(contentsOf: expectedURL)
        )
        let report = analyzer.analyze(source: source, path: fixture.path)
        #expect(report.isScorable)
        #expect(
            Dictionary(
                uniqueKeysWithValues: report.results.map {
                    ($0.identity, $0.complexity)
                }
            ) == expected
        )
    }

    @Test("static and instance overloads cannot collide in baselines")
    func staticInstanceIdentity() {
        let source = """
            struct S {
                func resolve(_ value: Int) {}
                static func resolve(_ value: Int) {}
            }
            """
        let identities = Set(
            analyzer.analyze(source: source).results.map(\.identity)
        )
        #expect(identities.contains("S.resolve(_:Int)"))
        #expect(identities.contains("S.static resolve(_:Int)"))
    }

    @Test("comma condition chains match boolean short-circuit complexity")
    func commaConditionChains() throws {
        let comma = try #require(
            analyzer.analyze(
                source: "func f(_ a: Bool, _ b: Bool) { if a, b {} }"
            ).results.first
        )
        let logical = try #require(
            analyzer.analyze(
                source: "func f(_ a: Bool, _ b: Bool) { if a && b {} }"
            ).results.first
        )
        #expect(comma.complexity == 3)
        #expect(comma.complexity == logical.complexity)
        #expect(comma.contributions.contains { $0.kind == .conditionChain })
    }

    @Test("guard and while comma conditions count each additional condition")
    func guardWhileConditionChains() throws {
        let source = """
            func f(_ a: Bool, _ b: Bool) {
                guard a, b else { return }
                while a, b { break }
            }
            """
        let result = try #require(
            analyzer.analyze(source: source).results.first
        )
        #expect(result.complexity == 5)
        #expect(
            result.contributions.filter { $0.kind == .conditionChain }.count
                == 2
        )
    }

    @Test("for and switch where predicates add paths")
    func wherePredicates() throws {
        let source = """
            func f(_ xs: [Int], _ x: Int) {
                for value in xs where value > 0 { print(value) }
                switch x {
                case let value where value > 0: print(value)
                default: break
                }
            }
            """
        let result = try #require(
            analyzer.analyze(source: source).results.first
        )
        #expect(result.complexity == 5)
        #expect(
            result.contributions.filter { $0.kind == .wherePredicate }.count
                == 2
        )
    }

    @Test("configuration validation never traps on bad external input")
    func configurationValidation() {
        #expect(throws: ComplexityConfigurationError.self) {
            try ComplexityConfiguration(warningThreshold: 0).validatedPolicy()
        }
        #expect(throws: ComplexityConfigurationError.self) {
            try ComplexityConfiguration(warningThreshold: 7, errorThreshold: 7)
                .validatedPolicy()
        }
        #expect(throws: ComplexityConfigurationError.self) {
            try ComplexityConfiguration(warningThreshold: 8, errorThreshold: 7)
                .validatedPolicy()
        }
    }

    @Test("baseline contract is versioned and validated")
    func baselineSchema() throws {
        try ComplexityBaseline().validate()
        #expect(throws: BaselineError.self) {
            try ComplexityBaseline(schemaVersion: 99).validate()
        }
        #expect(throws: BaselineError.self) {
            try ComplexityBaseline(metric: "other").validate()
        }
    }

    @Test("JSON output has an explicit protocol envelope")
    func outputSchema() throws {
        let output = ComplexityAnalysisOutput(reports: [
            analyzer.analyze(source: "func f() {}")
        ])
        let data = try JSONEncoder().encode(output)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["metric"] as? String == "swift-mccabe")
        #expect(object["swiftLanguageVersion"] as? String == "6.4")
    }

    @Test(
        "named closure identities survive unrelated closure insertion better than ordinals"
    )
    func structuralClosureIdentity() {
        let source = """
            func f() {
                let completion = { if Bool.random() {} }
                completion()
            }
            """
        let identities = analyzer.analyze(source: source).results.map(
            \.identity
        )
        #expect(identities.contains("f().closure[completion]"))
    }

    @Test(
        "baseline deltas explicitly represent added changed removed and unchanged callables"
    )
    func baselineDeltaStates() {
        let baseline = ComplexityBaseline(entries: [
            "A.swift::a()": 2, "B.swift::b()": 3, "D.swift::d()": 1,
        ])
        let observations = [
            BaselineObservation(
                key: "A.swift::a()",
                identity: "a()",
                path: "A.swift",
                location: SourceLocation(line: 1, column: 1),
                complexity: 4
            ),
            BaselineObservation(
                key: "C.swift::c()",
                identity: "c()",
                path: "C.swift",
                location: SourceLocation(line: 1, column: 1),
                complexity: 2
            ),
            BaselineObservation(
                key: "D.swift::d()",
                identity: "d()",
                path: "D.swift",
                location: SourceLocation(line: 1, column: 1),
                complexity: 1
            ),
        ]
        let states = Dictionary(
            uniqueKeysWithValues: baseline.deltas(comparedTo: observations).map
            { ($0.identity, $0.state) }
        )
        #expect(states["a()"] == .changed)
        #expect(states["b()"] == .removed)
        #expect(states["c()"] == .added)
        #expect(states["d()"] == .unchanged)
    }

    @Test("versioned JSON output shape is golden-tested")
    func outputGoldenShape() throws {
        let expectedURL = try #require(
            Bundle.module.url(
                forResource: "OutputEnvelope.expected",
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        )
        let expected = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: expectedURL))
                as? NSDictionary
        )
        let output = ComplexityAnalysisOutput(reports: [
            analyzer.analyze(source: "func f() {}")
        ])
        let actual = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(output))
                as? NSDictionary
        )
        #expect(actual == expected)
    }

    @Test("reused structural closure names remain collision-safe")
    func repeatedStructuralClosureNames() {
        let source = """
            func f(_ flag: Bool) {
                if flag { let work = { print(1) }; work() }
                else { let work = { print(2) }; work() }
            }
            """
        let identities = analyzer.analyze(source: source).results.filter {
            $0.kind == "closure"
        }.map(\.identity)
        #expect(identities.contains("f(_:Bool).closure[work]"))
        #expect(identities.contains("f(_:Bool).closure[work]#2"))
        #expect(Set(identities).count == 2)
    }

}
