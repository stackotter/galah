public struct Diagnostic: Error, CustomStringConvertible {
    public var level: Level
    public var message: String
    public var source: Source?

    public enum Level: String, CustomStringConvertible {
        case warning
        case error

        public var description: String {
            rawValue
        }
    }

    public enum Source {
        case location(Location)
        case span(Span)
    }

    public init(warning message: String, at location: Location?) {
        level = .warning
        self.message = message
        self.source = location.map(Source.location)
    }

    public init(warning message: String, at span: Span) {
        level = .warning
        self.message = message
        self.source = .span(span)
    }

    public init(error message: String, at location: Location?) {
        level = .error
        self.message = message
        self.source = location.map(Source.location)
    }

    public init(error message: String, at span: Span) {
        level = .error
        self.message = message
        self.source = .span(span)
    }

    public var diagnosticLine: String {
        switch source {
            case let .location(location):
                "\(level):\(location.line):\(location.column): \(message)"
            case let .span(span):
                "\(level):\(span.shortDescription): \(message)"
            case .none:
                "\(level): \(message)"
        }
    }

    public var description: String {
        diagnosticLine
    }

    /// - Precondition: `maxCodeLines` must be at least 1
    public func formatted(withSourceCode sourceCode: String, maxCodeLines: Int = 5) -> String {
        let annotation = annotate(sourceCode, maxCodeLines: maxCodeLines) ?? ""
        return [
            diagnosticLine,
            annotation,
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

        let lines = sourceCode.split(separator: "\n", omittingEmptySubsequences: false)
        let errorLines = Array(lines[startLine...endLine])
        let indent = "    "
        if errorLines.count > 1 {
            let ellipsis =
                if maxCodeLines < errorLines.count {
                    "\n\(indent)..."
                } else {
                    ""
                }
            return errorLines[0..<min(maxCodeLines, errorLines.count)]
                .map { line in
                    indent + line
                }
                .joined(separator: "\n")
                + ellipsis
        } else {
            let startColumn = startLocation.column
            let annotationWidth = endLocation.column - startLocation.column - 1
            let annotation =
                (startColumn > 1 ? String(repeating: " ", count: startLocation.column - 1) : "")
                + "^"
                + (annotationWidth > 0 ? String(repeating: "~", count: annotationWidth) : "")
            return
                (indent + errorLines[0] + "\n"
                + indent + annotation)
        }
    }
}

public struct WithDiagnostics<Inner> {
    public var inner: Inner
    public var diagnostics: [Diagnostic]

    public init(_ inner: Inner, _ diagnostics: [Diagnostic] = []) {
        self.inner = inner
        self.diagnostics = diagnostics
    }

    public func map<T>(_ map: (Inner) -> T) -> WithDiagnostics<T> {
        WithDiagnostics<T>(
            map(inner),
            diagnostics
        )
    }
}

extension [WithDiagnostics<CheckedAST.Fn>] {
    public func collect() -> WithDiagnostics<[CheckedAST.Fn]> {
        WithDiagnostics(
            map(\.inner),
            map(\.diagnostics).flatMap { $0 }
        )
    }
}
