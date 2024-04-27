import UtilityMacros

public struct TypeChecker {
    public static func check(
        _ ast: AST,
        _ builtinTypes: [BuiltinType],
        _ builtinFns: [BuiltinFn]
    ) -> Result<WithDiagnostics<CheckedAST>, [Diagnostic]> {
        TypeChecker(ast, builtinTypes, builtinFns).check()
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

        static func create(
            builtinTypes: [BuiltinType],
            structs: [CheckedAST.Struct]
        ) -> Result<TypeContext, [Diagnostic]> {
            let voidIdent = "Void"
            let intIdent = "Int"
            let stringIdent = "String"

            return #result {
                (
                    void: CheckedAST.TypeIndex,
                    int: CheckedAST.TypeIndex,
                    string: CheckedAST.TypeIndex
                ) in
                void <- Self.builtin(named: voidIdent, from: builtinTypes)
                int <- Self.builtin(named: intIdent, from: builtinTypes)
                string <- Self.builtin(named: stringIdent, from: builtinTypes)
                return Result<_, [Diagnostic]>.success(
                    TypeContext(
                        builtinTypes: builtinTypes,
                        structs: structs,
                        void: void,
                        int: int,
                        string: string,
                        voidIdent: voidIdent,
                        intIdent: intIdent,
                        stringIdent: stringIdent
                    )
                )
            }
        }

        static func builtin(
            named name: String,
            from builtinTypes: [BuiltinType]
        ) -> Result<CheckedAST.TypeIndex, [Diagnostic]> {
            guard let index = builtinTypes.firstIndex(where: { $0.ident == name }) else {
                return .failure([
                    Diagnostic(
                        error: "Expected to find builtin type named '\(name)'",
                        at: .builtin
                    )
                ])
            }

            return .success(.builtin(index))
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
        ) {
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
        ) -> Result<ResolvedFnCall, [Diagnostic]> {
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
                return .failure([
                    Diagnostic(
                        error: "No such function '\(*ident)' with parameters '(\(parameters))'"
                            + additionalContext,
                        at: span
                    )
                ])
            }

            return .success(
                ResolvedFnCall(
                    id: id,
                    returnType: signature.returnType
                )
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

    private init(_ ast: AST, _ builtinTypes: [BuiltinType], _ builtinFns: [BuiltinFn]) {
        self.builtinTypes = builtinTypes
        self.builtinFns = builtinFns
        structDecls = ast.structDecls
        fnDecls = ast.fnDecls
    }

    private func check() -> Result<WithDiagnostics<CheckedAST>, [Diagnostic]> {
        #result {
            (
                structs: [CheckedAST.Struct], typeContext: TypeContext,
                checkedBuiltinFnSignatures: [(
                    id: CheckedAST.FnId, signature: CheckedAST.FnSignature
                )],
                checkedFnDeclSignatures: [(id: CheckedAST.FnId, signature: CheckedAST.FnSignature)],
                fns: WithDiagnostics<[CheckedAST.Fn]>
            ) in
            structs <- checkStructs(structDecls)
            typeContext <- TypeContext.create(builtinTypes: builtinTypes, structs: structs)

            checkedBuiltinFnSignatures
                <- checkBuiltinFnSignatures(
                    builtinFns,
                    typeContext: typeContext
                )
            checkedFnDeclSignatures
                <- checkFnDeclSignatures(
                    fnDecls,
                    checkedBuiltinFns: checkedBuiltinFnSignatures,
                    typeContext: typeContext
                )

            let globalContext = GlobalContext(
                typeContext: typeContext,
                fns: checkedBuiltinFnSignatures + checkedFnDeclSignatures
            )

            fns
                <- collect(
                    zip(fnDecls, checkedFnDeclSignatures)
                        .map { (fnDecl, signature) in
                            checkFn(fnDecl, signature.1, globalContext)
                        }
                )
                .map({ withDiagnostics in
                    withDiagnostics.collect()
                })

            return .success(
                fns.map { fns in
                    CheckedAST(
                        builtinTypes: builtinTypes,
                        structs: structs,
                        builtinFns: builtinFns,
                        fns: fns
                    )
                }
            )
        }
    }

