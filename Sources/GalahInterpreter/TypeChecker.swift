public struct TypeChecker {
    public static func check(
        _ ast: AST,
        _ builtinTypes: [BuiltinType],
        _ builtinFns: [BuiltinFn]
    ) throws -> WithDiagnostics<CheckedAST> {
        try TypeChecker(ast, builtinTypes, builtinFns).check()
    }

    typealias LocalsTable = [String: (index: Int, type: Type)]
    typealias Typed = CheckedAST.Typed

    private struct Analyzed<T> {
        var inner: T
        var returnsOnAllPaths: Bool
        var diagnostics: [Diagnostic]

        init(_ inner: T, returnsOnAllPaths: Bool, diagnostics: [Diagnostic] = []) {
            self.inner = inner
            self.returnsOnAllPaths = returnsOnAllPaths
            self.diagnostics = diagnostics
        }

        func map<U>(_ action: (T) -> U) -> Analyzed<U> {
            Analyzed<U>(
                action(inner),
                returnsOnAllPaths: returnsOnAllPaths
            )
        }
    }

    private struct FnContext {
        struct Local {
            var ident: String
            var type: Type
        }

        typealias LocalIndex = Int

        var expectedReturnType: Type

        /// The number of locals in the context.
        var localCount: Int {
            locals.count
        }

        private var locals: [Local]
        private var scopes: [[String: LocalIndex]]
        var diagnostics: [Diagnostic]

        private var innermostScope: [String: LocalIndex] {
            get {
                scopes[scopes.count - 1]
            }
            _modify {
                yield &scopes[scopes.count - 1]
            }
        }

        /// Initializes a context with a single empty root scope.
        init(expectedReturnType: Type) {
            self.expectedReturnType = expectedReturnType
            locals = []
            scopes = [[:]]
            diagnostics = []
        }

        @discardableResult
        mutating func newLocal(_ ident: String, type: Type) -> LocalIndex {
            let index = locals.count
            locals.append(Local(ident: ident, type: type))
            innermostScope[ident] = index
            return index
        }

        mutating func pushScope() {
            scopes.append([:])
        }

        mutating func popScope() {
            assert(scopes.count > 1, "Attempted to pop root scope")
            _ = scopes.popLast()
        }

        func local(for ident: String) -> (index: LocalIndex, local: Local)? {
            for scope in scopes.reversed() {
                for (localIdent, index) in scope where localIdent == ident {
                    return (index, locals[index])
                }
            }
            return nil
        }

        func localInInnermostScope(for ident: String) -> (index: LocalIndex, local: Local)? {
            for (localIdent, index) in innermostScope where localIdent == ident {
                return (index, locals[index])
            }
            return nil
        }

        mutating func diagnose(_ diagnostic: Diagnostic) {
            diagnostics.append(diagnostic)
        }
    }

    let builtinTypes: [BuiltinType]
    let builtinFns: [BuiltinFn]
    let structDecls: [WithSpan<StructDecl>]
    let fnDecls: [WithSpan<FnDecl>]
    let fnTable: [(CheckedAST.FnId, FnSignature)]

    private init(_ ast: AST, _ builtinTypes: [BuiltinType], _ builtinFns: [BuiltinFn]) throws {
        self.builtinTypes = builtinTypes
        self.builtinFns = builtinFns
        structDecls = ast.structDecls
        fnDecls = ast.fnDecls
        fnTable = try Self.buildFnLookupTable(fnDecls, builtinFns)
    }

    private func check() throws -> WithDiagnostics<CheckedAST> {
        let structs = try checkStructs(structDecls)
        let fns: WithDiagnostics<[CheckedAST.Fn]> = try fnDecls.map(checkFn).collect()
        return fns.map { fns in
            CheckedAST(
                builtinTypes: builtinTypes,
                structs: structs,
                builtinFns: builtinFns,
                fns: fns
            )
        }
    }

    private func checkStructs(_ structDecls: [WithSpan<StructDecl>]) throws -> [CheckedAST.Struct] {
        var structs: [CheckedAST.Struct] = []
        for structDecl in structDecls {
            guard !builtinTypes.contains(where: { $0.ident == *structDecl.ident }) else {
                throw Diagnostic(
                    error: "Duplicate definition of builtin type '\(*structDecl.ident)'",
                    at: structDecl.ident.span
                )
            }

            // TODO: Include span of the original struct once errors can have multiple diagnostics
            guard !structs.map(\.ident).contains(structDecl.ident.inner) else {
                throw Diagnostic(
                    error: "Duplicate definition of struct '\(*structDecl.ident)'",
                    at: structDecl.ident.span
                )
            }

            var fields: [CheckedAST.Field] = []
            for field in structDecl.fields {
                guard !fields.contains(where: { $0.ident == *field.ident }) else {
                    throw Diagnostic(
                        error:
                            "Duplicate definition of field '\(*structDecl.ident).\(*field.ident)'",
                        at: field.span
                    )
                }
                let type = try checkType(field.type)
                fields.append(CheckedAST.Field(ident: *field.ident, type: type))
            }

            structs.append(CheckedAST.Struct(ident: *structDecl.ident, fields: fields))
        }

        // Check for self-referential structs
        let graph = TypeFieldGraph(builtinTypes: builtinTypes, structs: structs)
        let cycles = graph.cycles()
        guard cycles.isEmpty else {
            let diagnostics = diagnoseCycles(graph, cycles)
            for diagnostic in diagnostics {
                print(diagnostic.description)
            }

            // TODO: Refactor so that we can emit multiple errors
            throw Diagnostic(error: "See above", at: nil)
        }

        return structs
    }

    private func diagnoseCycles(
        _ graph: TypeFieldGraph, _ cycles: [Path<TypeFieldGraph.Node, TypeFieldGraph.Edge>]
    ) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        var diagnosedTypes: [String] = []
        for cycle in cycles {
            for offset in 0..<(cycle.nodes.count - 1) {
                let rotatedCycle = cycle.offset(by: offset)

                guard !diagnosedTypes.contains(graph.ident(of: rotatedCycle.firstNode)) else {
                    continue
                }

                let structDecl: WithSpan<StructDecl>
                switch rotatedCycle.firstNode {
                    case .builtin:
                        diagnostics.append(
                            Diagnostic(
                                error: "Precondition failure: struct cycle starts at builtin",
                                at: nil
                            ))
                        continue
                    case let .struct(index):
                        // TODO: There's not necessarily a guarantee that the indices from the TypeFieldGraph
                        //   will match up with the ordering of structDecls. Should probably try to encode that
                        //   somehow or centralize this functionality.
                        structDecl = structDecls[index]
                }

                let fieldAccesses = rotatedCycle.edges.map(graph.ident(of:))
                    .joined(separator: ".")
                diagnostics.append(
                    Diagnostic(
                        error:
                            "Struct '\(*structDecl.ident)' references itself via '\(*structDecl.ident).\(fieldAccesses)'",
                        at: structDecl.span
                    )
                )
                diagnosedTypes.append(*structDecl.ident)
            }
        }

        return diagnostics
    }

    private func checkFn(_ fn: WithSpan<FnDecl>) throws -> WithDiagnostics<CheckedAST.Fn> {
        let span = fn.span
        let fn = *fn

        if let returnType = fn.signature.returnType {
            try checkType(returnType)
        }

        var context = FnContext(expectedReturnType: fn.signature.returnType?.inner ?? .void)
        for param in fn.params {
            try checkType(param.inner.type)
            context.newLocal(*param.inner.ident, type: *param.inner.type)
        }

        let analyzedStmts = try checkStmts(fn.stmts, &context)
        let returnType = fn.signature.returnType?.inner ?? .void
        guard returnType == .void || analyzedStmts.returnsOnAllPaths else {
            // TODO: Attach the diagnostic to the last statement in each offending path
            throw Diagnostic(error: "Non-void function must return on all paths", at: span)
        }

        return WithDiagnostics(
            CheckedAST.Fn(
                signature: fn.signature, localCount: context.localCount, stmts: analyzedStmts.inner),
            context.diagnostics
        )
    }

    @discardableResult
    private func checkType(_ type: WithSpan<Type>) throws -> CheckedAST.TypeIndex {
        let typeName = type.inner.description
        if let builtinIndex = builtinTypes.firstIndex(where: { $0.ident == typeName }) {
            return .builtin(builtinIndex)
        } else if let structIndex = structDecls.firstIndex(where: { *$0.ident == typeName }) {
            return .struct(structIndex)
        } else {
            throw Diagnostic(error: "No such type '\(typeName)'", at: type.span)
        }
    }

    private func checkStmts(
        _ stmts: [WithSpan<Stmt>],
        _ context: inout FnContext
    ) throws -> Analyzed<[CheckedAST.Stmt]> {
        context.pushScope()
        let analyzedStmts = try stmts.map { stmt in
            try checkStmt(stmt, &context)
        }
        context.popScope()

        let lastReachableIndex = analyzedStmts.firstIndex(where: \.returnsOnAllPaths)
        if let lastReachableIndex, lastReachableIndex < stmts.count - 1 {
            context.diagnose(
                Diagnostic(
                    warning: "warning: Unreachable statements",
                    at: stmts[lastReachableIndex + 1].span))
        }
        return Analyzed(
            analyzedStmts[...(lastReachableIndex ?? analyzedStmts.count - 1)].map(\.inner),
            returnsOnAllPaths: analyzedStmts.contains(where: \.returnsOnAllPaths)
        )
    }

    private func checkStmt(
        _ stmt: WithSpan<Stmt>,
        _ context: inout FnContext
    ) throws -> Analyzed<CheckedAST.Stmt> {
        switch *stmt {
            case let .if(ifStmt):
                return (try checkIfStmt(ifStmt, &context)).map(CheckedAST.Stmt.if)
            case let .return(expr):
                let checkedExpr: Typed<CheckedAST.Expr>? =
                    if let expr {
                        try checkExpr(expr, &context)
                    } else {
                        nil
                    }
                guard (checkedExpr?.type ?? .void) == context.expectedReturnType else {
                    if let expr, let checkedExpr {
                        throw Diagnostic(
                            error:
                                "Function expected to return '\(context.expectedReturnType)', got expression of type '\(checkedExpr.type)'",
                            at: expr.span
                        )
                    } else {
                        throw Diagnostic(
                            error:
                                "Function expected to return '\(context.expectedReturnType)', got 'Void'",
                            at: stmt.span
                        )
                    }
                }
                return Analyzed(.return(checkedExpr), returnsOnAllPaths: true)
            case let .let(varDecl):
                if let type = varDecl.type {
                    try checkType(type)
                }

                let checkedExpr = try checkExpr(varDecl.value, &context)

                if let type = varDecl.type, checkedExpr.type != *type {
                    throw Diagnostic(
                        error:
                            "Let binding '\(*varDecl.ident)' expected expression of type '\(*type)', got expression of type '\(checkedExpr.type)'",
                        at: varDecl.value.span
                    )
                }

                // TODO: Do we allow shadowing within the same scope level? (it should be as easy as just removing this check)
                if context.localInInnermostScope(for: *varDecl.ident) != nil {
                    throw Diagnostic(
                        error: "Duplicate definition of '\(varDecl.ident)' within current scope",
                        at: varDecl.ident.span
                    )
                }

                let index = context.newLocal(*varDecl.ident, type: checkedExpr.type)
                return Analyzed(
                    .let(CheckedAST.VarDecl(localIndex: index, value: checkedExpr)),
                    returnsOnAllPaths: false
                )
            case let .expr(expr):
                return Analyzed(
                    .expr(try checkExpr(WithSpan(expr, stmt.span), &context)),
                    returnsOnAllPaths: false
                )
        }
    }

    private func checkIfStmt(
        _ ifStmt: IfStmt,
        _ context: inout FnContext
    ) throws -> Analyzed<CheckedAST.IfStmt> {
        let condition = try checkExpr(ifStmt.condition, &context)
        guard condition.type == Int.type else {
            throw Diagnostic(
                error:
                    "If statement condition must be of type '\(Int.type)', got \(condition.type)",
                at: ifStmt.condition.span
            )
        }

        let checkedIfBlock = try checkStmts(ifStmt.ifBlock, &context)
        let ifBlock = CheckedAST.IfBlock(
            condition: condition.inner,
            block: checkedIfBlock.inner
        )

        var elseIfBlocks: [CheckedAST.IfBlock] = []
        var elseBlock = ifStmt.else

        var checkedElseBlock: [CheckedAST.Stmt]?

        var returnsOnAllPaths = checkedIfBlock.returnsOnAllPaths
        while elseBlock != nil {
            switch elseBlock {
                case let .elseIf(ifBlock):
                    let condition = try checkExpr(ifBlock.condition, &context)
                    guard condition.type == Int.type else {
                        throw Diagnostic(
                            error:
                                "If statement condition must be of type '\(Int.type)', got \(condition.type)",
                            at: ifBlock.condition.span
                        )
                    }
                    let checkedBlock = try checkStmts(ifBlock.ifBlock, &context)
                    elseIfBlocks.append(
                        CheckedAST.IfBlock(
                            condition: condition.inner,
                            block: checkedBlock.inner
                        )
                    )
                    elseBlock = ifBlock.else
                    returnsOnAllPaths = returnsOnAllPaths && checkedBlock.returnsOnAllPaths
                case let .else(stmts):
                    let checkedBlock = try checkStmts(stmts, &context)
                    checkedElseBlock = checkedBlock.inner
                    returnsOnAllPaths = returnsOnAllPaths && checkedBlock.returnsOnAllPaths
                    elseBlock = nil
                case nil:
                    // No else block
                    returnsOnAllPaths = false
                    break
            }
        }

        return Analyzed(
            CheckedAST.IfStmt(
                ifBlock: ifBlock,
                elseIfBlocks: elseIfBlocks,
                elseBlock: checkedElseBlock
            ),
            returnsOnAllPaths: returnsOnAllPaths
        )
    }

    private func checkExpr(
        _ expr: WithSpan<Expr>, _ context: inout FnContext
    ) throws -> Typed<CheckedAST.Expr> {
        switch *expr {
            case let .stringLiteral(content):
                return Typed(.constant(content), String.type)
            case let .integerLiteral(value):
                return Typed(.constant(value), Int.type)
            case let .fnCall(fnCallExpr):
                let arguments = try fnCallExpr.arguments.map { expr in
                    try checkExpr(expr, &context)
                }
                let (id, signature) = try resolveFn(
                    fnCallExpr.ident,
                    arguments.map(\.type),
                    span: expr.span
                )
                return Typed(
                    .fnCall(CheckedAST.FnCallExpr(id: id, arguments: arguments)),
                    signature.returnType?.inner ?? .void
                )
            case let .ident(ident):
                guard let (index, local) = context.local(for: ident) else {
                    throw Diagnostic(error: "No such variable '\(ident)'", at: expr.span)
                }
                return Typed(.localVar(index), local.type)
            case let .structInit(structInit):
                let type = structInit.ident.map(Type.nominal)
                let typeIndex = try checkType(type)
                guard case let .struct(structIndex) = typeIndex else {
                    throw Diagnostic(
                        error:
                            "Struct initialization syntax can only be used for struct types, got '\(*structInit.ident)'",
                        at: structInit.ident.span
                    )
                }

                let structDecl = structDecls[structIndex]
                let structInitFieldIdents = structInit.fields.inner.map(\.inner.ident)
                let structDeclFieldIdents = structDecl.fields.map(\.inner.ident)
                guard structInitFieldIdents == structDeclFieldIdents else {
                    let diagnostics = diagnoseStructInitFieldMismatch(
                        *structInit.ident, structDeclFieldIdents, structInitFieldIdents, expr.span
                    )

                    // TODO: Emit as proper diagnostics instead of printing (once we can emit multple diagnostics)
                    for diagnostic in diagnostics {
                        print(diagnostic.description)
                    }

                    throw Diagnostic(error: "See above", at: nil)
                }

                let checkedFields = try structInit.fields.inner.map { field in
                    try checkExpr(field.inner.value, &context)
                }

                let expectedTypes = structDecl.fields.map(\.type.inner)
                let actualTypes = checkedFields.map(\.type)
                guard actualTypes == expectedTypes else {
                    let diagnostics = diagnoseStructInitFieldTypeMismatch(
                        *structInit.fields, expectedTypes, actualTypes
                    )

                    // TODO: Emit these properly once emitting multiple diagnostics is supported
                    for diagnostic in diagnostics {
                        print(diagnostic.description)
                    }

                    throw Diagnostic(error: "See above", at: nil)
                }

                return Typed(
                    .structInit(
                        CheckedAST.StructInitExpr(
                            structId: structIndex, fields: checkedFields
                        )
                    ),
                    *type
                )
            case let .unaryOp(unaryOpExpr):
                let operand = try checkExpr(unaryOpExpr.operand, &context)
                let (id, signature) = try resolveFn(
                    unaryOpExpr.op.map(\.token),
                    [operand.type],
                    span: expr.span
                )
                return Typed(
                    .fnCall(CheckedAST.FnCallExpr(id: id, arguments: [operand])),
                    signature.returnType?.inner ?? .void
                )
            case let .binaryOp(binaryOpExpr):
                let leftOperand = try checkExpr(binaryOpExpr.leftOperand, &context)
                let rightOperand = try checkExpr(binaryOpExpr.rightOperand, &context)
                let (id, signature) = try resolveFn(
                    binaryOpExpr.op.map(\.token),
                    [leftOperand.type, rightOperand.type],
                    span: expr.span
                )
                return Typed(
                    .fnCall(CheckedAST.FnCallExpr(id: id, arguments: [leftOperand, rightOperand])),
                    signature.returnType?.inner ?? .void
                )
            case let .parenthesizedExpr(inner):
                return try checkExpr(inner, &context)
        }
    }

    private func diagnoseStructInitFieldTypeMismatch(
        _ structInitFields: [WithSpan<StructInitField>],
        _ expectedTypes: [Type],
        _ actualTypes: [Type]
    ) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        let zipped = zip(structInitFields, zip(actualTypes, expectedTypes))

        for (field, (actualType, expectedType)) in zipped {
            guard actualType != expectedType else {
                continue
            }

            diagnostics.append(
                Diagnostic(
                    error:
                        "Expected expression of type '\(expectedType)' for field '\(*field.inner.ident)', got '\(actualType)'",
                    at: field.inner.value.span
                )
            )
        }

        return diagnostics
    }

    private func diagnoseStructInitFieldMismatch(
        _ structIdent: String,
        _ structDeclFieldIdents: [WithSpan<String>],
        _ structInitFieldIdents: [WithSpan<String>],
        _ structSpan: Span
    ) -> [Diagnostic] {
        var missingFields: [WithSpan<String>] = []
        var extraFields: [WithSpan<String>] = []
        for field in structDeclFieldIdents {
            if !structInitFieldIdents.contains(field) {
                missingFields.append(field)
            }
        }
        for field in structInitFieldIdents {
            if !structDeclFieldIdents.contains(field) {
                extraFields.append(field)
            }
        }

        var diagnostics: [Diagnostic] = []
        if !missingFields.isEmpty || !extraFields.isEmpty {
            for missingField in missingFields {
                diagnostics.append(
                    Diagnostic(
                        error:
                            "Missing field '\(*missingField)' in initialization of struct '\(structIdent)'",
                        at: structSpan
                    )
                )
            }
            for extraField in extraFields {
                diagnostics.append(
                    Diagnostic(
                        error:
                            "Unexpected field '\(*extraField)' in initialization of struct '\(structIdent)'",
                        at: extraField.span
                    )
                )
            }
        } else {
            for (initField, declField) in zip(
                structInitFieldIdents, structDeclFieldIdents)
            {
                if initField.inner != declField.inner {
                    diagnostics.append(
                        Diagnostic(
                            error:
                                "'\(declField.inner)' must preceed '\(initField.inner)' in initialization of '\(structIdent)'",
                            at: initField.span
                        )
                    )
                    break
                }
            }
            diagnostics.append(
                Diagnostic(
                    error:
                        "Type checker failure: failed to diagnose cause of mismatch between provided fields and declared fields",
                    at: structSpan
                )
            )
        }

        return diagnostics
    }

    private func resolveFn(
        _ ident: WithSpan<String>,
        _ argumentTypes: [Type],
        span: Span
    ) throws -> (CheckedAST.FnId, FnSignature) {
        guard
            let (id, signature) = fnTable.first(where: { (_, signature) in
                *signature.ident == *ident && signature.paramTypes.map(\.inner) == argumentTypes
            })
        else {
            let parameters = argumentTypes.map(\.description).joined(separator: ", ")
            let alternativesCount = fnTable.filter { *$0.1.ident == *ident }.count
            let additionalContext =
                if alternativesCount > 0 {
                    ". Found \(alternativesCount) function\(alternativesCount > 1 ? "s" : "") with the same name but incompatible parameter types"
                } else {
                    ""
                }
            throw Diagnostic(
                error: "No such function '\(*ident)' with parameters '(\(parameters))'"
                    + additionalContext,
                at: span
            )
        }

        return (id, signature)
    }

    private static func buildFnLookupTable(
        _ fnDecls: [WithSpan<FnDecl>],
        _ builtins: [BuiltinFn]
    ) throws -> [(CheckedAST.FnId, FnSignature)] {
        var table: [(CheckedAST.FnId, FnSignature)] = []

        for (i, fn) in builtins.enumerated() {
            let isDuplicate = table.contains { other in
                other.1.ident == fn.signature.ident && other.1.paramTypes == fn.signature.paramTypes
            }
            if isDuplicate {
                let paramTypes = fn.signature.paramTypes.map(\.inner.description)
                    .joined(separator: ", ")
                let returnType = fn.signature.returnType?.inner ?? .void
                throw Diagnostic(
                    error:
                        "Duplicate definition of builtin '\(fn.signature.ident)' with parameter types '(\(paramTypes)) -> \(returnType)'",
                    at: fn.signature.ident.span
                )
            }
            table.append((.builtin(index: i), fn.signature))
        }

        for (i, fn) in fnDecls.enumerated() {
            let span = fn.span
            let fn = *fn
            let isDuplicate = table.contains { other in
                other.1.ident == fn.ident && other.1.paramTypes == fn.signature.paramTypes
            }
            if isDuplicate {
                let paramTypes = fn.signature.paramTypes.map(\.inner.description)
                    .joined(separator: ", ")
                let returnType = fn.signature.returnType?.inner ?? .void
                throw Diagnostic(
                    error:
                        "Duplicate definition of '\(fn.ident)' with type '(\(paramTypes)) -> \(returnType)'",
                    at: span
                )
            }
            table.append((.userDefined(index: i), fn.signature))
        }

        return table
    }
}
