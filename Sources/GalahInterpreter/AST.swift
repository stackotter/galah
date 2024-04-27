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
    public var params: [WithSpan<Param>]
    public var returnType: WithSpan<Type>?

    public init(
        ident: WithSpan<String>,
        params: [WithSpan<Param>],
        returnType: WithSpan<Type>? = nil
    ) {
        self.ident = ident
        self.params = params
        self.returnType = returnType
    }

    public init(builtin ident: String, params: [Param], returnType: Type? = nil) {
        self.ident = WithSpan(builtin: ident)
        self.params = params.map(WithSpan.init(builtin:))
        self.returnType = returnType.map(WithSpan.init(builtin:))
    }
}

public struct FnDecl {
    public var signature: WithSpan<FnSignature>
    public var stmts: [WithSpan<Stmt>]
}

public struct Param: Hashable {
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

public struct VarDecl: Equatable {
    public var ident: WithSpan<String>
    public var type: WithSpan<Type>?
    public var value: WithSpan<Expr>
}

public enum Stmt: Equatable {
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

public struct IfStmt: Equatable {
    public indirect enum ElseBlock: Equatable {
        case elseIf(WithSpan<IfStmt>)
        case `else`([WithSpan<Stmt>])
    }

    public var condition: WithSpan<Expr>
    public var ifBlock: [WithSpan<Stmt>]
    public var `else`: ElseBlock?

    public var elseBlocks:
        (
            elseIfBlocks: [(condition: WithSpan<Expr>, stmts: [WithSpan<Stmt>])],
            elseBlock: [WithSpan<Stmt>]?
        )
    {
        let elseIfBlocks: [(condition: WithSpan<Expr>, stmts: [WithSpan<Stmt>])]
        let elseBlock: [WithSpan<Stmt>]?
        switch `else` {
            case let .elseIf(elseIfBlock):
                let blocks = elseIfBlock.inner.elseBlocks
                elseIfBlocks =
                    [(elseIfBlock.inner.condition, elseIfBlock.inner.ifBlock)] + blocks.elseIfBlocks
                elseBlock = blocks.elseBlock
            case let .else(block):
                elseIfBlocks = []
                elseBlock = block
            case nil:
                elseIfBlocks = []
                elseBlock = nil
        }
        return (elseIfBlocks, elseBlock)
    }
}

public indirect enum Expr: Equatable {
    case stringLiteral(String)
    case integerLiteral(Int)
    case fnCall(FnCallExpr)
    case ident(String)
    case unaryOp(UnaryOpExpr)
    case binaryOpChain(BinaryOpChainExpr)
    case parenthesizedExpr(WithSpan<Expr>)
    case structInit(StructInitExpr)
    case memberAccess(MemberAccessExpr)
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
                    "\(*fnCall.ident)(\(fnCall.arguments.map(\.inner.description).joined(separator: ", ")))"
            case .ident(let ident):
                return ident
            case .unaryOp(let unaryOp):
                return "\(*unaryOp.op)\(*unaryOp.operand)"
            case .binaryOpChain(let binaryOpChain):
                let chain = binaryOpChain.chain.map { item in
                    "\(*item.operand) \(*item.op)"
                }
                return "\(chain) \(*binaryOpChain.lastOperand)"
            case .parenthesizedExpr(let expr):
                return "(\(*expr))"
            case .structInit(let initExpr):
                return
                    "\(*initExpr.ident) { \(initExpr.fields.inner.map(\.inner.description).joined(separator: ", ")) }"
            case .memberAccess(let memberAccessExpr):
                return "\(*memberAccessExpr.base).\(*memberAccessExpr.memberIdent)"
        }
    }
}

public struct StructInitExpr: Equatable {
    public var ident: WithSpan<String>
    public var fields: WithSpan<[WithSpan<StructInitField>]>
}

public struct StructInitField: CustomStringConvertible, Equatable {
    public var ident: WithSpan<String>
    public var value: WithSpan<Expr>

    public var description: String {
        "\(*ident): \(*value)"
    }
}

public struct MemberAccessExpr: Equatable {
    public var base: WithSpan<Expr>
    public var memberIdent: WithSpan<String>
}

public struct UnaryOpExpr: Equatable {
    public var op: WithSpan<Op>
    public var operand: WithSpan<Expr>
}

/// A chain of binary operators and expressions (e.g. `1 + 2 * 3 / 4`). The ``Parser`` doesn't
/// handle precedence and associativity so this is a flat structure.
public struct BinaryOpChainExpr: Equatable {
    public var chain: [Item]
    public var lastOperand: WithSpan<Expr>

    public var operands: [WithSpan<Expr>] {
        chain.map(\.operand) + [lastOperand]
    }

    public var operators: [WithSpan<Op>] {
        chain.map(\.op)
    }

    public struct Item: Equatable {
        public var operand: WithSpan<Expr>
        public var op: WithSpan<Op>
    }
}

public struct FnCallExpr: Equatable {
    public var ident: WithSpan<String>
    public var arguments: [WithSpan<Expr>]
}

public struct Tuple: Equatable {
    public var elements: [WithSpan<Expr>]
}
