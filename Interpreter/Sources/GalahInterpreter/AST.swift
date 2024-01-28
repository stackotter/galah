public struct AST {
    public var decls: [Decl]

    public init(decls: [Decl]) {
        self.decls = decls
    }
}

public enum Decl {
    case fn(FnDecl)

    var ident: String {
        switch self {
            case let .fn(decl): decl.signature.ident
        }
    }
}

public struct FnSignature {
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

public enum Type {
    case nominal(String)

    public static var void: Type {
        .nominal("Void")
    }

    public static var any: Type {
        .nominal("Any")
    }
}

public enum Stmt {
    case expr(Expr)
    case `if`(IfStmt)
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
    case parenthesisedExpr(Expr)
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
