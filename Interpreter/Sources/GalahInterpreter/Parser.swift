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

        while let token = next() {
            switch token {
                case .keyword(.fn):
                    decls.append(.fn(try parseFnDecl()))
                default:
                    throw RichError("Unexpected token '\(token)' while parsing top-level declarations", at: location())
            }
        }

        return AST(decls: decls)
    }

    private mutating func parseFnDecl() throws -> FnDecl {
        let ident = try expectIdent()

        try expect(.leftParen)
        var params: [Param] = []
        while let token = peek(), token != .rightParen {
            let ident = try expectIdent()
            let type: String?
            if peek() == .colon {
                next()
                type = try expectIdent()
            } else {
                type = nil
            }

            params.append(Param(ident: ident, type: type))

            guard peek() == .comma else {
                break
            }

            next()
        }
        try expect(.rightParen)

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
        let condition = try parseExpr()
        let ifBlock = try parseCodeBlock()
        try expect(.keyword(.else))
        let elseBlock = try parseCodeBlock()
        return IfStmt(condition: condition, ifBlock: ifBlock, elseBlock: elseBlock)
    }

    private mutating func parseCodeBlock() throws -> [Stmt] {
        try expect(.leftBrace)
        var stmts: [Stmt] = []
        while let token = peek(), token != .rightBrace {
            stmts.append(try parseStmt())
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
        var elements: [Expr] = []
        while let token = peek(), token != .rightParen {
            elements.append(try parseExpr())

            guard peek() == .comma else {
                break
            }

            next()
        }
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

    @discardableResult
    private mutating func next() -> Token? {
        while true {
            guard let token = peek() else {
                return nil
            }

            index += 1

            guard case .trivia = token else {
                previousIndex = index
                while case .trivia = peek() {
                    index += 1
                }
                return token
            }
        }
    }

    private mutating func expect(_ token: Token) throws {
        guard let nextToken = next(), nextToken == token else {
            throw RichError("Expected '\(token)'", at: location())
        }
    }

    private mutating func expectIdent() throws -> String {
        guard case let .ident(ident) = next() else {
            throw RichError("Expected ident", at: location())
        }
        return ident
    }
}
