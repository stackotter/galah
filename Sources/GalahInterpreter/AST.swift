public struct AST {
    public var decls: [Decl]

    public init(decls: [Decl]) {
        self.decls = decls
    }
}

public enum Decl {
    case fn(FnDecl)

    public var ident: String {
        switch self {
            case let .fn(decl): decl.signature.ident
        }
    }

    public var asFnDecl: FnDecl? {
        switch self {
            case let .fn(fnDecl):
                fnDecl
        }
    }
}

public struct FnSignature: Hashable {
    public var ident: String
    public var paramTypes: [Type]
    public var returnType: Type
}

public struct FnDecl {
    public var ident: String
    public var params: [Param]
    public var returnType: Type?
    public var stmts: [Stmt]

    public var signature: FnSignature {
        FnSignature(ident: ident, paramTypes: params.map(\.type), returnType: returnType ?? .nominal("Void"))
    }
}

public struct Param {
    public var ident: String
    public var type: Type
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
    public var ident: String
    public var type: Type?
    public var value: Expr
}

public enum Stmt {
    case expr(Expr)
    case `if`(IfStmt)
    case `return`(Expr?)
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
        case elseIf(IfStmt)
        case `else`([Stmt])
    }

    public var condition: Expr
    public var ifBlock: [Stmt]
    public var `else`: ElseBlock?
}

public indirect enum Expr {
    case stringLiteral(String)
    case integerLiteral(Int)
    case fnCall(FnCallExpr)
    case ident(String)
    case unaryOp(UnaryOpExpr)
    case binaryOp(BinaryOpExpr)
    case parenthesizedExpr(Expr)
}

extension Expr: CustomStringConvertible {
    public var description: String {
        switch self {
            case .stringLiteral(let value):
                return "\"\(value)\""
            case .integerLiteral(let value):
                return "\(value)"
            case .fnCall(let fnCall):
                return "\(fnCall.ident)(\(fnCall.arguments.map(\.description).joined(separator: ", ")))"
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
    let op: Op
    let operand: Expr
}

public struct BinaryOpExpr {
    let op: Op
    let leftOperand: Expr
    let rightOperand: Expr
}

public struct FnCallExpr {
    public var ident: String
    public var arguments: [Expr]
}

public struct Tuple {
    public var elements: [Expr]
}
