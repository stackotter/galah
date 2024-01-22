public struct AST {
    public var decls: [Decl]

    public init(decls: [Decl]) {
        self.decls = decls
    }
}

public enum Decl {
    case fn(FnDecl)
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
}

public enum Expr {
    case stringLiteral(String)
    case fnCall(FnCallExpr)
}

public struct FnCallExpr {
    public var ident: String
    public var arguments: [Expr]
}

public struct Tuple {
    public var elements: [Expr]
}
