func todo(_ message: String) -> Never {
    print("todo: \(message)")
    exit(1)
}

public enum Interpreter {
    public static func run(_ code: String) throws {
        let tokens = try lex(code)
        print(tokens)
        let ast = try parse(tokens)
        print(ast)
        todo("Run AST")
    }

    public static func lex(_ code: String) throws -> [Token] {
        try Lexer.lex(code)
    }

    public static func parse(_ tokens: [Token]) throws -> AST {
        try Parser.parse(tokens)
    }
}
