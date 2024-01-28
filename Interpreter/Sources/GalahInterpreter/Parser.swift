public struct Parser {
    let tokens: [RichToken]
    var index = 0
    var previousIndex = 0

    public static func parse(_ tokens: [RichToken]) throws -> AST {
        let parser = Parser(tokens)
        return try parser.parse()
    }

    private init(_ tokens: [RichToken]) {
        self.tokens = tokens
    }

    private consuming func parse() throws -> AST {
        var decls: [Decl] = []

        skipTrivia()
        while let token = peek() {
            switch token {
                case .keyword(.fn):
                    decls.append(.fn(try parseFnDecl()))
                default:
                    throw RichError("Unexpected token '\(token)' while parsing top-level declarations", at: location())
            }
            skipTrivia()
        }

        return AST(decls: decls)
    }

    private mutating func parseFnDecl() throws -> FnDecl {
        try expect(.keyword(.fn))
        try expectWhitespaceSkippingTrivia()

        let ident = try expectIdent()

        try expect(.leftParen)
        skipTrivia()
        
        var params: [Param] = []
        while let token = peek(), token != .rightParen {
            let ident = try expectIdent()
            skipTrivia()

            let type: String?
            if peek() == .colon {
                next()
                skipTrivia()
                type = try expectIdent()
                skipTrivia()
            } else {
                type = nil
            }

            params.append(Param(ident: ident, type: type))

            guard peek() == .comma else {
                break
            }

            next()
            skipTrivia()
        }
        try expect(.rightParen)

        skipTrivia()

        let stmts = try parseCodeBlock()
        return FnDecl(ident: ident, params: params, stmts: stmts)
    }

    private mutating func parseStmt() throws -> Stmt {
        if peek() == .keyword(.if) {
            .if(try parseIfStmt())
        } else {
            .expr(try parseExpr())
        }
    }

    private mutating func parseIfStmt() throws -> IfStmt {
        try expect(.keyword(.if))
        try expectWhitespaceSkippingTrivia()
        let condition = try parseExpr()
        skipTrivia()
        let ifBlock = try parseCodeBlock()
        skipTrivia()

        let `else`: IfStmt.ElseBlock?
        if peek() == .keyword(.else) {
            next()
            skipTrivia()

            switch peek() {
                case .keyword(.if):
                    `else` = .elseIf(try parseIfStmt())
                case .leftBrace:
                    `else` = .else(try parseCodeBlock())
                case let token:
                    throw RichError("Expected 'if' or '{', got \(token?.noun ?? "EOF")", at: peekLocation())
            }
        } else {
            `else` = nil
        }
        
        return IfStmt(condition: condition, ifBlock: ifBlock, else: `else`)
    }

    private mutating func parseCodeBlock() throws -> [Stmt] {
        try expect(.leftBrace)
        skipTrivia()
        var stmts: [Stmt] = []
        while let token = peek(), token != .rightBrace {
            stmts.append(try parseStmt())
            do {
                try expectNewLineSkippingTrivia()
            } catch {
                break
            }
        }
        try expect(.rightBrace)
        return stmts
    }

    private mutating func parseExpr() throws -> Expr {
        guard let token = next() else {
            throw RichError("Unexpected EOF while parsing expression", at: location())
        }

        return switch token {
            case let .ident(ident):
                if peek() == .leftParen {
                    .fnCall(
                        FnCallExpr(
                            ident: ident,
                            arguments: try parseTuple().elements
                        )
                    )
                } else {
                    .ident(ident)
                }
            case let .stringLiteral(value):
                .stringLiteral(value)
            case let .integerLiteral(value):
                .integerLiteral(value)
            default:
                throw RichError("Unexpected token while parsing expression: \(token)", at: location())
        }
    }

    private mutating func parseTuple() throws -> Tuple {
        try expect(.leftParen)
        skipTrivia()

        var elements: [Expr] = []
        while let token = peek(), token != .rightParen {
            elements.append(try parseExpr())
            skipTrivia()

            guard peek() == .comma else {
                break
            }

            next()
            skipTrivia()
        }

        skipTrivia()
        try expect(.rightParen)

        return Tuple(elements: elements)
    }

    private func peek() -> Token? {
        if index < tokens.count {
            return tokens[index].token
        } else {
            return nil
        }
    }

    /// The location of the token most recently returned by ``Parser/next``.
    private func location() -> Location {
        return tokens[previousIndex].location
    }

    /// The location of the token that would be returned by ``Parser/peek``. If at the
    /// end of the file, the location after the file's last token is given.
    private func peekLocation() -> Location {
        location() + tokens[previousIndex].token.size
    }

    @discardableResult
    private mutating func next() -> Token? {
        let token = peek()
        if token != nil {
            previousIndex = index
            index += 1
        }
        return token
    }

    private mutating func skipTrivia() {
        while case .trivia = peek() {
            next()
        }
    }

    private mutating func expectWhitespaceSkippingTrivia() throws {
        var foundWhitespace = false
        while case let .trivia(trivia) = peek() {
            next()
            if case .whitespace = trivia {
                foundWhitespace = true
            }
        }
        guard foundWhitespace else {
            let token = peek()
            throw RichError("Expected whitespace, got \(token?.noun ?? "an EOF")", at: peekLocation())
        }
    }

    private mutating func expectNewLineSkippingTrivia() throws {
        var foundNewLine = false
        while case let .trivia(trivia) = peek() {
            next()
            if trivia == .whitespace(.newLine) {
                foundNewLine = true
            }
        }
        guard foundNewLine else {
            let token = peek()
            throw RichError("Expected a newline, got \(token?.noun ?? "an EOF")", at: peekLocation())
        }
    }

    private mutating func expect(_ token: Token) throws {
        let nextToken = next()
        guard let nextToken = nextToken, nextToken == token else {
            throw RichError("Expected \(token.noun), got \(nextToken?.noun ?? "an EOF")", at: location())
        }
    }

    private mutating func expectIdent() throws -> String {
        let token = next()
        guard case let .ident(ident) = token else {
            throw RichError("Expected an ident, got \(token?.noun ?? "an EOF")", at: location())
        }
        return ident
    }
}
