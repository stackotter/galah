import UtilityMacros

public struct CheckedAST {
    public var typeContext: TypeContext
    public var builtinFns: [BuiltinFn]
    public var fns: [Fn]

    public struct TypeContext {
        public let builtinTypes: [BuiltinType]
        public let structs: [CheckedAST.Struct]

        public let void: CheckedAST.TypeIndex
        public let int: CheckedAST.TypeIndex
        public let string: CheckedAST.TypeIndex

        public let voidIdent: String
        public let intIdent: String
        public let stringIdent: String

        static func create(
            builtinTypes: [BuiltinType],
            structs: [CheckedAST.Struct]
        ) -> Result<TypeContext, [Diagnostic]> {
            let voidIdent = "Void"
            let intIdent = "Int"
            let stringIdent = "String"

            return #result {
                (
                    void: CheckedAST.TypeIndex,
                    int: CheckedAST.TypeIndex,
                    string: CheckedAST.TypeIndex
                ) in
                void <- Self.builtin(named: voidIdent, from: builtinTypes)
                int <- Self.builtin(named: intIdent, from: builtinTypes)
                string <- Self.builtin(named: stringIdent, from: builtinTypes)
                return Result<_, [Diagnostic]>.success(
                    TypeContext(
                        builtinTypes: builtinTypes,
                        structs: structs,
                        void: void,
                        int: int,
                        string: string,
                        voidIdent: voidIdent,
                        intIdent: intIdent,
                        stringIdent: stringIdent
                    )
                )
            }
        }

        public static func builtin(
            named name: String,
            from builtinTypes: [BuiltinType]
        ) -> Result<CheckedAST.TypeIndex, [Diagnostic]> {
            guard let index = builtinTypes.firstIndex(where: { $0.ident == name }) else {
                return .failure([
                    Diagnostic(
                        error: "Expected to find builtin type named '\(name)'",
                        at: .builtin
                    )
                ])
            }

            return .success(.builtin(index))
        }

        public func describe(_ typeIndex: CheckedAST.TypeIndex) -> String {
            switch typeIndex {
                case let .builtin(index):
                    builtinTypes[index].ident
                case let .struct(index):
                    structs[index].ident
            }
        }

        public func checkType(
            _ type: WithSpan<Type>
        ) -> Result<CheckedAST.TypeIndex, [Diagnostic]> {
            checkType(type.inner, span: type.span)
        }

        public func checkType(
            _ type: Type,
            span: Span? = nil
        ) -> Result<CheckedAST.TypeIndex, [Diagnostic]> {
            Self.checkType(
                type,
                span: span,
                builtinTypeIdents: builtinTypes.lazy.map(\.ident),
                structIdents: structs.lazy.map(\.ident)
            )
        }

        public static func checkType<
            BuiltinIterator: Sequence<String>, StructIterator: Sequence<String>
        >(
            _ type: Type,
            span: Span?,
            builtinTypeIdents: BuiltinIterator,
            structIdents: StructIterator
        ) -> Result<CheckedAST.TypeIndex, [Diagnostic]> {
            let typeName = type.description
            if let builtinIndex = builtinTypeIdents.enumerated().first(where: {
                $0.element == typeName
            }).map(\.offset) {
                return .success(.builtin(builtinIndex))
            } else if let structIndex = structIdents.enumerated().first(where: {
                $0.element == typeName
            }).map(\.offset) {
                return .success(.struct(structIndex))
            } else {
                let message = "No such type '\(typeName)'"
                if let span {
                    return .failure([Diagnostic(error: message, at: span)])
                } else {
                    return .failure([Diagnostic(error: message, at: nil)])
                }
            }
        }
    }

    public struct Typed<Inner> {
        public var inner: Inner
        public var type: TypeIndex

        public init(_ inner: Inner, _ type: TypeIndex) {
            self.inner = inner
            self.type = type
        }

        public func map<U>(_ map: (Inner) throws -> U) rethrows -> Typed<U> {
            Typed<U>(
                try map(inner),
                type
            )
        }
    }

    public class Boxed<Inner> {
        public var inner: Inner

        public init(_ inner: Inner) {
            self.inner = inner
        }

        public static prefix func * (_ boxed: Boxed<Inner>) -> Inner {
            boxed.inner
        }
    }

    public struct Struct {
        public var ident: String
        public var fields: [Field]
    }

    public enum TypeIndex: Equatable, Hashable {
        case builtin(Int)
        case `struct`(Int)
    }

    public struct Field: Hashable {
        public var ident: String
        public var type: TypeIndex
    }

    public struct FnSignature {
        public var ident: String
        public var params: [Param]
        public var returnType: TypeIndex
    }

    public struct Param: Equatable {
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
        case structInit(StructInitExpr)
        case fieldAccess(FieldAccessExpr)
    }

    public enum FnId {
        case builtin(index: Int)
        case userDefined(index: Int)
    }

    public struct FnCallExpr {
        public var id: FnId
        public var arguments: [Typed<Expr>]
    }

    public struct StructInitExpr {
        public var structId: Int
        public var fields: [Typed<Expr>]
    }

    public struct FieldAccessExpr {
        public var base: Typed<Boxed<Expr>>
        public var fieldIndex: Int
    }

    public func fn(named ident: String, withParamTypes paramTypes: [TypeIndex]) -> Fn? {
        fns.first { fn in
            fn.signature.ident == ident && fn.signature.params.map(\.type) == paramTypes
        }
    }
}
