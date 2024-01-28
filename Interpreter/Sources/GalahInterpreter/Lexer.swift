public enum Keyword: String {
    case fn
    case `if`
    case `else`
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
            lastLineColumns = 0
            for character in content {
                if character.isNewline {
                    lines += 1
                    lastLineColumns = 0
                } else {
                    lastLineColumns += 1
                }
            }
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
        }
    }
}

public struct RichToken: Equatable {
    public var token: Token
    public var location: Location

    public init(_ token: Token, at location: Location) {
        self.token = token
        self.location = location
    }
}

public enum Lexer {
    static let firstIdentChars = Array("_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let identChars = Array("_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    static let digitChars = Array("0123456789")

    public static func lex(_ text: String) throws -> [RichToken] {
        var buffer = TextBuffer(text)

        var tokens: [RichToken] = []
        while let c = buffer.next() {
            let location = buffer.location
            if firstIdentChars.contains(c) {
                var ident = String(c)
                while let c = buffer.peek(), identChars.contains(c) {
                    buffer.next()
                    ident.append(c)
                }

                if let keyword = Keyword(rawValue: ident) {
                    tokens.append(RichToken(.keyword(keyword), at: location))
                } else {
                    tokens.append(RichToken(.ident(ident), at: location))
                }
            } else if c == "\"" {
                let startLocation = buffer.location
                var escapeNextChar = false
                var content = ""
                while let c = buffer.peek(), c != "\"" || escapeNextChar {
                    buffer.next()
                    if c == "\\" && !escapeNextChar {
                        escapeNextChar = true
                    } else if escapeNextChar {
                        // TODO: Use a switch expression here once I've updated my tree sitter grammars
                        //   and they don't freak out about switch expressions anymore.
                        let escapedChar: Character
                        switch c {
                            case "\\": escapedChar = "\\"
                            case "\"": escapedChar = "\""
                            case "n": escapedChar = "\n"
                            case "t": escapedChar = "\t"
                            case "r": escapedChar = "\r"
                            case "0": escapedChar = "\0"
                            default: throw RichError("Invalid escape sequence '\\\(c)'", at: buffer.location.back(1))
                        }
                        escapeNextChar = false
                        content.append(escapedChar)
                    } else if c.isNewline {
                        content.append("\n")
                    } else {
                        content.append(c)
                    }
                }

                if buffer.peek() != "\"" {
                    throw RichError("Unterminated string literal", at: startLocation)
                } else {
                    buffer.next()
                    tokens.append(RichToken(.stringLiteral(content), at: location))
                }
            } else if let digit = digitChars.firstIndex(of: c) {
                var value = digit
                while let c = buffer.peek(), let digit = digitChars.firstIndex(of: c) {
                    buffer.next()
                    value *= 10
                    value += digit
                }
                tokens.append(RichToken(.integerLiteral(value), at: location))
            } else if c == "(" {
                tokens.append(RichToken(.leftParen, at: location))
            } else if c == ")" {
                tokens.append(RichToken(.rightParen, at: location))
            } else if c == "{" {
                tokens.append(RichToken(.leftBrace, at: location))
            } else if c == "}" {
                tokens.append(RichToken(.rightBrace, at: location))
            } else if c == ":" {
                tokens.append(RichToken(.colon, at: location))
            } else if c == "," {
                tokens.append(RichToken(.comma, at: location))
            } else if let whitespace = Whitespace(rawValue: c) {
                tokens.append(RichToken(.trivia(.whitespace(whitespace)), at: location))
            } else if c == "\r\n" {
                tokens.append(RichToken(.trivia(.whitespace(.newLine)), at: location))
            } else if c == "/" && buffer.peek() == "/" {
                buffer.next()
                var content = ""
                while let c = buffer.peek(), !c.isNewline {
                    buffer.next()
                    content.append(c)
                }
                tokens.append(RichToken(.trivia(.comment(content)), at: location))
            } else {
                throw RichError("Unexpected character '\(c)'", at: buffer.location)
            }
        }

        return tokens
    }
}
