public struct RichError: Error, CustomStringConvertible {
    public var message: String
    public var source: Source?

    public enum Source {
        case location(Location)
        case span(Span)
    }

    public var errorLine: String {
        switch source {
            case let .location(location):
                "error:\(location.line):\(location.column): \(message)"
            case let .span(span):
                "error:\(span.shortDescription): \(message)"
            case .none:
                "error: \(message)"
        }
    }

    public var description: String {
        errorLine
    }

    /// - Precondition: `maxCodeLines` must be at least 1
    public func formatted(withSourceCode sourceCode: String, maxCodeLines: Int = 5) -> String {
        let annotation = annotate(sourceCode, maxCodeLines: maxCodeLines) ?? ""
        return [
            errorLine,
            annotation
        ].joined(separator: "\n")
    }

    /// - Precondition: `maxCodeLines` must be at least 1
    public func annotate(_ sourceCode: String, maxCodeLines: Int) -> String? {
        precondition(maxCodeLines >= 1, "maxCodeLines must be at least 1")

        let startLocation: Location
        let location: Location?
        switch source {
            case let .location(start):
                startLocation = start
                location = nil
            case let .span(.source(start, end)):
                startLocation = start
                location = end
            case .span(.builtin), .none:
                return nil
        }

        let endLocation = location ?? startLocation

        // Convert line numbering to 0-indexed lines
        let startLine = startLocation.line - 1
        let endLine = endLocation.line - 1

        let lines = sourceCode.split(separator: "\n")
        let errorLines = Array(lines[startLine...endLine])
        let indent = "    "
        if errorLines.count > 1 {
            return errorLines[..<maxCodeLines]
                .map { line in
                    indent + line
                }
                .joined(separator: "\n")
                + "\n\(indent)..."
        } else {
            let startColumn = startLocation.column
            let annotationWidth = endLocation.column - startLocation.column - 1
            let annotation =
                (startColumn > 1 ? String(repeating: " ", count: startLocation.column - 1) : "")
                + "^"
                + (annotationWidth > 0 ? String(repeating: "~", count: annotationWidth) : "")
            return (
                indent + errorLines[0] + "\n"
                + indent + annotation
            )
        }
    }

    public init(_ message: String, at location: Location?) {
        self.message = message
        self.source = location.map(Source.location)
    }

    public init(_ message: String, at span: Span) {
        self.message = message
        self.source = .span(span)
    }
}
