import XCTest

@testable import GalahInterpreter

final class GalahInterpreterTests: XCTestCase {
    func lexerTestCase(_ text: String, _ expected: [(Token, Int, Int)]) {
        XCTAssertEqual(
            try Lexer.lex(text),
            expected.map { token, line, column in
                RichToken(token, at: Location(line: line, column: column))
            }
        )
    }

    func testSimple() throws {
        lexerTestCase(
            "a b",
            [(.ident("a"), 1, 1), (.trivia(.whitespace(.space)), 1, 2), (.ident("b"), 1, 3)]
        )
    }

    func testIntegerLiteral() throws {
        lexerTestCase(
            "123",
            [(.integerLiteral(123), 1, 1)]
        )
    }

    func testComment() throws {
        lexerTestCase(
            """
            // comment\t\r
            123
            """,
            [
                (.trivia(.comment(" comment\t")), 1, 1), (.trivia(.whitespace(.newLine)), 1, 12),
                (.integerLiteral(123), 2, 1),
            ]
        )
    }

    func testUnterminatedStringLiteral() throws {
        do {
            _ = try Lexer.lex("\"asdf")
            XCTFail("Parsed unterminated string literal without throwing an error")
        } catch {}
    }

    func testMandatoryWhitespace() throws {
        do {
            _ = try Parser.parse(
                try Lexer.lex(
                    """
                    fn dummy() {
                        print(\"hi\") print(\"hi\")
                    }
                    """
                )
            )
            XCTFail("Two statements on the same line must fail")
        } catch {}
    }

    func testStructCycleChecker() throws {
        let ast = try Parser.parse(
            try Lexer.lex(
                """
                struct Chicken {
                    egg: Egg,
                }

                struct Nest {
                    stickCount: Int,
                    egg1: Egg,
                    egg2: Egg
                }

                struct Fish {
                    chicken: Chicken
                }

                struct Egg {
                    chicken: Chicken,
                    fish: Fish
                }
                """
            )
        )

        // TODO: Verify the diagnostics emitted once error handling is done with results instead
        do {
            _ = try TypeChecker.check(
                ast, Interpreter.defaultBuiltinTypes, Interpreter.defaultBuiltinFns
            )
            XCTFail("Self-referential structs must fail to type-check")
        } catch {}
    }

    func testNestedMemberAccesses() throws {
        let ast = try Parser.parse(
            try Lexer.lex(
                """
                fn main() {
                    x.a.b
                }
                """
            )
        )

        XCTAssertEqual(
            ast.fnDecls[0].stmts[0].inner,
            .expr(
                .memberAccess(
                    MemberAccessExpr.init(
                        base: WithSpan(
                            builtin: .memberAccess(
                                .init(
                                    base: WithSpan(builtin: .ident("x")),
                                    memberIdent: WithSpan(builtin: "a")
                                )
                            )
                        ),
                        memberIdent: WithSpan(builtin: "b")
                    )
                )
            )
        )
    }
}
