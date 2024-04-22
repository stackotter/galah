public struct AST {
    public var structDecls: [WithSpan<StructDecl>]
    public var fnDecls: [WithSpan<FnDecl>]

    public init(structDecls: [WithSpan<StructDecl>], fnDecls: [WithSpan<FnDecl>]) {
        self.structDecls = structDecls
        self.fnDecls = fnDecls
    }
}

public struct StructDecl {
    public var ident: WithSpan<String>
    public var fields: [WithSpan<Field>]
}

public struct Field {
    public var ident: WithSpan<String>
    public var type: WithSpan<Type>
}

public struct FnSignature: Hashable {
    public var ident: WithSpan<String>
    public var paramTypes: [WithSpan<Type>]
    public var returnType: WithSpan<Type>?

    public init(
        ident: WithSpan<String>,
        paramTypes: [WithSpan<Type>],
        returnType: WithSpan<Type>? = nil
    ) {
        self.ident = ident
        self.paramTypes = paramTypes
        self.returnType = returnType
    }

    public init(builtin ident: String, paramTypes: [Type], returnType: Type? = nil) {
        self.ident = WithSpan(builtin: ident)
        self.paramTypes = paramTypes.map(WithSpan.init(builtin:))
        self.returnType = returnType.map(WithSpan.init(builtin:))
    }
}

public struct FnDecl {
    public var ident: WithSpan<String>
    public var params: [WithSpan<Param>]
    public var returnType: WithSpan<Type>?
    public var stmts: [WithSpan<Stmt>]

    public var signature: FnSignature {
        FnSignature(ident: ident, paramTypes: params.map(\.type), returnType: returnType)
    }
}

public struct Param {
    public var ident: WithSpan<String>
    public var type: WithSpan<Type>
}

public enum Type: Hashable, CustomStringConvertible {
    case nominal(String)

    public static var void: Type {
        .nominal("Void")
    }

    public static var any: Type {
        .nominal("Any")
    }

    public var description: String {
        switch self {
            case let .nominal(name):
                name
        }
    }
}

public struct VarDecl {
    public var ident: WithSpan<String>
    public var type: WithSpan<Type>?
    public var value: WithSpan<Expr>
}

public enum Stmt {
    case expr(Expr)
    case `if`(IfStmt)
    case `return`(WithSpan<Expr>?)
    case `let`(VarDecl)
}

extension Stmt {
    public var endsWithCodeBlock: Bool {
        switch self {
            case .if:
                true
            case .expr, .return, .let:
                false
        }
    }
}

public struct IfStmt {
    public indirect enum ElseBlock {
        case elseIf(WithSpan<IfStmt>)
        case `else`([WithSpan<Stmt>])
    }

    public var condition: WithSpan<Expr>
    public var ifBlock: [WithSpan<Stmt>]
    public var `else`: ElseBlock?
}

public indirect enum Expr {
    case stringLiteral(String)
    case integerLiteral(Int)
    case fnCall(FnCallExpr)
    case ident(String)
    case unaryOp(UnaryOpExpr)
    case binaryOp(BinaryOpExpr)
    case parenthesizedExpr(WithSpan<Expr>)
}

extension Expr: CustomStringConvertible {
    public var description: String {
        switch self {
            case .stringLiteral(let value):
                return "\"\(value)\""
            case .integerLiteral(let value):
                return "\(value)"
            case .fnCall(let fnCall):
                return
                    "\(fnCall.ident)(\(fnCall.arguments.map(\.inner.description).joined(separator: ", ")))"
            case .ident(let ident):
                return ident
            case .unaryOp(let unaryOp):
                return "\(unaryOp.op)\(unaryOp.operand)"
            case .binaryOp(let binaryOp):
                return "\(binaryOp.leftOperand) + \(binaryOp.rightOperand)"
            case .parenthesizedExpr(let expr):
                return "(\(expr))"
        }
    }
}

public struct UnaryOpExpr {
    let op: WithSpan<Op>
    let operand: WithSpan<Expr>
}

public struct BinaryOpExpr {
    let op: WithSpan<Op>
    let leftOperand: WithSpan<Expr>
    let rightOperand: WithSpan<Expr>
}

public struct FnCallExpr {
    public var ident: WithSpan<String>
    public var arguments: [WithSpan<Expr>]
}

public struct Tuple {
    public var elements: [WithSpan<Expr>]
}
