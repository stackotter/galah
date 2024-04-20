import MacroToolkit
import SwiftSyntax
import SwiftSyntaxMacros

public struct WithSpanMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let function = Function(declaration) else {
            throw MacroError("@WithSpan() can only be applied to methods")
        }
        guard let returnType = function.returnType else {
            throw MacroError("@WithSpan() can only be applied to non-Void functions")
        }
        let returnTypeWithSpan: TypeSyntax = "WithSpan<\(returnType._syntax)>"

        return [
            DeclSyntax(
                function._syntax
                    .withAttributes(function.attributes.removing(node))
                    .withIdentifier("\(function.identifier)WithSpan")
                    .withReturnType(Type(returnTypeWithSpan))
                    .withBody(
                        CodeBlockSyntax {
                            "let startLocation = peekLocation()"
                            "let result = try \(raw: function.identifier)()"
                            "let endLocation = peekLocation()"
                            "return WithSpan(result, startLocation.span(until: endLocation))"
                        }
                    )
            )
        ]
    }
}

extension FunctionDeclSyntax {
    func withIdentifier(_ identifier: String) -> Self {
        var syntax = self
        syntax.name = TokenSyntax.identifier(identifier)
        return syntax
    }
}
