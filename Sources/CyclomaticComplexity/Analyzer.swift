import Foundation
import SwiftDiagnostics
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

public struct CyclomaticComplexityAnalyzer: Sendable {
    public init() {}

    public func analyze(source: String, path: String = "<memory>")
        -> FileComplexityReport
    {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: path, tree: tree)
        let parseIssues = ParseDiagnosticsGenerator.diagnostics(for: tree)
            .compactMap { diagnostic -> ParseIssue? in
                guard diagnostic.diagMessage.severity == .error else {
                    return nil
                }
                let location = diagnostic.location(converter: converter)
                return ParseIssue(
                    message: diagnostic.message,
                    location: SourceLocation(
                        line: location.line,
                        column: location.column
                    )
                )
            }
        guard parseIssues.isEmpty else {
            return FileComplexityReport(
                path: path,
                results: [],
                parseIssues: parseIssues
            )
        }
        let collector = CallableCollector(converter: converter)
        collector.walk(tree)
        return FileComplexityReport(path: path, results: collector.results)
    }
}

private final class CallableCollector: SyntaxVisitor {
    private let converter: SourceLocationConverter
    private(set) var results: [ComplexityResult] = []
    private var closureOrdinals: [String: Int] = [:]
    private var structuralClosureOrdinals: [String: Int] = [:]
    private var closureLeafByPosition: [Int: String] = [:]

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind
    {
        if let body = node.body {
            measure(
                display: functionDisplayName(node),
                leaf: functionIdentity(node),
                kind: "function",
                declaration: Syntax(node.funcKeyword),
                body: Syntax(body),
                node: Syntax(node)
            )
        }
        return .visitChildren
    }
    override func visit(_ node: InitializerDeclSyntax)
        -> SyntaxVisitorContinueKind
    {
        if let body = node.body {
            measure(
                display: initializerDisplayName(node),
                leaf: initializerIdentity(node),
                kind: "initializer",
                declaration: Syntax(node.initKeyword),
                body: Syntax(body),
                node: Syntax(node)
            )
        }
        return .visitChildren
    }
    override func visit(_ node: DeinitializerDeclSyntax)
        -> SyntaxVisitorContinueKind
    {
        if let body = node.body {
            measure(
                display: "deinit",
                leaf: "deinit",
                kind: "deinitializer",
                declaration: Syntax(node.deinitKeyword),
                body: Syntax(body),
                node: Syntax(node)
            )
        }
        return .visitChildren
    }
    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind
    {
        if let body = node.body {
            measure(
                display: accessorDisplayName(node),
                leaf: accessorIdentity(node),
                kind: "accessor",
                declaration: Syntax(node.accessorSpecifier),
                body: Syntax(body),
                node: Syntax(node)
            )
        }
        return .visitChildren
    }
    override func visit(_ node: PatternBindingSyntax)
        -> SyntaxVisitorContinueKind
    {
        guard let block = node.accessorBlock else { return .visitChildren }
        if case .getter(let body) = block.accessors {
            let name = "\(node.pattern.trimmedDescription).get"
            measure(
                display: name,
                leaf: patternBindingIdentity(node),
                kind: "getter",
                declaration: Syntax(node.pattern),
                body: Syntax(body),
                node: Syntax(node)
            )
        }
        return .visitChildren
    }
    override func visit(_ node: SubscriptDeclSyntax)
        -> SyntaxVisitorContinueKind
    {
        guard let block = node.accessorBlock else { return .visitChildren }
        if case .getter(let body) = block.accessors {
            measure(
                display: "\(subscriptDisplayName(node)).get",
                leaf: "\(subscriptIdentity(node)).get",
                kind: "subscript-getter",
                declaration: Syntax(node.subscriptKeyword),
                body: Syntax(body),
                node: Syntax(node)
            )
        }
        return .visitChildren
    }
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind
    {
        let parent = ancestorComponents(for: Syntax(node)).joined(
            separator: "."
        )
        let ordinal = (closureOrdinals[parent] ?? 0) + 1
        closureOrdinals[parent] = ordinal
        let leaf: String
        if let structural = structuralClosureLeaf(node) {
            let structuralKey = parent + "." + structural
            let structuralOrdinal =
                (structuralClosureOrdinals[structuralKey] ?? 0) + 1
            structuralClosureOrdinals[structuralKey] = structuralOrdinal
            leaf =
                structuralOrdinal == 1
                ? structural : "\(structural)#\(structuralOrdinal)"
        } else {
            leaf = "closure#\(ordinal)"
        }
        closureLeafByPosition[
            node.positionAfterSkippingLeadingTrivia.utf8Offset
        ] = leaf
        measure(
            display: leaf,
            leaf: leaf,
            kind: "closure",
            declaration: Syntax(node.leftBrace),
            body: Syntax(node.statements),
            node: Syntax(node)
        )
        return .visitChildren
    }

