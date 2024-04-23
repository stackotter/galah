public struct CheckedAST {
    public var builtinTypes: [BuiltinType]
    public var structs: [Struct]
    public var builtinFns: [BuiltinFn]
    public var fns: [Fn]

    public struct Typed<Inner> {
        public var inner: Inner
        public var type: Type

        public init(_ inner: Inner, _ type: Type) {
            self.inner = inner
            self.type = type
        }
    }

    public struct Struct {
        public var ident: String
        public var fields: [Field]
    }

    public enum TypeIndex: Hashable {
        case builtin(Int)
        case `struct`(Int)
    }

    public struct Field: Hashable {
        public var ident: String
        public var type: TypeIndex
    }

    public struct Fn {
        public var signature: FnSignature
        /// Number of local variables created/used within the function. The first n are expected
        /// to be the function's arguments.
        public var localCount: Int
        public var stmts: [Stmt]
    }

    public struct VarDecl {
        public var localIndex: Int
        public var value: Typed<Expr>
    }

    public enum Stmt {
        case `if`(IfStmt)
        case `return`(Typed<Expr>?)
        case `let`(VarDecl)
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
            *fn.signature.ident == ident && fn.signature.paramTypes.map(\.inner) == paramTypes
        }
    }
}
