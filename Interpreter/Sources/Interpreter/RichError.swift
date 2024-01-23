public struct RichError: Error, CustomStringConvertible {
    public var message: String
    public var location: Location?

    public var description: String {
        if let location {
            "error:\(location.line):\(location.column): \(message)"
        } else {
            "error: \(message)"
        }
    }

    public init(_ message: String, at location: Location? = nil) {
        self.message = message
        self.location = location
    }
}
