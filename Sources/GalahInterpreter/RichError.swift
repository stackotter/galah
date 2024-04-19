public struct RichError: Error, CustomStringConvertible {
    public var message: String
    public var source: Source?

    public enum Source {
        case location(Location)
        case span(Span)
    }

    public var description: String {
        switch source {
            case let .location(location):
                "error:\(location.line):\(location.column): \(message)"
            case let .span(span):
                "error:\(span.shortDescription): \(message)"
            case .none:
                "error: \(message)"
        }
    }

    public init(_ message: String, at location: Location? = nil) {
        self.message = message
        self.source = location.map(Source.location)
    }

    public init(_ message: String, at span: Span) {
        self.message = message
        self.source = .span(span)
    }
}
