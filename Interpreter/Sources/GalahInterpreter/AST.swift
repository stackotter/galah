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
            case let .fn(decl): decl.ident
        }
    }
}

public struct FnDecl {
    public var ident: String
    public var params: [Param]
    public var stmts: [Stmt]
}

public struct Param {
    public var ident: String
    public var type: String?
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

    var condition: Expr
    var ifBlock: [Stmt]
    var `else`: ElseBlock?
}


public enum Expr {
    case stringLiteral(String)
    case integerLiteral(Int)
    case fnCall(FnCallExpr)
    case ident(String)
}

public struct FnCallExpr {
    public var ident: String
    public var arguments: [Expr]
}

public struct Tuple {
    public var elements: [Expr]
}
