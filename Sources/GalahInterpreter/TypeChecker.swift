public struct TypeChecker {
    public static func check(_ ast: AST, _ builtins: [BuiltinFn]) throws -> CheckedAST {
        try TypeChecker(ast, builtins).check()
    }

    typealias LocalsTable = [String: (index: Int, type: Type)]
    typealias Typed = CheckedAST.Typed

    private struct Analyzed<T> {
        var inner: T
        var returnsOnAllPaths: Bool

        init(_ inner: T, returnsOnAllPaths: Bool) {
            self.inner = inner
            self.returnsOnAllPaths = returnsOnAllPaths
        }

        func map<U>(_ action: (T) -> U) -> Analyzed<U> {
            Analyzed<U>(
                action(inner),
                returnsOnAllPaths: returnsOnAllPaths
            )
        }
    }

    let builtins: [BuiltinFn]
    let fnDecls: [FnDecl]
    let fnTable: [(CheckedAST.FnId, FnSignature)]

    private init(_ ast: AST, _ builtins: [BuiltinFn]) throws {
        self.builtins = builtins
        fnDecls = ast.decls.compactMap(\.asFnDecl)
        fnTable = try Self.buildFnLookupTable(fnDecls, builtins)
    }

    private func check() throws -> CheckedAST {
        var fns: [CheckedAST.Fn] = []
        for fn in fnDecls {
            fns.append(try checkFn(fn))
        }
        return CheckedAST(builtins: builtins, fns: fns)
    }

    private func checkFn(_ fn: FnDecl) throws -> CheckedAST.Fn {
        var locals: LocalsTable = [:]
        for (i, param) in fn.params.enumerated() {
            locals[param.ident] = (index: i, type: param.type)
        }

        let analyzedStmts = try checkStmts(fn.stmts, expecting: fn.signature.returnType, locals)
        if let returnType = fn.returnType, returnType != .nominal("Void") {
            guard analyzedStmts.returnsOnAllPaths else {
                throw RichError("Non-void function must return on all paths")
            }
        }

        return CheckedAST.Fn(signature: fn.signature, stmts: analyzedStmts.inner)
    }

    private func checkStmts(_ stmts: [Stmt], expecting returnType: Type, _ locals: LocalsTable) throws -> Analyzed<[CheckedAST.Stmt]> {
        let analyzedStmts = try stmts.map { stmt in
            try checkStmt(stmt, expecting: returnType, locals)
        }
        return Analyzed(
            analyzedStmts.map(\.inner),
            returnsOnAllPaths: analyzedStmts.contains(where: \.returnsOnAllPaths)
        )
    }

    private func checkStmt(_ stmt: Stmt, expecting returnType: Type, _ locals: LocalsTable) throws -> Analyzed<CheckedAST.Stmt> {
        switch stmt {
            case let .if(ifStmt):
                return (try checkIfStmt(ifStmt, expecting: returnType, locals)).map(CheckedAST.Stmt.if)
            case let .return(expr):
                let checkedExpr: Typed<CheckedAST.Expr>? = if let expr {
                    try checkExpr(expr, locals)
                } else {
                    nil
                }
                guard (checkedExpr?.type ?? .nominal("Void")) == returnType else {
                    if let checkedExpr {
                        throw RichError("Function expected to return '\(returnType)', got expression of type '\(checkedExpr.type)'")
                    } else {
                        throw RichError("Returned expected to return '\(returnType)', got 'Void'")
                    }
                }
                return Analyzed(.return(checkedExpr), returnsOnAllPaths: true)
            case let .expr(expr):
                return Analyzed(.expr(try checkExpr(expr, locals)), returnsOnAllPaths: false)
        }
    }

    private func checkIfStmt(_ ifStmt: IfStmt, expecting returnType: Type, _ locals: LocalsTable) throws -> Analyzed<CheckedAST.IfStmt> {
        let condition = try checkExpr(ifStmt.condition, locals)
        guard condition.type == Int.type else {
            throw RichError("If statement condition must be of type '\(Int.type)', got \(condition.type)")
        }

        let checkedIfBlock = try checkStmts(ifStmt.ifBlock, expecting: returnType, locals)
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
                    let condition = try checkExpr(ifBlock.condition, locals)
                    guard condition.type == Int.type else {
                        throw RichError("If statement condition must be of type '\(Int.type)', got \(condition.type)")
                    }
                    let checkedBlock = try checkStmts(ifBlock.ifBlock, expecting: returnType, locals)
                    elseIfBlocks.append(CheckedAST.IfBlock(
                        condition: condition.inner,
                        block: checkedBlock.inner
                    ))
                    elseBlock = ifBlock.else
                    returnsOnAllPaths = returnsOnAllPaths && checkedBlock.returnsOnAllPaths
                case let .else(stmts):
                    let checkedBlock = try checkStmts(stmts, expecting: returnType, locals)
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

    private func checkExpr(_ expr: Expr, _ locals: LocalsTable) throws -> Typed<CheckedAST.Expr> {
        switch expr {
            case let .stringLiteral(content):
                return Typed(.constant(content), String.type)
            case let .integerLiteral(value):
                return Typed(.constant(value), Int.type)
            case let .fnCall(fnCallExpr):
                let arguments = try fnCallExpr.arguments.map { expr in
                    try checkExpr(expr, locals)
                }
                let (id, signature) = try resolveFn(fnCallExpr.ident, arguments.map(\.type))
                return Typed(
                    .fnCall(CheckedAST.FnCallExpr(id: id, arguments: arguments)),
                    signature.returnType
                )
            case let .ident(ident):
                guard let local = locals[ident] else {
                    throw RichError("No such variable '\(ident)'")
                }
                return Typed(.localVar(local.index), local.type)
            case let .unaryOp(unaryOpExpr):
                let operand = try checkExpr(unaryOpExpr.operand, locals)
                let (id, signature) = try resolveFn(unaryOpExpr.op.token, [operand.type])
                return Typed(
                    .fnCall(CheckedAST.FnCallExpr(id: id, arguments: [operand])),
                    signature.returnType
                )
            case let .binaryOp(binaryOpExpr):
                let leftOperand = try checkExpr(binaryOpExpr.leftOperand, locals)
                let rightOperand = try checkExpr(binaryOpExpr.rightOperand, locals)
                let (id, signature) = try resolveFn(binaryOpExpr.op.token, [leftOperand.type, rightOperand.type])
                return Typed(
                    .fnCall(CheckedAST.FnCallExpr(id: id, arguments: [leftOperand, rightOperand])),
                    signature.returnType
                )
            case let .parenthesizedExpr(inner):
                return try checkExpr(inner, locals)
        }
    }

    private func resolveFn(_ ident: String, _ argumentTypes: [Type]) throws -> (CheckedAST.FnId, FnSignature) {
        guard
            let (id, signature) = fnTable.first(where: { (_, signature) in
                signature.ident == ident && signature.paramTypes == argumentTypes
            })
        else {
            let parameters = argumentTypes.map(\.description).joined(separator: ", ")
            let alternativesCount = fnTable.filter { $0.1.ident == ident }.count
            throw RichError(
                "No such function '\(ident)' with parameters '(\(parameters))'. "
                + "Found \(alternativesCount) functions with the same name but incompatible parameter types"
            )
        }

        return (id, signature)
    }

    private static func buildFnLookupTable(
        _ fnDecls: [FnDecl],
        _ builtins: [BuiltinFn]
    ) throws -> [(CheckedAST.FnId, FnSignature)] {
        var table: [(CheckedAST.FnId, FnSignature)] = []

        for (i, fn) in builtins.enumerated() {
            let isDuplicate = table.contains { other in
                other.1.ident == fn.signature.ident && other.1.paramTypes == fn.signature.paramTypes
            }
            if isDuplicate {
                let paramTypes = fn.signature.paramTypes.map(\.description).joined(separator: ", ")
                let returnType = fn.signature.returnType
                // TODO: Enrich error message with more information about the two clashing signatures
                throw RichError("Duplicate definition of '\(fn.signature.ident)' with parameter types '(\(paramTypes)) -> \(returnType)'")
            }
            table.append((.builtin(index: i), fn.signature))
        }

        for (i, fn) in fnDecls.enumerated() {
            let isDuplicate = table.contains { other in
                other.1.ident == fn.ident && other.1.paramTypes == fn.signature.paramTypes
            }
            if isDuplicate {
                let paramTypes = fn.signature.paramTypes.map(\.description).joined(separator: ", ")
                let returnType = fn.signature.returnType
                throw RichError("Duplicate definition of '\(fn.ident)' with type '(\(paramTypes)) -> \(returnType)'")
            }
            table.append((.userDefined(index: i), fn.signature))
        }

        return table
    }
}
