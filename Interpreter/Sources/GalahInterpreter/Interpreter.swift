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

    static let builtins: [String: BuiltinFn] = Self.dictionary(
        of: [
            BuiltinFn("add") { (a: Int, b: Int) in
                a + b
            },
            BuiltinFn("sub") { (a: Int, b: Int) in
                a - b
            },
            BuiltinFn("equals") { (a: Int, b: Int) in
                a == b ? 1 : 0
            },
            BuiltinFn("not") { (x: Int) in
                x == 0 ? 1 : 0
            },
            BuiltinFn("print") { (x: Any) in
                print(x)
            }
        ],
        keyedBy: \.ident
    )

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
                let arguments = try fnCallExpr.arguments.map { argument in
                    try evaluate(argument, locals)
                }

                if let builtin = Self.builtins[fnCallExpr.ident] {
                    return try builtin.call(with: arguments)
                } else {
                    guard case let .fn(fnDecl) = decls[fnCallExpr.ident] else {
                        throw RichError("No such function '\(fnCallExpr.ident)'")
                    }
                    var locals: [String: Any] = [:]
                    for (ident, value) in zip(fnDecl.params.map(\.ident), arguments) {
                        locals[ident] = value
                    }
                    return try evaluate(fnDecl.stmts, locals)
                }
            case let .ident(ident):
                guard let value = locals[ident] else {
                    throw RichError("No such local variable '\(ident)'")
                }
                return value
            case let .integerLiteral(value):
                return value
            case let .stringLiteral(value):
                return value
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
