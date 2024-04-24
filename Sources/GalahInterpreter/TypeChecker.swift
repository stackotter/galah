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

    private struct TypeContext {
        var builtinTypes: [BuiltinType]
        var structs: [CheckedAST.Struct]

        let void: CheckedAST.TypeIndex
        let int: CheckedAST.TypeIndex
        let string: CheckedAST.TypeIndex

        let voidIdent: String
        let intIdent: String
        let stringIdent: String

        init(
            builtinTypes: [BuiltinType],
            structs: [CheckedAST.Struct]
        ) throws {
            self.builtinTypes = builtinTypes
            self.structs = structs

            voidIdent = "Void"
            void = try Self.builtin(named: voidIdent, from: builtinTypes)
            intIdent = "Int"
            int = try Self.builtin(named: intIdent, from: builtinTypes)
            stringIdent = "String"
            string = try Self.builtin(named: stringIdent, from: builtinTypes)
        }

        static func builtin(
            named name: String,
            from builtinTypes: [BuiltinType]
        ) throws -> CheckedAST.TypeIndex {
            guard let index = builtinTypes.firstIndex(where: { $0.ident == name }) else {
                throw Diagnostic(
                    error: "Expected to find builtin type named '\(name)'",
                    at: .builtin
                )
            }

            return .builtin(index)
        }

        func describe(_ typeIndex: CheckedAST.TypeIndex) -> String {
            switch typeIndex {
                case let .builtin(index):
                    builtinTypes[index].ident
                case let .struct(index):
                    structs[index].ident
            }
        }
    }

    private struct GlobalContext {
        var typeContext: TypeContext
        var fns: [(CheckedAST.FnId, CheckedAST.FnSignature)]

        init(
            typeContext: TypeContext,
            fns: [(CheckedAST.FnId, CheckedAST.FnSignature)]
        ) throws {
            self.typeContext = typeContext
            self.fns = fns
        }

        struct ResolvedFnCall {
            var id: CheckedAST.FnId
            var returnType: CheckedAST.TypeIndex
        }

        func resolveFnCall(
            _ ident: WithSpan<String>,
            _ argumentTypes: [CheckedAST.TypeIndex],
            span: Span
        ) throws -> ResolvedFnCall {
            guard
                let (id, signature) = fns.first(where: { (id, signature) in
                    signature.ident == *ident && signature.params.map(\.type) == argumentTypes
                })
            else {
                let parameters = argumentTypes.map(typeContext.describe).joined(separator: ", ")
                let alternativesCount = fns.filter { $0.1.ident == *ident }.count
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

            return ResolvedFnCall(
                id: id,
                returnType: signature.returnType
            )
        }
    }

    private struct FnContext {
        struct Local {
            var ident: String
            var type: CheckedAST.TypeIndex
        }

        typealias LocalIndex = Int

        var expectedReturnType: CheckedAST.TypeIndex

        /// The number of locals in the context.
        var localCount: Int {
            locals.count
        }

        private var locals: [Local]
        private var scopes: [[String: LocalIndex]]

        var globalContext: GlobalContext

        var typeContext: TypeContext {
            globalContext.typeContext
        }

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
        init(globalContext: GlobalContext, expectedReturnType: CheckedAST.TypeIndex) {
            self.globalContext = globalContext
            self.expectedReturnType = expectedReturnType
            locals = []
            scopes = [[:]]
            diagnostics = []
        }

        @discardableResult
        mutating func newLocal(_ ident: String, type: CheckedAST.TypeIndex) -> LocalIndex {
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

    private init(_ ast: AST, _ builtinTypes: [BuiltinType], _ builtinFns: [BuiltinFn]) throws {
        self.builtinTypes = builtinTypes
        self.builtinFns = builtinFns
        structDecls = ast.structDecls
        fnDecls = ast.fnDecls
    }

    private func check() throws -> WithDiagnostics<CheckedAST> {
        let structs = try checkStructs(structDecls)
        let typeContext = try TypeContext(builtinTypes: builtinTypes, structs: structs)

        let checkedBuiltinFnSignatures = try checkBuiltinFnSignatures(
            builtinFns,
            typeContext: typeContext
        )
        let checkedFnDeclSignatures = try checkFnDeclSignatures(
            fnDecls,
            checkedBuiltinFns: checkedBuiltinFnSignatures,
            typeContext: typeContext
        )

        let globalContext = try GlobalContext(
            typeContext: typeContext,
            fns: checkedBuiltinFnSignatures + checkedFnDeclSignatures
        )

        let fns: WithDiagnostics<[CheckedAST.Fn]> = try zip(fnDecls, checkedFnDeclSignatures)
            .map { (fnDecl, signature) in
                try checkFn(fnDecl, signature.1, globalContext)
            }
            .collect()

        return fns.map { fns in
            CheckedAST(
                builtinTypes: builtinTypes,
                structs: structs,
                builtinFns: builtinFns,
                fns: fns
            )
        }
    }

    private func checkBuiltinFnSignatures(
        _ builtinFns: [BuiltinFn],
        typeContext: TypeContext
    ) throws -> [(id: CheckedAST.FnId, signature: CheckedAST.FnSignature)] {
        var checkedBuiltinFnSignatures: [(CheckedAST.FnId, CheckedAST.FnSignature)] = []
        for (index, builtinFn) in builtinFns.enumerated() {
            let checkedFn = try checkBuiltinFn(builtinFn, typeContext)

            guard
                !checkedBuiltinFnSignatures.contains(where: {
                    $0.1.ident == *builtinFn.signature.ident && $0.1.params == checkedFn.params
                })
            else {
                let parameterTypes = checkedFn.params.map(\.type).map(typeContext.describe)
                    .joined(separator: ", ")
                throw Diagnostic(
                    error:
                        "Duplicate definition of function '\(*builtinFn.signature.ident)' with parameter types '(\(parameterTypes))'",
                    at: builtinFn.signature.ident.span
                )
            }

            checkedBuiltinFnSignatures.append(
                (
                    .builtin(index: index),
                    checkedFn
                )
            )
        }
        return checkedBuiltinFnSignatures
    }

    private func checkFnDeclSignatures(
        _ fnDecls: [WithSpan<FnDecl>],
        checkedBuiltinFns: [(id: CheckedAST.FnId, signature: CheckedAST.FnSignature)],
        typeContext: TypeContext
    ) throws -> [(id: CheckedAST.FnId, signature: CheckedAST.FnSignature)] {
        var checkedFnDeclSignatures: [(CheckedAST.FnId, CheckedAST.FnSignature)] = []
        for (index, fnDecl) in fnDecls.enumerated() {
            let checkedFn = try checkFnSignature(fnDecl, typeContext)
            guard
                !(checkedBuiltinFns + checkedFnDeclSignatures).contains(where: {
                    $0.1.ident == *fnDecl.signature.ident && $0.1.params == checkedFn.params
                })
            else {
                let parameterTypes = checkedFn.params.map(\.type).map(typeContext.describe)
                    .joined(separator: ", ")
                throw Diagnostic(
                    error:
                        "Duplicate definition of function '\(*fnDecl.signature.ident)' with parameter types '(\(parameterTypes))'",
                    at: fnDecl.signature.ident.span
                )
            }
            checkedFnDeclSignatures.append(
                (
                    .userDefined(index: index),
                    checkedFn
                )
            )
        }

        return checkedFnDeclSignatures
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

    private func checkBuiltinFn(
        _ builtinFn: BuiltinFn,
        _ typeContext: TypeContext
    ) throws -> CheckedAST.FnSignature {
        CheckedAST.FnSignature(
            ident: *builtinFn.signature.ident,
            params: try builtinFn.signature.params.map { param in
                CheckedAST.Param(
                    ident: *param.ident,
                    type: try checkType(param.type)
                )
            },
            returnType: try builtinFn.signature.returnType.map(checkType)
                ?? typeContext.void
        )
    }

    private func checkFnSignature(
        _ fn: WithSpan<FnDecl>,
        _ typeContext: TypeContext
    ) throws -> CheckedAST.FnSignature {
        var seenIdents: [String] = []
        let params = try fn.signature.params.map { param in
            guard !seenIdents.contains(*param.ident) else {
                throw Diagnostic(
                    error: "Duplicate definition of parameter '\(*param.ident)'", at: param.span)
            }
            seenIdents.append(*param.ident)
            return CheckedAST.Param(
                ident: *param.ident,
                type: try checkType(param.type)
            )
        }

        let returnType = try fn.signature.returnType.map(checkType) ?? typeContext.void

        return CheckedAST.FnSignature(
            ident: *fn.signature.ident,
            params: params,
            returnType: returnType
        )
    }

    private func checkFn(
        _ fn: WithSpan<FnDecl>,
        _ checkedSignature: CheckedAST.FnSignature,
        _ globalContext: GlobalContext

    ) throws -> WithDiagnostics<CheckedAST.Fn> {
        let span = fn.span
        let fn = *fn

        var context = FnContext(
            globalContext: globalContext,
            expectedReturnType: checkedSignature.returnType
        )
        for param in checkedSignature.params {
            context.newLocal(param.ident, type: param.type)
        }

        let analyzedStmts = try checkStmts(fn.stmts, &context)
        let returnType = fn.signature.returnType?.inner ?? .void
        guard returnType == .void || analyzedStmts.returnsOnAllPaths else {
            // TODO: Attach the diagnostic to the last statement in each offending path
            throw Diagnostic(error: "Non-void function must return on all paths", at: span)
        }

        return WithDiagnostics(
            CheckedAST.Fn(
                signature: checkedSignature,
                localCount: context.localCount,
                stmts: analyzedStmts.inner
            ),
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
                let type = checkedExpr?.type ?? context.globalContext.typeContext.void
                guard type == context.expectedReturnType else {
                    if let expr, let checkedExpr {
                        let actualType = context.typeContext.describe(checkedExpr.type)
                        throw Diagnostic(
                            error:
                                "Function expected to return '\(context.expectedReturnType)', got expression of type '\(actualType)'",
                            at: expr.span
                        )
                    } else {
                        throw Diagnostic(
                            error:
                                "Function expected to return '\(context.expectedReturnType)', got '\(context.typeContext.voidIdent)'",
                            at: stmt.span
                        )
                    }
                }
                return Analyzed(.return(checkedExpr), returnsOnAllPaths: true)
            case let .let(varDecl):
                let typeAnnotation = try varDecl.type.map(checkType)

                let checkedExpr = try checkExpr(varDecl.value, &context)

                if let typeAnnotation = typeAnnotation, checkedExpr.type != typeAnnotation {
                    let actualType = context.typeContext.describe(checkedExpr.type)
                    throw Diagnostic(
                        error:
                            "Let binding '\(*varDecl.ident)' expected expression of type '\(context.typeContext.describe(typeAnnotation))', got expression of type '\(actualType)'",
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
        guard condition.type == context.typeContext.int else {
            throw Diagnostic(
                error:
                    "If statement condition must be of type '\(context.typeContext.intIdent)', got \(condition.type)",
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
                    guard condition.type == context.typeContext.int else {
                        throw Diagnostic(
                            error:
                                "If statement condition must be of type '\(context.typeContext.intIdent)', got \(condition.type)",
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
                return Typed(.constant(content), context.typeContext.string)
            case let .integerLiteral(value):
                return Typed(.constant(value), context.typeContext.int)
            case let .fnCall(fnCallExpr):
                let arguments = try fnCallExpr.arguments.map { expr in
                    try checkExpr(expr, &context)
                }
                let resolvedFn = try context.globalContext.resolveFnCall(
                    fnCallExpr.ident,
                    arguments.map(\.type),
                    span: expr.span
                )
                return Typed(
                    .fnCall(CheckedAST.FnCallExpr(id: resolvedFn.id, arguments: arguments)),
                    resolvedFn.returnType
                )
            case let .ident(ident):
                guard let (index, local) = context.local(for: ident) else {
                    throw Diagnostic(error: "No such variable '\(ident)'", at: expr.span)
                }
                return Typed(.localVar(index), local.type)
            case let .unaryOp(unaryOpExpr):
                let operand = try checkExpr(unaryOpExpr.operand, &context)
                let resolvedFn = try context.globalContext.resolveFnCall(
                    unaryOpExpr.op.map(\.token),
                    [operand.type],
                    span: expr.span
                )
                return Typed(
                    .fnCall(CheckedAST.FnCallExpr(id: resolvedFn.id, arguments: [operand])),
                    resolvedFn.returnType
                )
            case let .binaryOp(binaryOpExpr):
                let leftOperand = try checkExpr(binaryOpExpr.leftOperand, &context)
                let rightOperand = try checkExpr(binaryOpExpr.rightOperand, &context)
                let resolvedFn = try context.globalContext.resolveFnCall(
                    binaryOpExpr.op.map(\.token),
                    [leftOperand.type, rightOperand.type],
                    span: expr.span
                )
                return Typed(
                    .fnCall(
                        CheckedAST.FnCallExpr(
                            id: resolvedFn.id, arguments: [leftOperand, rightOperand]
                        )
                    ),
                    resolvedFn.returnType
                )
            case let .parenthesizedExpr(inner):
                return try checkExpr(inner, &context)
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

                let structDecl = context.typeContext.structs[structIndex]
                let structInitFieldIdents = structInit.fields.inner.map(\.inner.ident)
                let structDeclFieldIdents = structDecl.fields.map(\.ident)
                guard structInitFieldIdents.map(\.inner) == structDeclFieldIdents else {
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

                let expectedTypes = structDecl.fields.map(\.type)
                let actualTypes = checkedFields.map(\.type)
                guard actualTypes == expectedTypes else {
                    let diagnostics = diagnoseStructInitFieldTypeMismatch(
                        *structInit.fields, expectedTypes, actualTypes,
                        typeContext: context.typeContext
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
                    typeIndex
                )
            case let .memberAccess(memberAccess):
                let base = try checkExpr(memberAccess.base, &context)
                guard case let .struct(structIndex) = base.type else {
                    throw Diagnostic(
                        error:
                            "Member accesses cannot be performed on builtin types, got type '\(context.typeContext.describe(base.type))'",
                        at: expr.span
                    )
                }

                let structDecl = context.typeContext.structs[structIndex]
                guard
                    let fieldIndex = structDecl.fields.firstIndex(where: {
                        $0.ident == *memberAccess.memberIdent
                    })
                else {
                    // TODO: Should this be attached to the member ident or the whole expression?
                    throw Diagnostic(
                        error:
                            "Value of type '\(structDecl.ident)' has no such field '\(*memberAccess.memberIdent)'",
                        at: expr.span
                    )
                }
                let field = structDecl.fields[fieldIndex]

                return Typed(
                    .fieldAccess(
                        CheckedAST.FieldAccessExpr(
                            base: base.map(CheckedAST.Boxed.init),
                            fieldIndex: fieldIndex
                        )
                    ),
                    field.type
                )
        }
    }

    private func diagnoseStructInitFieldTypeMismatch(
        _ structInitFields: [WithSpan<StructInitField>],
        _ expectedTypes: [CheckedAST.TypeIndex],
        _ actualTypes: [CheckedAST.TypeIndex],
        typeContext: TypeContext
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
                        "Expected expression of type '\(typeContext.describe(expectedType))' for field '\(*field.inner.ident)', got '\(typeContext.describe(actualType))'",
                    at: field.inner.value.span
                )
            )
        }

        return diagnostics
    }

    private func diagnoseStructInitFieldMismatch(
        _ structIdent: String,
        _ structDeclFieldIdents: [String],
        _ structInitFieldIdents: [WithSpan<String>],
        _ structSpan: Span
    ) -> [Diagnostic] {
        var missingFields: [String] = []
        var extraFields: [WithSpan<String>] = []
        for field in structDeclFieldIdents {
            if !structInitFieldIdents.map(\.inner).contains(field) {
                missingFields.append(field)
            }
        }
        for field in structInitFieldIdents {
            if !structDeclFieldIdents.contains(field.inner) {
                extraFields.append(field)
            }
        }

        var diagnostics: [Diagnostic] = []
        if !missingFields.isEmpty || !extraFields.isEmpty {
            for missingField in missingFields {
                diagnostics.append(
                    Diagnostic(
                        error:
                            "Missing field '\(missingField)' in initialization of struct '\(structIdent)'",
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
                if initField.inner != declField {
                    diagnostics.append(
                        Diagnostic(
                            error:
                                "'\(declField)' must preceed '\(initField.inner)' in initialization of '\(structIdent)'",
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
}
