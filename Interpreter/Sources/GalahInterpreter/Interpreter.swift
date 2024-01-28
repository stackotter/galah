func todo(_ message: String) -> Never {
    print("todo: \(message)")
    exit(1)
}

public struct Interpreter {
    public static func run(_ code: String) throws {
        let tokens = try Lexer.lex(code)

        let ast = try Parser.parse(tokens)

        let interpreter = Interpreter(ast)

        guard case let .fn(main) = interpreter.decls["main"] else {
            throw RichError("Missing 'main' function")
        }

        guard main.params.isEmpty else {
            throw RichError("'main' function must not have any parameters")
        }

        _ = try interpreter.evaluate(main.stmts, [:])
    }

    var decls: [String: Decl]

    static let builtins: [BuiltinFn] = [
        BuiltinFn(binaryOp: "+") { (a: Int, b: Int) in
            a + b
        },
        BuiltinFn(binaryOp: "-") { (a: Int, b: Int) in
            a - b
        },
        BuiltinFn(binaryOp: "==") { (a: Int, b: Int) in
            a == b ? 1 : 0
        },
        BuiltinFn(unaryOp: "!") { (x: Int) in
            x == 0 ? 1 : 0
        },
        BuiltinFn(unaryOp: "-") { (x: Int) in
            -x
        },
        BuiltinFn("print") { (x: Any) in
            print(x)
        },
    ]

    public init(_ ast: AST) {
        decls = Self.dictionary(of: ast.decls, keyedBy: \.ident)
    }

    public func evaluate(_ stmts: [Stmt], _ locals: [String: Any]) throws -> Any {
        for (i, stmt) in stmts.enumerated() {
            let result = try evaluate(stmt, locals)
            if i == stmts.count - 1 {
                return result
            }
        }
        return Void()
    }

    public func evaluate(_ stmt: Stmt, _ locals: [String: Any]) throws -> Any {
        switch stmt {
            case let .expr(expr):
                return try evaluate(expr, locals)
            case let .if(ifStmt):
                return try evaluate(ifStmt, locals)
        }
    }

    public func evaluate(_ ifStmt: IfStmt, _ locals: [String: Any]) throws -> Any {
        guard let condition = try evaluate(ifStmt.condition, locals) as? Int else {
            throw RichError("'if' conditions must be integers")
        }

        if condition != 0 {
            return try evaluate(ifStmt.ifBlock, locals)
        } else {
            switch ifStmt.`else` {
                case let .elseIf(elseIfBlock):
                    return try evaluate(elseIfBlock, locals)
                case let .else(stmts):
                    return try evaluate(stmts, locals)
                case nil:
                    return Void()
            }
        }
    }

    public func evaluate(_ expr: Expr, _ locals: [String: Any]) throws -> Any {
        switch expr {
            case let .fnCall(fnCallExpr):
                return try evaluate(fnCallExpr, locals)
            case let .ident(ident):
                guard let value = locals[ident] else {
                    throw RichError("No such local variable '\(ident)'")
                }
                return value
            case let .integerLiteral(value):
                return value
            case let .stringLiteral(value):
                return value
            case let .binaryOp(opExpr):
                return try evaluate(
                    FnCallExpr(
                        ident: opExpr.op.token,
                        arguments: [opExpr.leftOperand, opExpr.rightOperand]
                    ),
                    locals
                )
            case let .unaryOp(opExpr):
                return try evaluate(
                    FnCallExpr(
                        ident: opExpr.op.token,
                        arguments: [opExpr.operand]
                    ),
                    locals
                )
            case let .parenthesisedExpr(innerExpr):
                return try evaluate(innerExpr, locals)
        }
    }

    public func evaluate(_ fnCallExpr: FnCallExpr, _ locals: [String: Any]) throws -> Any {
        let arguments = try fnCallExpr.arguments.map { argument in
            try evaluate(argument, locals)
        }

        if let builtin = Self.builtins.first(where: { $0.signature.ident == fnCallExpr.ident && ($0.arity == nil || $0.arity == arguments.count) }) {
            return try builtin.call(with: arguments)
        } else {
            guard case let .fn(fnDecl) = decls[fnCallExpr.ident] else {
                // TODO: Update error message to be more correct (currently incorrect when
                //   you try to call a built-in function with an incorrect number of args).
                let type = "(\(arguments.map { _ in "_" }.joined(separator: ", "))) -> _"
                throw RichError("No such function '\(fnCallExpr.ident)' with type '\(type)'")
            }
            var locals: [String: Any] = [:]
            for (ident, value) in zip(fnDecl.params.map(\.ident), arguments) {
                locals[ident] = value
            }
            return try evaluate(fnDecl.stmts, locals)
        }
    }

    public static func dictionary<T, K: Hashable>(of values: [T], keyedBy keyPath: KeyPath<T, K>) -> [K: T] {
        var dictionary: [K: T] = [:]
        for value in values {
            dictionary[value[keyPath: keyPath]] = value
        }
        return dictionary
    }
}
