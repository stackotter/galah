public struct CheckedAST {
    public var builtins: [BuiltinFn]
    public var fns: [Fn]

    public struct Typed<Inner> {
        public var inner: Inner
        public var type: Type

        public init(_ inner: Inner, _ type: Type) {
            self.inner = inner
            self.type = type
        }
    }

    public struct Fn {
        public var signature: FnSignature
        public var stmts: [Stmt]
    }

    public enum Stmt {
        case `if`(IfStmt)
        case `return`(Typed<Expr>)
        case expr(Typed<Expr>)
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
        public var arguments: [Typed<Expr>]
    }

    public func fn(named ident: String, withParamTypes paramTypes: [Type]) -> Fn? {
        fns.first { fn in
            fn.signature.ident == ident && fn.signature.paramTypes == paramTypes
        }
    }
}
