public enum Keyword: String {
    case fn
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
}

public enum Lexer {
    static let firstIdentChars = "_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    static let identChars = "_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    static let digitChars = "0123456789"

    public static func lex(_ text: String) throws -> [Token] {
        var buffer = TextBuffer(text)

        var tokens: [Token] = []
        while let c = buffer.next() {
            if firstIdentChars.contains(c) {
                var ident = String(c)
                while let c = buffer.peek(), identChars.contains(c) {
                    buffer.next()
                    ident.append(c)
                }

                if let keyword = Keyword(rawValue: ident) {
                    tokens.append(.keyword(keyword))
                } else {
                    tokens.append(.ident(ident))
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
                    } else {
                        content.append(c)
                    }
                }

                if buffer.peek() != "\"" {
                    throw RichError("Unterminated string literal", at: startLocation)
                } else {
                    buffer.next()
                    tokens.append(.stringLiteral(content))
                }
            } else if c == "(" {
                tokens.append(.leftParen)
            } else if c == ")" {
                tokens.append(.rightParen)
            } else if c == "{" {
                tokens.append(.leftBrace)
            } else if c == "}" {
                tokens.append(.rightBrace)
            } else if c == ":" {
                tokens.append(.colon)
            } else if c == "," {
                tokens.append(.comma)
            } else if c == " " || c == "\t" || c == "\r" || c == "\n" {
                continue
            } else {
                throw RichError("Unexpected character '\(c)'", at: buffer.location)
            }
        }

        return tokens
    }
}