    private func structuralClosureLeaf(_ node: ClosureExprSyntax) -> String? {
        var current = Syntax(node).parent
        while let syntax = current {
            if let binding = syntax.as(PatternBindingSyntax.self),
                binding.initializer?.value.as(ClosureExprSyntax.self)?.id
                    == node.id
            {
                let name = binding.pattern.trimmedDescription
                if !name.isEmpty { return "closure[\(name)]" }
            }
            // Stop before crossing another callable boundary.
            if syntax.is(FunctionDeclSyntax.self)
                || syntax.is(InitializerDeclSyntax.self)
                || syntax.is(AccessorDeclSyntax.self)
                || syntax.is(ClosureExprSyntax.self)
            {
                break
            }
            current = syntax.parent
        }
        return nil
    }

    private func measure(
        display: String,
        leaf: String,
        kind: String,
        declaration: Syntax,
        body: Syntax,
        node: Syntax
    ) {
        let visitor = DecisionVisitor(converter: converter)
        visitor.walk(body)
        results.append(
            ComplexityResult(
                identity: (ancestorComponents(for: node) + [leaf]).joined(
                    separator: "."
                ),
                name: display,
                kind: kind,
                location: sourceLocation(for: declaration),
                complexity: 1
                    + visitor.contributions.reduce(0) { $0 + $1.increment },
                contributions: visitor.contributions
            )
        )
    }

    private func sourceLocation(for syntax: Syntax) -> SourceLocation {
        let location = converter.location(
            for: syntax.positionAfterSkippingLeadingTrivia
        )
        return SourceLocation(line: location.line, column: location.column)
    }

    private func functionDisplayName(_ node: FunctionDeclSyntax) -> String {
        "\(node.name.text)\(parameterLabels(node.signature.parameterClause.parameters))"
    }
    private func initializerDisplayName(_ node: InitializerDeclSyntax) -> String
    { "init\(parameterLabels(node.signature.parameterClause.parameters))" }
    private func subscriptDisplayName(_ node: SubscriptDeclSyntax) -> String {
        "subscript\(parameterLabels(node.parameterClause.parameters))"
    }

    private func functionIdentity(_ node: FunctionDeclSyntax) -> String {
        let generic = node.genericParameterClause?.trimmedDescription ?? ""
        let whereClause =
            node.genericWhereClause.map { "\($0.trimmedDescription)" } ?? ""
        return
            "\(scopeModifier(node.modifiers))\(node.name.text)\(generic)\(typedParameters(node.signature.parameterClause.parameters))\(effectAndReturn(node.signature))\(whereClause)"
    }
    private func initializerIdentity(_ node: InitializerDeclSyntax) -> String {
        let generic = node.genericParameterClause?.trimmedDescription ?? ""
        let whereClause =
            node.genericWhereClause.map { "\($0.trimmedDescription)" } ?? ""
        return
            "init\(generic)\(typedParameters(node.signature.parameterClause.parameters))\(node.signature.effectSpecifiers?.trimmedDescription ?? "")\(whereClause)"
    }
    private func subscriptIdentity(_ node: SubscriptDeclSyntax) -> String {
        let generic = node.genericParameterClause?.trimmedDescription ?? ""
        let whereClause =
            node.genericWhereClause.map { "\($0.trimmedDescription)" } ?? ""
        return
            "\(scopeModifier(node.modifiers))subscript\(generic)\(typedParameters(node.parameterClause.parameters))->\(node.returnClause.type.trimmedDescription)\(whereClause)"
    }
    private func effectAndReturn(_ signature: FunctionSignatureSyntax) -> String
    {
        (signature.effectSpecifiers?.trimmedDescription ?? "")
            + (signature.returnClause.map { "->\($0.type.trimmedDescription)" }
                ?? "")
    }
    private func typedParameters(_ parameters: FunctionParameterListSyntax)
        -> String
    {
        "("
            + parameters.map {
                "\($0.firstName.text):\($0.type.trimmedDescription)\($0.ellipsis == nil ? "" : "...")"
            }.joined(separator: ",") + ")"
    }
    private func parameterLabels(_ parameters: FunctionParameterListSyntax)
        -> String
    { "(" + parameters.map { "\($0.firstName.text):" }.joined() + ")" }
    private func scopeModifier(_ modifiers: DeclModifierListSyntax) -> String {
        if modifiers.contains(where: { $0.name.text == "static" }) {
            return "static "
        }
        if modifiers.contains(where: { $0.name.text == "class" }) {
            return "class "
        }
        return ""
    }

