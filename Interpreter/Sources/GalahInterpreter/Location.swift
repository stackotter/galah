public struct Location: Equatable {
    public var line: Int
    public var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    /// Gets the location of the character located back `n` non-newline characters.
    public func back(_ n: Int) -> Location {
        // TODO: Should this validate?
        var location = self
        location.column -= n
        return location
    }

    public static func +(_ lhs: Self, _ rhs: Token.Size) -> Self {
        var result = lhs
        result.line += rhs.lines - 1
        if rhs.lines == 1 {
            result.column += rhs.lastLineColumns
        } else {
            result.column = rhs.lastLineColumns
        }
        return result
    }
}
