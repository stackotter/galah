public struct BuiltinFn {
    public var ident: String
    private var storage: Storage

    private enum Storage {
        case fn0(() throws -> Any)
        case fn1((Any) throws -> Any)
        case fn2((Any, Any) throws -> Any)
        case variadic(([Any]) throws -> Any)
    }

    public var arity: Int? {
        switch self.storage {
            case .fn0: 0
            case .fn1: 1
            case .fn2: 2
            case .variadic: nil
        }
    }

    public init<R>(_ ident: String, _ fn: @escaping () -> R) {
        self.ident = ident
        self.storage = .fn0 {
            fn()
        }
    }

    public init<A, R>(_ ident: String, _ fn: @escaping (A) -> R) {
        self.ident = ident
        self.storage = .fn1 { a in
            return fn(try Self.cast(a, for: ident))
        }
    }

    public init<A, B, R>(_ ident: String, _ fn: @escaping (A, B) -> R) {
        self.ident = ident
        self.storage = .fn2 { a, b in
            return fn(
                try Self.cast(a, for: ident),
                try Self.cast(b, for: ident)
            )
        }
    }

    public init<T, R>(variadic ident: String, _ fn: @escaping ([T]) -> R) {
        self.ident = ident
        self.storage = .variadic { arguments in
            return fn(
                try arguments.map { try Self.cast($0, for: ident) }
            )
        }
    }

    public func call(with arguments: [Any]) throws -> Any {
        if let arity {
            guard arity == arguments.count else {
                throw RichError("'\(ident)' expects \(arity) arguments, got \(arguments.count)")
            }
        }

        return switch self.storage {
            case let .fn0(fn):
                try fn()
            case let .fn1(fn):
                try fn(arguments[0])
            case let .fn2(fn):
                try fn(arguments[0], arguments[1])
            case let .variadic(fn):
                try fn(arguments)
        }
    }

    private static func cast<T>(_ argument: Any, for ident: String) throws -> T {
        guard let argument = argument as? T else {
            throw RichError("'\(ident)' expects argument 1 to be of type '\(T.self)', got '\(type(of: argument))'")
        }
        return argument
    }
}
