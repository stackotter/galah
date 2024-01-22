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

        try interpreter.evaluate(main.stmts)
    }

    var decls: [String: Decl]

    public init(_ ast: AST) {
        decls = [:]
        for decl in ast.decls {
            decls[decl.ident] = decl
        }
    }

    public func evaluate(_ stmts: [Stmt]) throws {
        for stmt in stmts {
            try evaluate(stmt)
        }
    }

    public func evaluate(_ stmt: Stmt) throws {
        switch stmt {
            case let .expr(expr):
                _ = try evaluate(expr)
        }
    }

    public func evaluate(_ expr: Expr) throws -> Any {
        switch expr {
            case let .fnCall(fnCallExpr):
                let arguments = try fnCallExpr.arguments.map { argument in
                    try evaluate(argument)
                }
                switch fnCallExpr.ident {
                    case "print":
                        var argumentStrings: [String] = []
                        for argument in arguments {
                            argumentStrings.append("\(argument)")
                        }
                        print(argumentStrings.joined(separator: " "))
                    default:
                        guard case let .fn(fnDecl) = decls[fnCallExpr.ident] else {
                            throw RichError("No such function '\(fnCallExpr.ident)'")
                        }
                        try evaluate(fnDecl.stmts)
                }
                return Void()
            case let .stringLiteral(value):
                return value
        }
    }
}
