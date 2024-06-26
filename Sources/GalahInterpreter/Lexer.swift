public enum Lexer {
    static let firstIdentChars = Array("_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let identChars = Array("_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    static let digitChars = Array("0123456789")
    static let operatorChars = Array("+-*/><=!%^&|?~")
    static let fixedRepresentationTokens: [Character: Token] = [
        "(": .leftParen,
        ")": .rightParen,
        "{": .leftBrace,
        "}": .rightBrace,
        ":": .colon,
        ",": .comma,
        ".": .period,
    ]

    public static func lex(_ text: String) throws -> [RichToken] {
        var buffer = TextBuffer(text)

        var tokens: [RichToken] = []
        while let c = buffer.next() {
            let location = buffer.location
            if let token = fixedRepresentationTokens[c] {
                tokens.append(RichToken(token, at: location))
            } else if firstIdentChars.contains(c) {
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
                        let escapedChar: Character
                        switch c {
                            case "\\": escapedChar = "\\"
                            case "\"": escapedChar = "\""
                            case "n": escapedChar = "\n"
                            case "t": escapedChar = "\t"
                            case "r": escapedChar = "\r"
                            case "0": escapedChar = "\0"
                            default:
                                throw Diagnostic(
                                    error: "Invalid escape sequence '\\\(c)'",
                                    at: buffer.location.back(1)
                                )
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
                    throw Diagnostic(error: "Unterminated string literal", at: startLocation)
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
            } else if operatorChars.contains(c) {
                var token = String(c)
                while let c = buffer.peek(), operatorChars.contains(c) {
                    buffer.next()
                    token.append(c)
                }
                tokens.append(RichToken(.op(Op(token: token)), at: location))
            } else {
                throw Diagnostic(error: "Unexpected character '\(c)'", at: buffer.location)
            }
        }

        return tokens
    }
}
