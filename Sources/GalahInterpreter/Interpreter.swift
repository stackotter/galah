@dynamicMemberLookup
public struct Interpreter {
    /// - Parameters:
    ///   - builtinFns: The builtin functions that will be available to the script.
    ///     Defaults to ``Interpreter/defaultBuiltinFns``.
    public init(
        _ code: String,
        builtinTypes: [BuiltinType] = Self.defaultBuiltinTypes,
        builtinFns: [BuiltinFn] = Self.defaultBuiltinFns,
        diagnosticHandler handleDiagnostic: (Diagnostic) -> Void = { _ in }
    ) throws {
        do {
            let tokens = try Lexer.lex(code)

            let ast = try Parser.parse(tokens)

            let checkedAST: WithDiagnostics<CheckedAST>
            switch TypeChecker.check(ast, builtinTypes, builtinFns) {
                case let .success(value):
                    checkedAST = value
                case let .failure(diagnostics):
                    throw diagnostics
            }
            checkedAST.diagnostics.forEach(handleDiagnostic)

            self.ast = checkedAST.inner
        } catch let error as Diagnostic {
            throw [error]
        } catch {
            throw error
        }
    }

    public static let defaultBuiltinTypes: [BuiltinType] = [
        BuiltinType(ident: "Void"),
        BuiltinType(ident: "Int"),
        BuiltinType(ident: "Bool"),
        BuiltinType(ident: "String"),
    ]

