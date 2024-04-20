public struct TypeChecker {
    public static func check(_ ast: AST, _ builtins: [BuiltinFn]) throws -> WithDiagnostics<
        CheckedAST
    > {
        try TypeChecker(ast, builtins).check()
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

    let builtins: [BuiltinFn]
    let fnDecls: [WithSpan<FnDecl>]
    let fnTable: [(CheckedAST.FnId, FnSignature)]

    private init(_ ast: AST, _ builtins: [BuiltinFn]) throws {
        self.builtins = builtins
        fnDecls = ast.fnDecls
        fnTable = try Self.buildFnLookupTable(fnDecls, builtins)
    }

    private func check() throws -> WithDiagnostics<CheckedAST> {
        let fns: WithDiagnostics<[CheckedAST.Fn]> = try fnDecls.map(checkFn).collect()
        return fns.map { fns in
            CheckedAST(builtins: builtins, fns: fns)
        }
    }

    private func checkFn(_ fn: WithSpan<FnDecl>) throws -> WithDiagnostics<CheckedAST.Fn> {
        let span = fn.span
        let fn = *fn
        var context = FnContext(expectedReturnType: fn.signature.returnType?.inner ?? .void)
        for param in fn.params {
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
                let checkedExpr = try checkExpr(varDecl.value, &context)
                if let type = varDecl.type, checkedExpr.type != *type {
                    throw Diagnostic(
                        error:
                            "Let binding '\(varDecl.ident)' expected expression of type '\(type)', got expression of type '\(checkedExpr.type)'",
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
