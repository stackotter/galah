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

    public enum StmtEffect {
        case `return`(Any)
    }

    var ast: CheckedAST

    public init(_ ast: CheckedAST) {
        self.ast = ast
    }

    public func evaluate(_ stmts: [CheckedAST.Stmt], _ locals: [Any]) throws -> StmtEffect? {
        for stmt in stmts {
            switch try evaluate(stmt, locals) {
                case .some(.return(let value)):
                    return .return(value)
                case .none:
                    continue
            }
        }
        return nil
    }

    public func evaluate(_ stmt: CheckedAST.Stmt, _ locals: [Any]) throws -> StmtEffect? {
        switch stmt {
            case let .expr(expr):
                _ = try evaluate(expr.inner, locals)
                return nil
            case let .return(expr):
                return .return(try evaluate(expr.inner, locals))
            case let .if(ifStmt):
                return try evaluate(ifStmt, locals)
        }
    }

    private static func cast<T>(_ value: Any) -> T {
        assert(type(of: value) == T.self)
        return withUnsafePointer(to: value) { pointer in
            pointer.withMemoryRebound(to: T.self, capacity: 1) { pointer in
                pointer.pointee
            }
        }
    }

    public func evaluate(_ ifStmt: CheckedAST.IfStmt, _ locals: [Any]) throws -> StmtEffect? {
        let condition: Int = Self.cast(try evaluate(ifStmt.ifBlock.condition, locals))
        if condition != 0 {
            return try evaluate(ifStmt.ifBlock.block, locals)
        } else {
            for elseIfBlock in ifStmt.elseIfBlocks {
                let condition: Int = Self.cast(try evaluate(elseIfBlock.condition, locals))
                if condition != 0 {
                    return try evaluate(elseIfBlock.block, locals)
                }
            }
            if let elseBlock = ifStmt.elseBlock {
                return try evaluate(elseBlock, locals)
            }
            return nil
        }
    }

    public func evaluate(_ expr: CheckedAST.Expr, _ locals: [Any]) throws -> Any {
        switch expr {
            case let .constant(value):
                return value
            case let .fnCall(fnCallExpr):
                let arguments = try fnCallExpr.arguments.map { argument in
                    try evaluate(argument.inner, locals)
                }
                switch fnCallExpr.id {
                    case let .builtin(index):
                        return try ast.builtins[index].call(with: arguments)
                    case let .userDefined(index):
                        return switch try evaluate(ast.fns[index].stmts, arguments) {
                            case .some(.return(let value)):
                                value
                            case .none:
                                Void()
                        }
                }
            case let .localVar(index):
                return locals.withUnsafeBufferPointer { $0[index] }
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