    private func patternBindingIdentity(_ binding: PatternBindingSyntax)
        -> String
    {
        var parent = Syntax(binding).parent
        while let current = parent {
            if let variable = current.as(VariableDeclSyntax.self) {
                return
                    "\(scopeModifier(variable.modifiers))\(binding.pattern.trimmedDescription).get"
            }
            parent = current.parent
        }
        return "\(binding.pattern.trimmedDescription).get"
    }

    private func accessorDisplayName(_ node: AccessorDeclSyntax) -> String {
        var parent = Syntax(node).parent
        while let current = parent {
            if let subscriptDecl = current.as(SubscriptDeclSyntax.self) {
                return
                    "\(subscriptDisplayName(subscriptDecl)).\(node.accessorSpecifier.text)"
            }
            if let variable = current.as(VariableDeclSyntax.self),
                let binding = variable.bindings.first
            {
                return
                    "\(binding.pattern.trimmedDescription).\(node.accessorSpecifier.text)"
            }
            parent = current.parent
        }
        return node.accessorSpecifier.text
    }
    private func accessorIdentity(_ node: AccessorDeclSyntax) -> String {
        var parent = Syntax(node).parent
        while let current = parent {
            if let subscriptDecl = current.as(SubscriptDeclSyntax.self) {
                return
                    "\(subscriptIdentity(subscriptDecl)).\(node.accessorSpecifier.text)"
            }
            if let variable = current.as(VariableDeclSyntax.self),
                let binding = variable.bindings.first
            {
                return
                    "\(scopeModifier(variable.modifiers))\(binding.pattern.trimmedDescription).\(node.accessorSpecifier.text)"
            }
            parent = current.parent
        }
        return node.accessorSpecifier.text
    }

    private func ancestorComponents(for node: Syntax) -> [String] {
        var components: [String] = []
        var parent = node.parent
        while let current = parent {
            if let closure = current.as(ClosureExprSyntax.self),
                let leaf = closureLeafByPosition[
                    closure.positionAfterSkippingLeadingTrivia.utf8Offset
                ]
            {
                components.append(leaf)
            } else if let accessor = current.as(AccessorDeclSyntax.self) {
                components.append(accessorIdentity(accessor))
            } else if let binding = current.as(PatternBindingSyntax.self),
                let block = binding.accessorBlock,
                case .getter = block.accessors
            {
                components.append(patternBindingIdentity(binding))
            } else if let subscriptDecl = current.as(SubscriptDeclSyntax.self),
                let block = subscriptDecl.accessorBlock,
                case .getter = block.accessors
            {
                components.append("\(subscriptIdentity(subscriptDecl)).get")
            } else if let function = current.as(FunctionDeclSyntax.self) {
                components.append(functionIdentity(function))
            } else if let initializer = current.as(InitializerDeclSyntax.self) {
                components.append(initializerIdentity(initializer))
            } else if current.is(DeinitializerDeclSyntax.self) {
                components.append("deinit")
            } else if let clause = current.as(IfConfigClauseSyntax.self) {
                components.append(ifConfigIdentity(clause))
            } else if let type = current.as(StructDeclSyntax.self) {
                components.append(type.name.text)
            } else if let type = current.as(ClassDeclSyntax.self) {
                components.append(type.name.text)
            } else if let type = current.as(EnumDeclSyntax.self) {
                components.append(type.name.text)
            } else if let type = current.as(ActorDeclSyntax.self) {
                components.append(type.name.text)
            } else if let type = current.as(ProtocolDeclSyntax.self) {
                components.append(type.name.text)
            } else if let ext = current.as(ExtensionDeclSyntax.self) {
                components.append(ext.extendedType.trimmedDescription)
            }
            parent = current.parent
        }
        return components.reversed()
    }

