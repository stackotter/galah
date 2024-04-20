public struct Location: Equatable, Hashable {
    public var line: Int
    public var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    /// Gets the location of the character located back `n` non-newline characters.
    public func back(_ n: Int) -> Location {
        assert(column >= n, "can't go back \(n) characters from column \(column)")
        var location = self
        location.column -= n
        return location
    }

    public static func + (_ lhs: Self, _ rhs: Token.Size) -> Self {
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

extension Location {
    public func span(until endLocation: Location) -> Span {
        Span.source(start: self, end: endLocation)
    }
}
