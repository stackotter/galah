public struct Parser {
    let tokens: [Token]
    var index = 0

    public static func parse(_ tokens: [Token]) throws -> AST {
        let parser = Parser(tokens)
        return try parser.parse()
    }

    private init(_ tokens: [Token]) {
        self.tokens = tokens
    }

    private consuming func parse() throws -> AST {
        var decls: [Decl] = []

        while let token = next() {
            switch token {
                case .keyword(.fn):
                    decls.append(.fn(try parseFnDecl()))
                default:
                    throw RichError("Unexpected token '\(token)' while parsing top-level declarations")
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

        try expect(.leftBrace)
        var stmts: [Stmt] = []
        while let token = peek(), token != .rightBrace {
            stmts.append(try parseStmt())
        }
        try expect(.rightBrace)

        return FnDecl(ident: ident, params: params, stmts: stmts)
    }

    private mutating func parseStmt() throws -> Stmt {
        .expr(try parseExpr())
    }

    private mutating func parseExpr() throws -> Expr {
        guard let token = next() else {
            throw RichError("Unexpected EOF while parsing expression")
        }

        return switch token {
            case let .ident(ident):
                .fnCall(
                    FnCallExpr(
                        ident: ident,
                        arguments: try parseTuple().elements
                    )
                )
            case let .stringLiteral(value):
                .stringLiteral(value)
            default:
                print(index)
                throw RichError("Unexpected token while parsing expression: \(token)")
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
            return tokens[index]
        } else {
            return nil
        }
    }

    @discardableResult
    private mutating func next() -> Token? {
        if let token = peek() {
            index += 1
            return token
        } else {
            return nil
        }
    }

    private mutating func expect(_ token: Token) throws {
        guard let nextToken = next(), nextToken == token else {
            throw RichError("Expected '\(token)'")
        }
    }

    private mutating func expectIdent() throws -> String {
        guard case let .ident(ident) = next() else {
            throw RichError("Expected ident")
        }
        return ident
    }
}
