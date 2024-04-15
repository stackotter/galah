public struct RichToken: Equatable {
    public var token: Token
    public var location: Location

    public init(_ token: Token, at location: Location) {
        self.token = token
        self.location = location
    }
}
