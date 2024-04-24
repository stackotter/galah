import UtilityMacros

// TODO: Borrow ideas from parser combinators to make some of the more tedious parsing
//   logic (e.g. parts that have to look ahead) more declarative and composable.
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

    private mutating func withSpan<T>(_ parse: (inout Parser) throws -> T) rethrows -> WithSpan<T> {
        let start = peekLocation()
        let result = try parse(&self)
        let end = location()
        return WithSpan(result, start.span(until: end))
    }

    private consuming func parse() throws -> AST {
        var structDecls: [WithSpan<StructDecl>] = []
        var fnDecls: [WithSpan<FnDecl>] = []

        skipTrivia()
        while let token = peek() {
            switch token {
                case .keyword(.struct):
                    structDecls.append(try parseStructDeclWithSpan())
                case .keyword(.fn):
                    fnDecls.append(try parseFnDeclWithSpan())
                default:
                    throw Diagnostic(
                        error: "Unexpected token '\(token)' while parsing top-level declarations",
                        at: location()
                    )
            }
            skipTrivia()
        }

        return AST(structDecls: structDecls, fnDecls: fnDecls)
    }

    @AlsoWithSpan
    private mutating func parseStructDecl() throws -> StructDecl {
        try expect(.keyword(.struct))
        try expectWhitespaceSkippingTrivia()

        let ident = try expectIdentWithSpan()

        skipTrivia()
        try expect(.leftBrace)
        skipTrivia()

        var fields: [WithSpan<Field>] = []
        while let token = peek(), token != .rightBrace {
            fields.append(try parseFieldWithSpan())
            skipTrivia()
            if peek() == .comma {
                next()
                skipTrivia()
            } else {
                break
            }
        }

        try expect(.rightBrace)

        return StructDecl(
            ident: ident,
            fields: fields
        )
    }

    @AlsoWithSpan
    private mutating func parseField() throws -> Field {
        let ident = try expectIdentWithSpan()
        skipTrivia()
        try expect(.colon)
        skipTrivia()
        let type = try parseTypeWithSpan()
        return Field(ident: ident, type: type)
    }

    @AlsoWithSpan
    private mutating func parseFnDecl() throws -> FnDecl {
        let signature = try parseFnSignatureWithSpan()
        skipTrivia()
        let stmts = try parseCodeBlock()
        return FnDecl(
            signature: signature,
            stmts: stmts
        )
    }

    @AlsoWithSpan
    private mutating func parseFnSignature() throws -> FnSignature {
        try expect(.keyword(.fn))
        try expectWhitespaceSkippingTrivia()

        let ident = try expectIdentWithSpan()

        try expect(.leftParen)
        skipTrivia()

        var params: [WithSpan<Param>] = []
        while let token = peek(), token != .rightParen {
            params.append(try parseFnParamWithSpan())

            skipTrivia()
            guard peek() == .comma else {
                break
            }

            next()
            skipTrivia()
        }
        try expect(.rightParen)

        let returnType: WithSpan<Type>?
        if case let .op(op) = peekPastTrivia(), op.token == "->" {
            skipTrivia()
            next()
            skipTrivia()
            returnType = try parseTypeWithSpan()
        } else {
            returnType = nil
        }

        return FnSignature(
            ident: ident,
            params: params,
            returnType: returnType
        )
    }

    @AlsoWithSpan
    private mutating func parseFnParam() throws -> Param {
        let ident = try expectIdentWithSpan()
        skipTrivia()
        try expect(.colon)
        skipTrivia()

        let type = try parseTypeWithSpan()
        return Param(ident: ident, type: type)
    }

    @AlsoWithSpan
    private mutating func parseStmt() throws -> Stmt {
        if peek() == .keyword(.if) {
            return .if(try parseIfStmt())
        } else if peek() == .keyword(.return) {
            return .return(try parseReturnStmtWithSpan())
        } else if peek() == .keyword(.let) {
            return .let(try parseLetStmt())
        } else {
            return .expr(try parseExpr())
        }
    }

    private mutating func parseReturnStmtWithSpan() throws -> WithSpan<Expr>? {
        try expect(.keyword(.return))
        while let token = peek(),
            case let .trivia(trivia) = token, trivia != .whitespace(.newLine)
        {
            next()
        }
        if peek() == .trivia(.whitespace(.newLine)) {
            return nil
        } else {
            return try parseExprWithSpan()
        }
    }

    private mutating func parseLetStmt() throws -> VarDecl {
        try expect(.keyword(.let))
        try expectWhitespaceSkippingTrivia()

        let ident = try expectIdentWithSpan()
        skipTrivia()

        let type: WithSpan<Type>?
        if peek() == .colon {
            next()
            skipTrivia()
            type = try parseTypeWithSpan()
            skipTrivia()
        } else {
            type = nil
        }

        try expect(.op(.assignment))
        skipTrivia()

        let value = try parseExprWithSpan()
        return VarDecl(
            ident: ident,
            type: type,
            value: value
        )
    }

    @AlsoWithSpan
    private mutating func parseIfStmt() throws -> IfStmt {
        try expect(.keyword(.if))
        try expectWhitespaceSkippingTrivia()
        let condition = try parseExprWithSpan()
        skipTrivia()
        let ifBlock = try parseCodeBlock()
        skipTrivia()

        let `else`: IfStmt.ElseBlock?
        if peek() == .keyword(.else) {
            next()
            skipTrivia()

            switch peek() {
                case .keyword(.if):
                    `else` = .elseIf(try parseIfStmtWithSpan())
                case .leftBrace:
                    `else` = .else(try parseCodeBlock())
                case let token:
                    throw Diagnostic(
                        error: "Expected 'if' or '{', got \(token?.noun ?? "EOF")",
                        at: peekLocation()
                    )
            }
        } else {
            `else` = nil
        }

        return IfStmt(condition: condition, ifBlock: ifBlock, else: `else`)
    }

    private mutating func parseCodeBlock() throws -> [WithSpan<Stmt>] {
        try expect(.leftBrace)
        skipTrivia()
        var stmts: [WithSpan<Stmt>] = []
        while let token = peek(), token != .rightBrace {
            let stmt = try parseStmtWithSpan()
            stmts.append(stmt)
            if !stmt.inner.endsWithCodeBlock {
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

    @AlsoWithSpan
    private mutating func parseExpr() throws -> Expr {
        guard let token = richNext() else {
            throw Diagnostic(error: "Unexpected EOF while parsing expression", at: location())
        }

        let startLocation = location()
        var expr: Expr
        switch token.token {
            case let .ident(ident):
                if peek() == .leftParen {
                    expr = .fnCall(
                        FnCallExpr(
                            ident: WithSpan(ident, token.span),
                            arguments: try parseTuple().elements
                        )
                    )
                } else if peekPastTrivia() == .leftBrace {
                    expr = .structInit(
                        StructInitExpr(
                            ident: WithSpan(ident, token.span),
                            fields: try parseStructInitBlockWithSpan()
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
                    throw Diagnostic(
                        error: "A prefix unary operator must not be separated from its operand",
                        at: location()
                    )
                }
                expr = .unaryOp(
                    UnaryOpExpr(
                        op: WithSpan(op, token.span),
                        operand: try parseExprWithSpan()
                    ))
            case .leftParen:
                skipTrivia()
                let inner = try parseExprWithSpan()
                skipTrivia()
                try expect(.rightParen)
                expr = .parenthesizedExpr(inner)
            default:
                throw Diagnostic(
                    error: "Expected an expression, got \(token.token.noun)",
                    at: location()
                )
        }
        var endLocation = location()

        if case .period = peek() {
            next()
            let memberIdent = try expectIdentWithSpan()
            expr = .memberAccess(
                MemberAccessExpr(
                    base: WithSpan(expr, startLocation.span(until: endLocation)),
                    memberIdent: memberIdent
                )
            )
            endLocation = location()
        }

        let previousIndexBeforeTrivia = previousIndex
        let indexBeforeTrivia = index
        let hasWhitespaceBeforeOp = skipTrivia().foundWhitespace
        if let token = richPeek(), case let .op(op) = token.token {
            next()

            let operatorLocation = location()
            let hasWhitespaceAfterOp = skipTrivia().foundWhitespace
            guard hasWhitespaceBeforeOp == hasWhitespaceAfterOp else {
                throw Diagnostic(
                    error:
                        "A binary operator must either have whitespace on both sides or none at all",
                    at: operatorLocation
                )
            }

            let rightOperand = try parseExprWithSpan()
            let exprWithSpan = WithSpan(expr, startLocation.span(until: endLocation))
            return .binaryOp(
                BinaryOpExpr(
                    op: WithSpan(op, token.span),
                    leftOperand: exprWithSpan,
                    rightOperand: rightOperand
                )
            )
        } else {
            previousIndex = previousIndexBeforeTrivia
            index = indexBeforeTrivia
            return expr
        }
    }

    @AlsoWithSpan
    private mutating func parseStructInitBlock() throws -> [WithSpan<StructInitField>] {
        skipTrivia()
        try expect(.leftBrace)

        var fields: [WithSpan<StructInitField>] = []
        skipTrivia()
        while let token = richPeek(), token.token != .rightBrace {
            fields.append(try parseStructInitFieldWithSpan())
            skipTrivia()

            if peek() == .comma {
                next()
                skipTrivia()
            } else {
                break
            }
        }

        try expect(.rightBrace)
        return fields
    }

    @AlsoWithSpan
    private mutating func parseStructInitField() throws -> StructInitField {
        let ident = try expectIdentWithSpan()
        skipTrivia()
        try expect(.colon)
        skipTrivia()
        let value = try parseExprWithSpan()
        return StructInitField(ident: ident, value: value)
    }

    @AlsoWithSpan
    private mutating func parseTuple() throws -> Tuple {
        try expect(.leftParen)
        skipTrivia()

        var elements: [WithSpan<Expr>] = []
        while let token = peek(), token != .rightParen {
            elements.append(try parseExprWithSpan())
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

    @AlsoWithSpan
    private mutating func parseType() throws -> Type {
        .nominal(try expectIdent())
    }

    private func richPeek() -> RichToken? {
        if index < tokens.count {
            return tokens[index]
        } else {
            return nil
        }
    }

    private func peek() -> Token? {
        richPeek()?.token
    }

    // TODO: Generalize saving/restoring state to make it more reusable.
    private mutating func peekPastTrivia() -> Token? {
        let savedIndex = index
        let savedPreviousIndex = previousIndex
        skipTrivia()
        let token = peek()
        index = savedIndex
        previousIndex = savedPreviousIndex
        return token
    }

    /// The location of the token most recently returned by ``Parser/next``.
    private func location() -> Location {
        return tokens[previousIndex].location
    }

    /// The location of the token that would be returned by ``Parser/peek``. If at the
    /// end of the file, the location after the file's last token is given.
    private func peekLocation() -> Location {
        if index < tokens.count {
            tokens[index].location
        } else {
            location() + tokens[previousIndex].token.size
        }
    }

    @discardableResult
    private mutating func richNext() -> RichToken? {
        let token = richPeek()
        if token != nil {
            previousIndex = index
            index += 1
        }
        return token
    }

    @discardableResult
    private mutating func next() -> Token? {
        richNext()?.token
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
            throw Diagnostic(
                error: "Expected whitespace, got \(token?.noun ?? "EOF")",
                at: peekLocation()
            )
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
            throw Diagnostic(
                error: "Expected a newline, got \(token?.noun ?? "an EOF")",
                at: peekLocation()
            )
        }
    }

    private mutating func expect(_ token: Token) throws {
        let nextToken = next()
        guard let nextToken = nextToken, nextToken == token else {
            throw Diagnostic(
                error: "Expected \(token.noun), got \(nextToken?.noun ?? "an EOF")",
                at: location()
            )
        }
    }

    @AlsoWithSpan
    private mutating func expectIdent() throws -> String {
        let token = next()
        guard case let .ident(ident) = token else {
            throw Diagnostic(
                error: "Expected an ident, got \(token?.noun ?? "an EOF")",
                at: location()
            )
        }
        return ident
    }
}
