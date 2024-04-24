prefix operator *

public enum Span: Equatable, Hashable {
    case source(start: Location, end: Location)
    case builtin

    public var shortDescription: String {
        switch self {
            case let .source(start, end):
                return "\(start.line):\(start.column)~\(end.line):\(end.column)"
            case .builtin:
                return "<builtin>"
        }
    }
}

@dynamicMemberLookup
public struct WithSpan<Inner> {
    public var inner: Inner
    public var span: Span

    public subscript<U>(dynamicMember keyPath: WritableKeyPath<Inner, U>) -> U {
        get {
            inner[keyPath: keyPath]
        }
        set {
            inner[keyPath: keyPath] = newValue
        }
    }

    public init(_ inner: Inner, _ span: Span) {
        self.inner = inner
        self.span = span
    }

    public init(builtin inner: Inner) {
        self.inner = inner
        self.span = .builtin
    }

    public func map<U>(_ map: (Inner) -> U) -> WithSpan<U> {
        WithSpan<U>(map(inner), span)
    }
}

extension WithSpan: Equatable where Inner: Equatable {
    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.inner == rhs.inner
    }
}

extension WithSpan: Hashable where Inner: Hashable {
    public func hash(into hasher: inout Hasher) {
        inner.hash(into: &hasher)
    }
}

prefix func * <Inner>(_ span: WithSpan<Inner>) -> Inner {
    span.inner
}