    public static let defaultBuiltinFns: [BuiltinFn] = [
        BuiltinFn(binaryOp: "+") { (a: Int, b: Int) in
            a + b
        },
        BuiltinFn(binaryOp: "-") { (a: Int, b: Int) in
            a - b
        },
        BuiltinFn(binaryOp: "*") { (a: Int, b: Int) in
            a * b
        },
        BuiltinFn(binaryOp: "/") { (a: Int, b: Int) in
            a / b
        },
        BuiltinFn(binaryOp: "==") { (a: Int, b: Int) in
            a == b ? 1 : 0
        },
        BuiltinFn(binaryOp: "||") { (a: Int, b: Int) in
            (a == 1 || b == 1) ? 1 : 0
        },
        BuiltinFn(binaryOp: "&&") { (a: Int, b: Int) in
            (a == 1 && b == 1) ? 1 : 0
        },
        BuiltinFn(unaryOp: "!") { (x: Int) in
            x == 0 ? 1 : 0
        },
        BuiltinFn(unaryOp: "-") { (x: Int) in
            -x
        },
        BuiltinFn(binaryOp: ">") { (x: Int, y: Int) in
            x > y ? 1 : 0
        },
        BuiltinFn(binaryOp: "<") { (x: Int, y: Int) in
            x < y ? 1 : 0
        },
        BuiltinFn(binaryOp: ">=") { (x: Int, y: Int) in
            x >= y ? 1 : 0
        },
        BuiltinFn(binaryOp: "<=") { (x: Int, y: Int) in
            x <= y ? 1 : 0
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

    public func evaluateMainFn() throws {
        guard let fn = ast.fn(named: "main", withParamTypes: []) else {
            throw Diagnostic(error: "Missing 'main' function", at: nil)
        }

        guard fn.signature.returnType == ast.typeContext.void else {
            throw Diagnostic(error: "'main' function must return 'Void'", at: nil)
        }

        _ = try evaluate(fn, arguments: [])
    }

    public subscript<R: GalahRepresentable>(dynamicMember fnName: String) -> (
        (any GalahRepresentable...) throws -> R
    ) {
        { arguments in
            try evaluateFn(named: fnName, arguments: arguments)
        }
    }

    public func evaluateFn<R: GalahRepresentable>(
        named name: String,
        arguments: [any GalahRepresentable]
    ) throws -> R {
        let parameterTypes = arguments.map { type(of: $0).type }
        let checkedParameterTypes = try collect(
            parameterTypes.map { type in
                ast.typeContext.checkType(type)
            }
        ).get()

        guard let fn = ast.fn(named: name, withParamTypes: checkedParameterTypes) else {
            let parameterTypesList = parameterTypes.map(\.description).joined(separator: ", ")
            throw Diagnostic(
                error: "No such function '\(name)' with parameter types '(\(parameterTypesList))'",
                at: nil
            )
        }

        guard fn.signature.returnType == (try ast.typeContext.checkType(R.type).get()) else {
            throw Diagnostic(
                error: "No such function '\(name) with return type '\(R.type.description)'",
                at: nil
            )
        }

        return try evaluate(fn, arguments: arguments) as! R
    }

    public func evaluate(_ fn: CheckedAST.Fn, arguments: [Any]) throws -> Any {
        var locals = arguments
        locals.append(contentsOf: Array(repeating: Void(), count: fn.localCount - arguments.count))
        switch try evaluate(fn.stmts, &locals) {
            case let .some(.return(value)):
                return value
            case .none:
                return Void()
        }
    }

    public func evaluate(_ stmts: [CheckedAST.Stmt], _ locals: inout [Any]) throws -> StmtEffect? {
        for stmt in stmts {
            switch try evaluate(stmt, &locals) {
                case .some(.return(let value)):
                    return .return(value)
                case .none:
                    continue
            }
        }
        return nil
    }

    public func evaluate(_ stmt: CheckedAST.Stmt, _ locals: inout [Any]) throws -> StmtEffect? {
        switch stmt {
            case let .expr(expr):
                _ = try evaluate(expr.inner, &locals)
                return nil
            case let .return(expr):
                if let expr {
                    return .return(try evaluate(expr.inner, &locals))
                } else {
                    return .return(Void())
                }
            case let .let(varDecl):
                locals[varDecl.localIndex] = try evaluate(varDecl.value.inner, &locals)
                return nil
            case let .if(ifStmt):
                return try evaluate(ifStmt, &locals)
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

    public func evaluate(_ ifStmt: CheckedAST.IfStmt, _ locals: inout [Any]) throws -> StmtEffect? {
        let condition: Int = Self.cast(try evaluate(ifStmt.ifBlock.condition, &locals))
        if condition != 0 {
            return try evaluate(ifStmt.ifBlock.block, &locals)
        } else {
            for elseIfBlock in ifStmt.elseIfBlocks {
                let condition: Int = Self.cast(try evaluate(elseIfBlock.condition, &locals))
                if condition != 0 {
                    return try evaluate(elseIfBlock.block, &locals)
                }
            }
            if let elseBlock = ifStmt.elseBlock {
                return try evaluate(elseBlock, &locals)
            }
            return nil
        }
    }

    public func evaluate(_ expr: CheckedAST.Expr, _ locals: inout [Any]) throws -> Any {
        switch expr {
            case let .constant(value):
                return value
            case let .fnCall(fnCallExpr):
                let arguments = try fnCallExpr.arguments.map { argument in
                    try evaluate(argument.inner, &locals)
                }
                switch fnCallExpr.id {
                    case let .builtin(index):
                        return try ast.builtinFns[index].call(with: arguments)
                    case let .userDefined(index):
                        return try evaluate(ast.fns[index], arguments: arguments)
                    case .constructor:
                        return arguments
                }
            case let .localVar(index):
                return locals[index]
            case let .structInit(structInit):
                let fields = try structInit.fields.map { field in
                    try evaluate(field.inner, &locals)
                }
                return fields
            case let .fieldAccess(fieldAccess):
                let base = try evaluate(fieldAccess.base.inner.inner, &locals)
                guard let fields = base as? [Any] else {
                    throw Diagnostic(
                        error:
                            "Precondition failed, expressions resulting in structs must be represented internally as arrays of fields",
                        at: nil
                    )
                }
                return fields[fieldAccess.fieldIndex]
        }
    }

    public static func dictionary<T, K: Hashable>(
        of values: [T],
        keyedBy keyPath: KeyPath<T, K>
    ) -> [K: T] {
        var dictionary: [K: T] = [:]
        for value in values {
            dictionary[value[keyPath: keyPath]] = value
        }
        return dictionary
    }
}
