public struct RichToken: Equatable {
    public var token: Token
    public var location: Location

    public var endLocation: Location {
        location + token.size
    }

    public var span: Span {
        location.span(until: endLocation)
    }

    public init(_ token: Token, at location: Location) {
        self.token = token
        self.location = location
    }
}
