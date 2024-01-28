public struct CheckedAST {
    public var builtins: [BuiltinFn]
    public var fns: [Fn]

    public struct Fn {
        public var stmts: [Stmt]
    }

    public enum Stmt {
        case `if`(IfStmt)
        case expr(Expr)
    }

    public struct IfStmt {
        public var ifBlock: IfBlock
        public var elseIfBlocks: [IfBlock]
        public var elseBlock: [Stmt]?
    }

    public struct IfBlock {
        public var condition: Expr
        public var block: [Stmt]
    }

    public enum Expr {
        case constant(Any)
        case fnCall(FnCallExpr)
        case localVar(Int)
    }

    public enum FnId {
        case builtin(index: Int)
        case userDefined(index: Int)
    }

    public struct FnCallExpr {
        public var id: FnId
        public var arguments: [Expr]
    }
}