    private func checkBuiltinFnSignatures(
        _ builtinFns: [BuiltinFn],
        typeContext: TypeContext
    ) -> Result<[(id: CheckedAST.FnId, signature: CheckedAST.FnSignature)], [Diagnostic]> {
        var checkedBuiltinFnSignatures: [(id: CheckedAST.FnId, signature: CheckedAST.FnSignature)] =
            []
        return collect(
            builtinFns.enumerated().map { (index, builtinFn) in
                #result { (checkedFn: CheckedAST.FnSignature) in
                    checkedFn <- checkBuiltinFn(builtinFn, typeContext)

                    guard
                        !checkedBuiltinFnSignatures.contains(where: {
                            $0.1.ident == *builtinFn.signature.ident
                                && $0.1.params == checkedFn.params
                        })
                    else {
                        let parameterTypes = checkedFn.params.map(\.type).map(typeContext.describe)
                            .joined(separator: ", ")
                        return .failure([
                            Diagnostic(
                                error:
                                    "Duplicate definition of function '\(*builtinFn.signature.ident)' with parameter types '(\(parameterTypes))'",
                                at: builtinFn.signature.ident.span
                            )
                        ])
                    }

                    let result = (
                        CheckedAST.FnId.builtin(index: index),
                        checkedFn
                    )
                    checkedBuiltinFnSignatures.append(result)
                    return .success(result)
                }
            }
        )
    }

    private func checkFnDeclSignatures(
        _ fnDecls: [WithSpan<FnDecl>],
        checkedBuiltinFns: [(id: CheckedAST.FnId, signature: CheckedAST.FnSignature)],
        typeContext: TypeContext
    ) -> Result<[(id: CheckedAST.FnId, signature: CheckedAST.FnSignature)], [Diagnostic]> {
        var checkedFnDeclSignatures: [(id: CheckedAST.FnId, signature: CheckedAST.FnSignature)] = []
        return collect(
            fnDecls.enumerated().map { (index, fnDecl) in
                #result { (checkedFn: CheckedAST.FnSignature) in
                    checkedFn <- checkFnSignature(fnDecl, typeContext)
                    guard
                        !(checkedBuiltinFns + checkedFnDeclSignatures).contains(where: {
                            (_, signature) in
                            return signature.ident == checkedFn.ident
                                && signature.params == checkedFn.params
                        })
                    else {
                        let parameterTypes = checkedFn.params.map(\.type).map(typeContext.describe)
                            .joined(separator: ", ")
                        return .failure([
                            Diagnostic(
                                error:
                                    "Duplicate definition of function '\(*fnDecl.inner.signature.inner.ident)' with parameter types '(\(parameterTypes))'",
                                at: fnDecl.inner.signature.inner.ident.span
                            )
                        ])
                    }
                    let result = (
                        CheckedAST.FnId.userDefined(index: index),
                        checkedFn
                    )
                    checkedFnDeclSignatures.append(result)
                    return .success(result)
                }
            }
        )
    }

    private func checkStructs(
        _ structDecls: [WithSpan<StructDecl>]
    ) -> Result<[CheckedAST.Struct], [Diagnostic]> {
        var seenStructs: [String] = []
        return #result { (structs: [CheckedAST.Struct]) in
            structs
                <- collect(
                    structDecls.map { structDecl in
                        #result {
                            (fields: [CheckedAST.Field]) -> Result<CheckedAST.Struct, [Diagnostic]>
                            in
                            guard
                                !builtinTypes.contains(where: {
                                    $0.ident == *structDecl.inner.ident
                                })
                            else {
                                return .failure([
                                    Diagnostic(
                                        error:
                                            "Duplicate definition of builtin type '\(*structDecl.inner.ident)'",
                                        at: structDecl.inner.ident.span
                                    )
                                ])
                            }

                            // TODO: Include span of the original struct once errors can have multiple diagnostics
                            guard
                                !seenStructs.contains(structDecl.inner.ident.inner)
                            else {
                                return .failure([
                                    Diagnostic(
                                        error:
                                            "Duplicate definition of struct '\(*structDecl.inner.ident)'",
                                        at: structDecl.inner.ident.span
                                    )
                                ])
                            }

                            var seenFields: [String] = []
                            fields
                                <- collect(
                                    structDecl.inner.fields.map {
                                        (field: WithSpan<Field>) -> Result<
                                            CheckedAST.Field, [Diagnostic]
                                        >
                                        in
                                        #result { (checkedType: CheckedAST.TypeIndex) in
                                            guard
                                                !seenFields.contains(*field.inner.ident)
                                            else {
                                                return .failure([
                                                    Diagnostic(
                                                        error:
                                                            "Duplicate definition of field '\(*structDecl.inner.ident).\(*field.inner.ident)'",
                                                        at: field.span
                                                    )
                                                ])
                                            }
                                            checkedType <- checkType(field.inner.type)
                                            seenFields.append(*field.inner.ident)
                                            return .success(
                                                CheckedAST.Field(
                                                    ident: *field.inner.ident, type: checkedType
                                                )
                                            )
                                        }
                                    }
                                )

                            seenStructs.append(*structDecl.inner.ident)
                            return .success(
                                CheckedAST.Struct(ident: *structDecl.inner.ident, fields: fields)
                            )
                        }
                    })

            // Check for self-referential structs
            let graph = TypeFieldGraph(builtinTypes: builtinTypes, structs: structs)
            let cycles = graph.cycles()
            guard cycles.isEmpty else {
                return .failure(diagnoseCycles(graph, cycles))
            }

            return .success(structs)
        }
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
                            "Struct '\(structDecl.inner.ident.inner)' references itself via '\(structDecl.inner.ident.inner).\(fieldAccesses)'",
                        at: structDecl.span
                    )
                )
                diagnosedTypes.append(structDecl.inner.ident.inner)
            }
        }

        return diagnostics
    }

    private func checkBuiltinFn(
        _ builtinFn: BuiltinFn,
        _ typeContext: TypeContext
    ) -> Result<CheckedAST.FnSignature, [Diagnostic]> {
        #result { (params: [CheckedAST.Param], returnType: CheckedAST.TypeIndex?) in
            params
                <- collect(
                    builtinFn.signature.params.map {
                        (param: WithSpan<Param>) -> Result<CheckedAST.Param, [Diagnostic]> in
                        checkType(param.inner.type).map { checkedType in
                            CheckedAST.Param(
                                ident: param.inner.ident.inner,
                                type: checkedType
                            )
                        }
                    }
                )
            returnType <- invert(builtinFn.signature.returnType.map(checkType))
            return Result<_, [Diagnostic]>.success(
                CheckedAST.FnSignature(
                    ident: *builtinFn.signature.ident,
                    params: params,
                    returnType: returnType
                        ?? typeContext.void
                )
            )
        }
    }

    private func checkFnSignature(
        _ fn: WithSpan<FnDecl>,
        _ typeContext: TypeContext
    ) -> Result<CheckedAST.FnSignature, [Diagnostic]> {
        #result { (params: [CheckedAST.Param], returnType: CheckedAST.TypeIndex?) in
            var seenIdents: [String] = []
            params
                <- collect(
                    fn.inner.signature.inner.params.map { param in
                        #result {
                            (checkedType: CheckedAST.TypeIndex) -> Result<
                                CheckedAST.Param, [Diagnostic]
                            > in
                            guard !seenIdents.contains(*param.inner.ident) else {
                                return .failure([
                                    Diagnostic(
                                        error:
                                            "Duplicate definition of parameter '\(*param.inner.ident)'",
                                        at: param.span
                                    )
                                ])
                            }
                            seenIdents.append(*param.inner.ident)
                            checkedType <- checkType(param.inner.type)
                            return .success(
                                CheckedAST.Param(
                                    ident: *param.inner.ident,
                                    type: checkedType
                                )
                            )
                        }
                    })

            returnType <- invert(fn.inner.signature.inner.returnType.map(checkType))

            return .success(
                CheckedAST.FnSignature(
                    ident: *fn.inner.signature.inner.ident,
                    params: params,
                    returnType: returnType ?? typeContext.void
                )
            )
        }
    }

    private func checkFn(
        _ fn: WithSpan<FnDecl>,
        _ checkedSignature: CheckedAST.FnSignature,
        _ globalContext: GlobalContext
    ) -> Result<WithDiagnostics<CheckedAST.Fn>, [Diagnostic]> {
        #result { (analyzedStmts: Analyzed<[CheckedAST.Stmt]>) in
            let span = fn.span
            let fn = *fn

            var context = FnContext(
                globalContext: globalContext,
                expectedReturnType: checkedSignature.returnType
            )
            for param in checkedSignature.params {
                context.newLocal(param.ident, type: param.type)
            }

            analyzedStmts <- checkStmts(fn.stmts, &context)
            let returnType = fn.signature.inner.returnType?.inner ?? .void
            guard returnType == .void || analyzedStmts.returnsOnAllPaths else {
                // TODO: Attach the diagnostic to the last statement in each offending path
                return .failure([
                    Diagnostic(error: "Non-void function must return on all paths", at: span)
                ])
            }

            return .success(
                WithDiagnostics(
                    CheckedAST.Fn(
                        signature: checkedSignature,
                        localCount: context.localCount,
                        stmts: analyzedStmts.inner
                    ),
                    context.diagnostics
                )
            )
        }
    }

    @discardableResult
    private func checkType(_ type: WithSpan<Type>) -> Result<CheckedAST.TypeIndex, [Diagnostic]> {
        let typeName = type.inner.description
        if let builtinIndex = builtinTypes.firstIndex(where: { $0.ident == typeName }) {
            return .success(.builtin(builtinIndex))
        } else if let structIndex = structDecls.firstIndex(where: { *$0.inner.ident == typeName }) {
            return .success(.struct(structIndex))
        } else {
            return .failure([Diagnostic(error: "No such type '\(typeName)'", at: type.span)])
        }
    }

    private func checkStmts(
        _ stmts: [WithSpan<Stmt>],
        _ context: inout FnContext
    ) -> Result<Analyzed<[CheckedAST.Stmt]>, [Diagnostic]> {
        #result { (analyzedStmts: [Analyzed<CheckedAST.Stmt>]) in
            context.pushScope()
            analyzedStmts
                <- collect(
                    stmts.map { stmt in
                        checkStmt(stmt, &context)
                    }
                )
            context.popScope()

            let lastReachableIndex = analyzedStmts.firstIndex(where: \.returnsOnAllPaths)
            if let lastReachableIndex, lastReachableIndex < stmts.count - 1 {
                context.diagnose(
                    Diagnostic(
                        warning: "warning: Unreachable statements",
                        at: stmts[lastReachableIndex + 1].span
                    )
                )
            }
            return .success(
                Analyzed(
                    analyzedStmts[...(lastReachableIndex ?? analyzedStmts.count - 1)].map(\.inner),
                    returnsOnAllPaths: analyzedStmts.contains(where: \.returnsOnAllPaths)
                )
            )
        }
    }

    private func checkStmt(
        _ stmt: WithSpan<Stmt>,
        _ context: inout FnContext
    ) -> Result<Analyzed<CheckedAST.Stmt>, [Diagnostic]> {
        switch *stmt {
            case let .if(ifStmt):
                return checkIfStmt(ifStmt, &context).map { analyzedIfStmt in
                    analyzedIfStmt.map(CheckedAST.Stmt.if)
                }
            case let .return(expr):
                return #result { (checkedExpr: Typed<CheckedAST.Expr>?) in
                    checkedExpr <- invert(expr.map { checkExpr($0, &context) })
                    let type = checkedExpr?.type ?? context.globalContext.typeContext.void
                    guard type == context.expectedReturnType else {
                        if let expr, let checkedExpr {
                            let actualType = context.typeContext.describe(checkedExpr.type)
                            return .failure([
                                Diagnostic(
                                    error:
                                        "Function expected to return '\(context.expectedReturnType)', got expression of type '\(actualType)'",
                                    at: expr.span
                                )
                            ])
                        } else {
                            return .failure([
                                Diagnostic(
                                    error:
                                        "Function expected to return '\(context.expectedReturnType)', got '\(context.typeContext.voidIdent)'",
                                    at: stmt.span
                                )
                            ])
                        }
                    }
                    return .success(Analyzed(.return(checkedExpr), returnsOnAllPaths: true))
                }
            case let .let(varDecl):
                return #result {
                    (
                        typeAnnotation: CheckedAST.TypeIndex?,
                        checkedExpr: CheckedAST.Typed<CheckedAST.Expr>
                    ) in
                    typeAnnotation <- invert(varDecl.type.map(checkType))

                    checkedExpr <- checkExpr(varDecl.value, &context)

                    if let typeAnnotation = typeAnnotation, checkedExpr.type != typeAnnotation {
                        let actualType = context.typeContext.describe(checkedExpr.type)
                        return .failure([
                            Diagnostic(
                                error:
                                    "Let binding '\(*varDecl.ident)' expected expression of type '\(context.typeContext.describe(typeAnnotation))', got expression of type '\(actualType)'",
                                at: varDecl.value.span
                            )
                        ])
                    }

                    // TODO: Do we allow shadowing within the same scope level? (it should be as easy as just removing this check)
                    if context.localInInnermostScope(for: *varDecl.ident) != nil {
                        return .failure([
                            Diagnostic(
                                error:
                                    "Duplicate definition of '\(varDecl.ident)' within current scope",
                                at: varDecl.ident.span
                            )
                        ])
                    }

                    let index = context.newLocal(*varDecl.ident, type: checkedExpr.type)
                    return .success(
                        Analyzed(
                            .let(CheckedAST.VarDecl(localIndex: index, value: checkedExpr)),
                            returnsOnAllPaths: false
                        )
                    )
                }
            case let .expr(expr):
                return #result { (checkedExpr: CheckedAST.Typed<CheckedAST.Expr>) in
                    checkedExpr <- checkExpr(WithSpan(expr, stmt.span), &context)
                    return .success(
                        Analyzed(
                            .expr(checkedExpr),
                            returnsOnAllPaths: false
                        )
                    )
                }
        }
    }

    private func checkIfStmt(
        _ ifStmt: IfStmt,
        _ context: inout FnContext
    ) -> Result<Analyzed<CheckedAST.IfStmt>, [Diagnostic]> {
        return #result {
            (
                results: (
                    condition: CheckedAST.Typed<CheckedAST.Expr>,
                    checkedIfBlockStmts: Analyzed<[CheckedAST.Stmt]>,
                    checkedElseIfBlocks: [Analyzed<CheckedAST.IfBlock>],
                    checkedElseBlockStmts: Analyzed<[CheckedAST.Stmt]>?
                )
            ) in
            let elseBlocks = ifStmt.elseBlocks
            results
                <- collectResults(
                    checkExpr(ifStmt.condition, &context),

                    checkStmts(ifStmt.ifBlock, &context),

                    collect(
                        elseBlocks.elseIfBlocks.map { elseIfBlock in
                            #result {
                                (
                                    condition: CheckedAST.Typed<CheckedAST.Expr>,
                                    checkedBlock: Analyzed<[CheckedAST.Stmt]>
                                ) -> Result<Analyzed<CheckedAST.IfBlock>, [Diagnostic]> in
                                condition <- checkExpr(elseIfBlock.condition, &context)
                                guard condition.type == context.typeContext.int else {
                                    return .failure([
                                        Diagnostic(
                                            error:
                                                "If statement condition must be of type '\(context.typeContext.intIdent)', got \(context.typeContext.describe(condition.type))",
                                            at: elseIfBlock.condition.span
                                        )
                                    ])
                                }
                                checkedBlock <- checkStmts(elseIfBlock.stmts, &context)
                                return .success(
                                    checkedBlock.map { checkedBlock in
                                        CheckedAST.IfBlock(
                                            condition: condition.inner,
                                            block: checkedBlock
                                        )
                                    }
                                )
                            }
                        }
                    ),

                    invert(elseBlocks.elseBlock.map { checkStmts($0, &context) }))

            let (condition, checkedIfBlockStmts, checkedElseIfBlocks, checkedElseBlockStmts) =
                results

            guard condition.type == context.typeContext.int else {
                return .failure([
                    Diagnostic(
                        error:
                            "If statement condition must be of type '\(context.typeContext.intIdent)', got \(condition.type)",
                        at: ifStmt.condition.span
                    )
                ])
            }

            let ifBlock = CheckedAST.IfBlock(
                condition: condition.inner,
                block: checkedIfBlockStmts.inner
            )

            let checkedElseBlock: [CheckedAST.Stmt]? = checkedElseBlockStmts?.inner
            let returnsOnAllPaths =
                checkedIfBlockStmts.returnsOnAllPaths
                && checkedElseIfBlocks.allSatisfy(\.returnsOnAllPaths)
                && checkedElseBlockStmts?.returnsOnAllPaths == true

            return .success(
                Analyzed(
                    CheckedAST.IfStmt(
                        ifBlock: ifBlock,
                        elseIfBlocks: checkedElseIfBlocks.map(\.inner),
                        elseBlock: checkedElseBlock
                    ),
                    returnsOnAllPaths: returnsOnAllPaths
                )
            )
        }
    }

    private func checkExpr(
        _ expr: WithSpan<Expr>, _ context: inout FnContext
    ) -> Result<Typed<CheckedAST.Expr>, [Diagnostic]> {
        #result { () in
            switch *expr {
                case let .stringLiteral(content):
                    return .success(Typed(.constant(content), context.typeContext.string))
                case let .integerLiteral(value):
                    return .success(Typed(.constant(value), context.typeContext.int))
                case let .fnCall(fnCallExpr):
                    return #result {
                        (
                            arguments: [CheckedAST.Typed<CheckedAST.Expr>],
                            resolvedFn: GlobalContext.ResolvedFnCall
                        ) in
                        arguments
                            <- collect(
                                fnCallExpr.arguments.map { expr in
                                    checkExpr(expr, &context)
                                }
                            )
                        resolvedFn
                            <- context.globalContext.resolveFnCall(
                                fnCallExpr.ident,
                                arguments.map(\.type),
                                span: expr.span
                            )
                        return .success(
                            Typed(
                                .fnCall(
                                    CheckedAST.FnCallExpr(id: resolvedFn.id, arguments: arguments)),
                                resolvedFn.returnType
                            )
                        )
                    }
                case let .ident(ident):
                    guard let (index, local) = context.local(for: ident) else {
                        return .failure([
                            Diagnostic(error: "No such variable '\(ident)'", at: expr.span)
                        ])
                    }
                    return .success(Typed(.localVar(index), local.type))
                case let .unaryOp(unaryOpExpr):
                    return #result {
                        (
                            operand: CheckedAST.Typed<CheckedAST.Expr>,
                            resolvedFn: GlobalContext.ResolvedFnCall
                        ) in
                        operand <- checkExpr(unaryOpExpr.operand, &context)
                        resolvedFn
                            <- context.globalContext.resolveFnCall(
                                unaryOpExpr.op.map(\.token),
                                [operand.type],
                                span: expr.span
                            )
                        return .success(
                            Typed(
                                .fnCall(
                                    CheckedAST.FnCallExpr(id: resolvedFn.id, arguments: [operand])),
                                resolvedFn.returnType
                            )
                        )
                    }
                case let .binaryOp(binaryOpExpr):
                    return #result {
                        (
                            leftOperand: CheckedAST.Typed<CheckedAST.Expr>,
                            rightOperand: CheckedAST.Typed<CheckedAST.Expr>,
                            resolvedFn: GlobalContext.ResolvedFnCall
                        ) in
                        leftOperand <- checkExpr(binaryOpExpr.leftOperand, &context)
                        rightOperand <- checkExpr(binaryOpExpr.rightOperand, &context)
                        resolvedFn
                            <- context.globalContext.resolveFnCall(
                                binaryOpExpr.op.map(\.token),
                                [leftOperand.type, rightOperand.type],
                                span: expr.span
                            )
                        return .success(
                            Typed(
                                .fnCall(
                                    CheckedAST.FnCallExpr(
                                        id: resolvedFn.id, arguments: [leftOperand, rightOperand]
                                    )
                                ),
                                resolvedFn.returnType
                            )
                        )
                    }
                case let .parenthesizedExpr(inner):
                    return checkExpr(inner, &context)
                case let .structInit(structInit):
                    return #result {
                        (
                            typeIndex: CheckedAST.TypeIndex,
                            checkedFields: [CheckedAST.Typed<CheckedAST.Expr>]
                        ) in
                        let type = structInit.ident.map(Type.nominal)
                        typeIndex <- checkType(type)
                        guard case let .struct(structIndex) = typeIndex else {
                            return .failure([
                                Diagnostic(
                                    error:
                                        "Struct initialization syntax can only be used for struct types, got '\(*structInit.ident)'",
                                    at: structInit.ident.span
                                )
                            ])
                        }

                        let structDecl = context.typeContext.structs[structIndex]
                        let structInitFieldIdents = structInit.fields.inner.map(\.inner.ident)
                        let structDeclFieldIdents = structDecl.fields.map(\.ident)
                        guard structInitFieldIdents.map(\.inner) == structDeclFieldIdents else {
                            return .failure(
                                diagnoseStructInitFieldMismatch(
                                    *structInit.ident, structDeclFieldIdents, structInitFieldIdents,
                                    expr.span
                                ))
                        }

                        checkedFields
                            <- collect(
                                structInit.fields.inner.map { field in
                                    checkExpr(field.inner.value, &context)
                                }
                            )

                        let expectedTypes = structDecl.fields.map(\.type)
                        let actualTypes = checkedFields.map(\.type)
                        guard actualTypes == expectedTypes else {
                            return .failure(
                                diagnoseStructInitFieldTypeMismatch(
                                    *structInit.fields, expectedTypes, actualTypes,
                                    typeContext: context.typeContext
                                ))
                        }

                        return .success(
                            Typed(
                                .structInit(
                                    CheckedAST.StructInitExpr(
                                        structId: structIndex, fields: checkedFields
                                    )
                                ),
                                typeIndex
                            )
                        )
                    }
                case let .memberAccess(memberAccess):
                    return #result { (base: CheckedAST.Typed<CheckedAST.Expr>) in
                        base <- checkExpr(memberAccess.base, &context)
                        guard case let .struct(structIndex) = base.type else {
                            return .failure([
                                Diagnostic(
                                    error:
                                        "Member accesses cannot be performed on builtin types, got type '\(context.typeContext.describe(base.type))'",
                                    at: expr.span
                                )
                            ])
                        }

                        let structDecl = context.typeContext.structs[structIndex]
                        guard
                            let fieldIndex = structDecl.fields.firstIndex(where: {
                                $0.ident == *memberAccess.memberIdent
                            })
                        else {
                            // TODO: Should this be attached to the member ident or the whole expression?
                            return .failure([
                                Diagnostic(
                                    error:
                                        "Value of type '\(structDecl.ident)' has no such field '\(*memberAccess.memberIdent)'",
                                    at: expr.span
                                )
                            ])
                        }
                        let field = structDecl.fields[fieldIndex]

                        return .success(
                            Typed(
                                .fieldAccess(
                                    CheckedAST.FieldAccessExpr(
                                        base: base.map(CheckedAST.Boxed.init),
                                        fieldIndex: fieldIndex
                                    )
                                ),
                                field.type
                            )
                        )
                    }
            }
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
