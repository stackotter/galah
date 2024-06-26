public struct BuiltinFn {
    private var storage: Storage
    public var signature: FnSignature

    private enum Storage {
        case fn0(() throws -> Any)
        case fn1((Any) throws -> Any)
        case fn2((Any, Any) throws -> Any)
        case unaryOp((Any) throws -> Any)
        case binaryOp((Any, Any) throws -> Any)
    }

    public var arity: Int? {
        switch storage {
            case .fn0: 0
            case .fn1: 1
            case .fn2: 2
            case .unaryOp: 1
            case .binaryOp: 2
        }
    }

    public init(_ ident: String, _ fn: @escaping () -> Void) {
        storage = .fn0 {
            fn()
        }
        signature = FnSignature(builtin: ident, params: [], returnType: .void)
    }

    public init<R: GalahRepresentable>(_ ident: String, _ fn: @escaping () -> R) {
        storage = .fn0 {
            fn()
        }
        signature = FnSignature(builtin: ident, params: [], returnType: R.type)
    }

    public init<A: GalahRepresentable, R: GalahRepresentable>(
        _ ident: String,
        paramLabel: String? = nil,
        _ fn: @escaping (A) -> R
    ) {
        storage = .fn1 { a in
            return fn(Self.cast(a, for: ident))
        }
        signature = FnSignature(
            builtin: ident,
            params: [
                Param(
                    ident: WithSpan(builtin: paramLabel ?? "param"),
                    type: WithSpan(builtin: A.type)
                )
            ],
            returnType: R.type
        )
    }

    public init<A: GalahRepresentable, B: GalahRepresentable, R: GalahRepresentable>(
        _ ident: String,
        paramLabels: (String, String)? = nil,
        _ fn: @escaping (A, B) -> R
    ) {
        storage = .fn2 { a, b in
            return fn(
                Self.cast(a, for: ident),
                Self.cast(b, for: ident)
            )
        }
        let paramLabels = paramLabels ?? ("param1", "param2")
        signature = FnSignature(
            builtin: ident,
            params: [
                Param(
                    ident: WithSpan(builtin: paramLabels.0),
                    type: WithSpan(builtin: A.type)
                ),
                Param(
                    ident: WithSpan(builtin: paramLabels.1),
                    type: WithSpan(builtin: B.type)
                ),
            ],
            returnType: R.type
        )
    }

    public init<Operand: GalahRepresentable, R: GalahRepresentable>(
        unaryOp ident: String,
        paramLabel: String? = nil,
        _ fn: @escaping (Operand) -> R
    ) {
        storage = .unaryOp { operand in
            return fn(
                Self.cast(operand, for: ident)
            )
        }
        signature = FnSignature(
            builtin: ident,
            params: [
                Param(
                    ident: WithSpan(builtin: paramLabel ?? "operand"),
                    type: WithSpan(builtin: Operand.type)
                )
            ],
            returnType: R.type
        )
    }

    public init<Left: GalahRepresentable, Right: GalahRepresentable, R: GalahRepresentable>(
        binaryOp ident: String,
        paramLabels: (String, String)? = nil,
        _ fn: @escaping (Left, Right) -> R
    ) {
        storage = .binaryOp { left, right in
            return fn(
                Self.cast(left, for: ident),
                Self.cast(right, for: ident)
            )
        }
        let paramLabels = paramLabels ?? ("lhs", "rhs")
        signature = FnSignature(
            builtin: ident,
            params: [
                Param(
                    ident: WithSpan(builtin: paramLabels.0),
                    type: WithSpan(builtin: Left.type)
                ),
                Param(
                    ident: WithSpan(builtin: paramLabels.1),
                    type: WithSpan(builtin: Right.type)
                ),
            ],
            returnType: R.type
        )
    }

    public init<A: GalahRepresentable>(
        _ ident: String,
        paramLabel: String? = nil,
        _ fn: @escaping (A) -> Void
    ) {
        storage = .fn1 { a in
            return fn(Self.cast(a, for: ident))
        }
        signature = FnSignature(
            builtin: ident,
            params: [
                Param(
                    ident: WithSpan(builtin: paramLabel ?? "param"),
                    type: WithSpan(builtin: A.type)
                )
            ],
            returnType: .void
        )
    }

    public init(
        _ ident: String,
        paramLabel: String? = nil,
        _ fn: @escaping (Any) -> Void
    ) {
        storage = .fn1 { a in
            return fn(Self.cast(a, for: ident))
        }
        signature = FnSignature(
            builtin: ident,
            params: [
                Param(
                    ident: WithSpan(builtin: paramLabel ?? "param"),
                    type: WithSpan(builtin: .any)
                )
            ],
            returnType: .void
        )
    }

    public init<A: GalahRepresentable, B: GalahRepresentable>(
        _ ident: String,
        paramLabels: (String, String)? = nil,
        _ fn: @escaping (A, B) -> Void
    ) {
        storage = .fn2 { a, b in
            return fn(
                Self.cast(a, for: ident),
                Self.cast(b, for: ident)
            )
        }
        let paramLabels = paramLabels ?? ("param1", "param2")
        signature = FnSignature(
            builtin: ident,
            params: [
                Param(
                    ident: WithSpan(builtin: paramLabels.0),
                    type: WithSpan(builtin: A.type)
                ),
                Param(
                    ident: WithSpan(builtin: paramLabels.1),
                    type: WithSpan(builtin: B.type)
                ),
            ],
            returnType: .void
        )
    }

    public init<Operand: GalahRepresentable>(
        unaryOp ident: String,
        paramLabel: String? = nil,
        _ fn: @escaping (Operand) -> Void
    ) {
        storage = .unaryOp { operand in
            return fn(
                Self.cast(operand, for: ident)
            )
        }
        signature = FnSignature(
            builtin: ident,
            params: [
                Param(
                    ident: WithSpan(builtin: paramLabel ?? "operand"),
                    type: WithSpan(builtin: Operand.type)
                )
            ],
            returnType: .void
        )
    }

    public init<Left: GalahRepresentable, Right: GalahRepresentable>(
        binaryOp ident: String,
        paramLabels: (String, String)? = nil,
        _ fn: @escaping (Left, Right) -> Void
    ) {
        storage = .binaryOp { left, right in
            return fn(
                Self.cast(left, for: ident),
                Self.cast(right, for: ident)
            )
        }
        let paramLabels = paramLabels ?? ("lhs", "rhs")
        signature = FnSignature(
            builtin: ident,
            params: [
                Param(
                    ident: WithSpan(builtin: paramLabels.0),
                    type: WithSpan(builtin: Left.type)
                ),
                Param(
                    ident: WithSpan(builtin: paramLabels.1),
                    type: WithSpan(builtin: Right.type)
                ),
            ],
            returnType: .void
        )
    }

    public func call(with arguments: [Any]) throws -> Any {
        if let arity {
            guard arity == arguments.count else {
                throw Diagnostic(
                    error:
                        "'\(signature.ident)' expects \(arity) arguments, got \(arguments.count)",
                    at: .builtin
                )
            }
        }

        return switch self.storage {
            case let .fn0(fn):
                try fn()
            case let .fn1(fn):
                try fn(arguments[0])
            case let .fn2(fn):
                try fn(arguments[0], arguments[1])
            case let .unaryOp(fn):
                try fn(arguments[0])
            case let .binaryOp(fn):
                try fn(arguments[0], arguments[1])
        }
    }

    private static func cast<T>(_ argument: Any, for ident: String) -> T {
        assert(
            type(of: argument) == T.self,
            "'\(ident)' expects argument 1 to be of type '\(T.self)', got '\(type(of: argument))'"
        )
        return argument as! T
    }
}
