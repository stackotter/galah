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
            try expect(.colon)
            skipTrivia()

            let type = try parseType()
            params.append(Param(ident: ident, type: type))

            guard peek() == .comma else {
                break
            }

            next()
            skipTrivia()
        }
        try expect(.rightParen)

        skipTrivia()

        let returnType: Type?
        if case let .op(op) = peek(), op.token == "->" {
            next()
            skipTrivia()
            returnType = try parseType()
            skipTrivia()
        } else {
            returnType = nil
        }

        let stmts = try parseCodeBlock()
        return FnDecl(
            ident: ident,
            params: params,
            returnType: returnType,
            stmts: stmts
        )
    }

    private mutating func parseStmt() throws -> Stmt {
        if peek() == .keyword(.if) {
            return .if(try parseIfStmt())
        } else if peek() == .keyword(.return) {
            return .return(try parseReturnStmt())
        } else if peek() == .keyword(.let) {
            return .let(try parseLetStmt())
        } else {
            return .expr(try parseExpr())
        }
    }

    private mutating func parseReturnStmt() throws -> Expr? {
        try expect(.keyword(.return))
        while let token = peek(), case let .trivia(trivia) = token, trivia != .whitespace(.newLine) {
            next()
        }
        if peek() == .trivia(.whitespace(.newLine)) {
            return nil
        } else {
            return try parseExpr()
        }
    }

    private mutating func parseLetStmt() throws -> VarDecl {
        try expect(.keyword(.let))
        try expectWhitespaceSkippingTrivia()

        let ident = try expectIdent()
        skipTrivia()

        let type: Type?
        if peek() == .colon {
            next()
            skipTrivia()
            type = try parseType()
            skipTrivia()
        } else {
            type = nil
        }

        try expect(.op(.assignment))
        skipTrivia()

        let value = try parseExpr()
        return VarDecl(
            ident: ident,
            type: type,
            value: value
        )
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
            let stmt = try parseStmt()
            stmts.append(stmt)
            if !stmt.endsWithCodeBlock {
                do {
                    try expectNewLineSkippingTrivia()
                } catch {
                    break
                }
            } else {
                skipTrivia()
            }
        }
        try expect(.rightBrace)
        return stmts
    }

    private mutating func parseExpr() throws -> Expr {
        guard let token = next() else {
            throw RichError("Unexpected EOF while parsing expression", at: location())
        }

        let expr: Expr
        switch token {
            case let .ident(ident):
                if peek() == .leftParen {
                    expr = .fnCall(
                        FnCallExpr(
                            ident: ident,
                            arguments: try parseTuple().elements
                        )
                    )
                } else {
                    expr = .ident(ident)
                }
            case let .stringLiteral(value):
                expr = .stringLiteral(value)
            case let .integerLiteral(value):
                expr = .integerLiteral(value)
            case let .op(op):
                if case .trivia = peek() {
                    throw RichError("A prefix unary operator must not be separated from its operand", at: location())
                }
                expr = .unaryOp(UnaryOpExpr(op: op, operand: try parseExpr()))
            default:
                throw RichError("Expected an expression, got \(token.noun)", at: location())
        }

        let indexBeforeTrivia = index
        let hasWhitespaceBeforeOp = skipTrivia().foundWhitespace
        if case let .op(op) = peek() {
            next()
            let operatorLocation = location()
            let hasWhitespaceAfterOp = skipTrivia().foundWhitespace
            guard hasWhitespaceBeforeOp == hasWhitespaceAfterOp else {
                throw RichError("A binary operator must either have whitespace on both sides or none at all", at: operatorLocation)
            }
            let rightOperand = try parseExpr()
            return .binaryOp(BinaryOpExpr(op: op, leftOperand: expr, rightOperand: rightOperand))
        } else {
            index = indexBeforeTrivia
            return expr
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

    private mutating func parseType() throws -> Type {
        .nominal(try expectIdent())
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

    private struct TriviaSkippingResult {
        var foundWhitespace: Bool
        var foundNewLine: Bool
        var foundComment: Bool
        var skippedTrivia: Bool
    }

    /// Returns whether any trivia was skipped.
    @discardableResult
    private mutating func skipTrivia() -> TriviaSkippingResult {
        var whitespaceCount = 0
        var newLineCount = 0
        var commentCount = 0
        var count = 0
        while case let .trivia(trivia) = peek() {
            next()
            switch trivia {
                case .comment: commentCount += 1
                case let .whitespace(whitespace):
                    whitespaceCount += 1
                    if whitespace == .newLine {
                        newLineCount += 1
                    }
            }
            count += 1
        }
        return TriviaSkippingResult(
            foundWhitespace: whitespaceCount > 0,
            foundNewLine: newLineCount > 0,
            foundComment: commentCount > 0,
            skippedTrivia: count > 0
        )
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
            throw RichError("Expected whitespace, got \(token?.noun ?? "EOF")", at: peekLocation())
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
