public struct RichError: Error, CustomStringConvertible {
    public var message: String
    public var location: Location

    public var description: String {
        """
        error:\(location.line):\(location.column): \(message)
        """
    }

    public init(_ message: String, at location: Location) {
        self.message = message
        self.location = location
    }
}
