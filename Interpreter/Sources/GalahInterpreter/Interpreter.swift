func todo(_ message: String) -> Never {
    print("todo: \(message)")
    exit(1)
}

public struct Interpreter {
    public static func run(_ code: String) throws {
        let tokens = try Lexer.lex(code)

        let ast = try Parser.parse(tokens)

        let checkedAST = try TypeChecker.check(ast, builtins)

        let interpreter = Interpreter(checkedAST)

        guard let main = interpreter.ast.fn(named: "main", withParamTypes: []) else {
            throw RichError("Missing 'main' function")
        }

        _ = try interpreter.evaluate(main.stmts, [])
    }

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
        BuiltinFn("print") { (x: Int) in
            print(x)
        },
        BuiltinFn("print") { (x: String) in
            print(x)
        },
    ]

    var ast: CheckedAST

    public init(_ ast: CheckedAST) {
        self.ast = ast
    }

    public func evaluate(_ stmts: [CheckedAST.Stmt], _ locals: [Any]) throws -> Any {
        for (i, stmt) in stmts.enumerated() {
            let result = try evaluate(stmt, locals)
            if i == stmts.count - 1 {
                return result
            }
        }
        return Void()
    }

    public func evaluate(_ stmt: CheckedAST.Stmt, _ locals: [Any]) throws -> Any {
        switch stmt {
            case let .expr(expr):
                return try evaluate(expr, locals)
            case let .if(ifStmt):
                return try evaluate(ifStmt, locals)
        }
    }

    public func evaluate(_ ifStmt: CheckedAST.IfStmt, _ locals: [Any]) throws -> Any {
        let condition = try evaluate(ifStmt.ifBlock.condition, locals) as! Int
        if condition != 0 {
            return try evaluate(ifStmt.ifBlock.block, locals)
        } else {
            for elseIfBlock in ifStmt.elseIfBlocks {
                let condition = try evaluate(elseIfBlock.condition, locals) as! Int
                if condition != 0 {
                    return try evaluate(elseIfBlock.block, locals)
                }
            }
            if let elseBlock = ifStmt.elseBlock {
                return try evaluate(elseBlock, locals)
            }
            return Void()
        }
    }

    public func evaluate(_ expr: CheckedAST.Expr, _ locals: [Any]) throws -> Any {
        switch expr {
            case let .constant(value):
                return value
            case let .fnCall(fnCallExpr):
                let arguments = try fnCallExpr.arguments.map { argument in
                    try evaluate(argument, locals)
                }
                switch fnCallExpr.id {
                    case let .builtin(index):
                        return try ast.builtins[index].call(with: arguments)
                    case let .userDefined(index):
                        return try evaluate(ast.fns[index].stmts, arguments)
                }
            case let .localVar(index):
                return locals[index]
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