    private func ifConfigIdentity(_ clause: IfConfigClauseSyntax) -> String {
        let keyword = clause.poundKeyword.text
        let condition = clause.condition?.trimmedDescription ?? ""
        return condition.isEmpty ? keyword : "\(keyword)(\(condition))"
    }
}

private final class DecisionVisitor: SyntaxVisitor {
    private let converter: SourceLocationConverter
    private(set) var contributions: [ComplexityContribution] = []
    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind
    { .skipChildren }
    override func visit(_ node: InitializerDeclSyntax)
        -> SyntaxVisitorContinueKind
    { .skipChildren }
    override func visit(_ node: DeinitializerDeclSyntax)
        -> SyntaxVisitorContinueKind
    { .skipChildren }
    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind
    { .skipChildren }
    override func visit(_ node: PatternBindingSyntax)
        -> SyntaxVisitorContinueKind
    { node.accessorBlock == nil ? .visitChildren : .skipChildren }
    override func visit(_ node: SubscriptDeclSyntax)
        -> SyntaxVisitorContinueKind
    { .skipChildren }
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind
    { .skipChildren }

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        add(.ifStatement, at: Syntax(node))
        addConditionChain(node.conditions)
        return .visitChildren
    }
    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        add(.guardStatement, at: Syntax(node))
        addConditionChain(node.conditions)
        return .visitChildren
    }
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        add(.forLoop, at: Syntax(node))
        if let whereClause = node.whereClause {
            add(.wherePredicate, at: Syntax(whereClause))
        }
        return .visitChildren
    }
    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        add(.whileLoop, at: Syntax(node))
        addConditionChain(node.conditions)
        return .visitChildren
    }
    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        add(.repeatWhileLoop, at: Syntax(node))
        return .visitChildren
    }
    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind
    {
        add(.catchClause, at: Syntax(node))
        return .visitChildren
    }
    override func visit(_ node: TernaryExprSyntax) -> SyntaxVisitorContinueKind
    {
        add(.ternary, at: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: SwitchCaseItemSyntax)
        -> SyntaxVisitorContinueKind
    {
        if let whereClause = node.whereClause {
            add(.wherePredicate, at: Syntax(whereClause))
        }
        return .visitChildren
    }

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        let alternatives = node.cases.compactMap {
            $0.as(SwitchCaseSyntax.self)
        }
        for alternative in alternatives.dropFirst() {
            add(.switchAlternative, at: Syntax(alternative))
        }
        return .visitChildren
    }

    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        switch token.tokenKind {
        case .binaryOperator("&&"): add(.logicalAnd, at: Syntax(token))
        case .binaryOperator("||"): add(.logicalOr, at: Syntax(token))
        case .binaryOperator("??"): add(.nilCoalescing, at: Syntax(token))
        default: break
        }
        return .visitChildren
    }

    private func addConditionChain(_ conditions: ConditionElementListSyntax) {
        for condition in conditions.dropFirst() {
            add(.conditionChain, at: Syntax(condition))
        }
    }

    private func add(_ kind: DecisionKind, at syntax: Syntax) {
        let location = converter.location(
            for: syntax.positionAfterSkippingLeadingTrivia
        )
        let excerpt =
            syntax.firstToken(viewMode: .sourceAccurate)?.text ?? kind.rawValue
        contributions.append(
            ComplexityContribution(
                kind: kind,
                increment: 1,
                location: SourceLocation(
                    line: location.line,
                    column: location.column
                ),
                excerpt: excerpt
            )
        )
    }
}
