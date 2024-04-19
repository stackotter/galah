public enum Keyword: String {
    case fn
    case `if`
    case `else`
    case `return`
    case `let`
}

public enum Whitespace: Character {
    case space = " "
    case tab = "\t"
    case newLine = "\n"
}

public enum Trivia: Equatable {
    case whitespace(Whitespace)
    case comment(String)
}

public struct Op: Equatable {
    var token: String

    static let assignment = Op(token: "=")
}

extension Op: CustomStringConvertible {
    public var description: String {
        token
    }
}

public enum Token: Equatable {
    case ident(String)
    case leftParen
    case rightParen
    case leftBrace
    case rightBrace
    case colon
    case comma
    case keyword(Keyword)
    case stringLiteral(String)
    case integerLiteral(Int)
    case trivia(Trivia)
    case op(Op)

    public var noun: String {
        switch self {
            case .ident: "an ident"
            case .leftParen: "'('"
            case .rightParen: "')'"
            case .leftBrace: "'{'"
            case .rightBrace: "'}'"
            case .colon: "':'"
            case .comma: "','"
            case let .keyword(keyword): "'\(keyword.rawValue)'"
            case .stringLiteral: "a string literal"
            case .integerLiteral: "an integer literal"
            case let .trivia(trivia):
                switch trivia {
                    case let .whitespace(whitespace):
                        switch whitespace {
                            case .space: "a space"
                            case .tab: "a tab"
                            case .newLine: "a newline"
                        }
                    case .comment: "a comment"
                }
            case let .op(op): "'\(op.token)'"
        }
    }

    /// The size of a token. Its main purpose is for working with ``Location``s, hence the choice
    /// of ``Size/lastLineColumns`` as the measure of width.
    public struct Size: ExpressibleByIntegerLiteral {
        /// The height of the token. An ident only spans 1 line, but a string literal may span many.
        public var lines: Int
        /// The number of columns taken up by the last line of the token. In the case of a
        /// simple token like an ident, this is simply the number of characters in the token.
        public var lastLineColumns: Int

        public init(integerLiteral value: IntegerLiteralType) {
            lines = 1
            lastLineColumns = Int(value)
        }

        public init(columns: Int) {
            self.lines = 1
            self.lastLineColumns = columns
        }

        public init(lines: Int, lastLineColumns: Int) {
            self.lines = lines
            self.lastLineColumns = lastLineColumns
        }

        public init(ofStringLiteral content: String) {
            lines = 1
            // Account for the opening delimiter
            lastLineColumns = 1
            for character in content {
                if character.isNewline {
                    lines += 1
                    lastLineColumns = 0
                } else {
                    lastLineColumns += 1
                }
            }
            // Account for the closing delimiter
            lastLineColumns += 1
        }
    }

    public var size: Size {
        switch self {
            case let .ident(ident): Size(columns: ident.count)
            case .leftParen: 1
            case .rightParen: 1
            case .leftBrace: 1
            case .rightBrace: 1
            case .colon: 1
            case .comma: 1
            case let .keyword(keyword): Size(columns: keyword.rawValue.count)
            case let .stringLiteral(content): Size(ofStringLiteral: content)
            case let .integerLiteral(value): Size(columns: value.description.count)
            case let .trivia(trivia):
                switch trivia {
                    case let .whitespace(whitespace):
                        switch whitespace {
                            case .space, .tab: 1
                            case .newLine: Size(lines: 2, lastLineColumns: 0)
                        }
                    case let .comment(content):
                        Size(columns: content.count + 2)
                }
            case let .op(op): Size(columns: op.token.count)
        }
    }
}
