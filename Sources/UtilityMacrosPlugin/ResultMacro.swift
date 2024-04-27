import MacroToolkit
import SwiftSyntax
import SwiftSyntaxMacros

class ArrowSyntaxRewriter<Context: MacroExpansionContext>: SyntaxRewriter {
    var context: Context
    var contextVariables: [String: TypeSyntax]
    var diagnostics: [MacroError]

    init(context: Context, contextVariables: [String: TypeSyntax]) {
        self.context = context
        self.contextVariables = contextVariables
        self.diagnostics = []
    }

    override func visit(_ node: CodeBlockItemSyntax) -> CodeBlockItemSyntax {
        var node = node
        switch node.item {
            case let .expr(expr):
                let leftOperand: ExprSyntax
                let rightOperand: ExprSyntax
                if let operatorExpr = expr.as(InfixOperatorExprSyntax.self),
                    operatorExpr.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "<-"
                {
                    leftOperand = operatorExpr.leftOperand
                    rightOperand = operatorExpr.rightOperand
                } else if var operatorSequenceExpr = expr.as(SequenceExprSyntax.self),
                    let operatorToken = Array(operatorSequenceExpr.elements)[1]
                        .as(BinaryOperatorExprSyntax.self),
                    operatorToken.operator.text == "<-"
                {
                    let elements = Array(operatorSequenceExpr.elements)
                    leftOperand = elements[0]
                    operatorSequenceExpr.elements = ExprListSyntax(
                        Array(operatorSequenceExpr.elements.dropFirst(2)))
                    rightOperand = ExprSyntax(operatorSequenceExpr)
                } else {
                    return node
                }

                guard
                    let ident = leftOperand.as(DeclReferenceExprSyntax.self),
                    contextVariables.keys.contains(ident.baseName.text),
                    ident.argumentNames == nil
                else {
                    diagnostics.append(
                        MacroError(
                            "Unknown context variable \(leftOperand). Only declared closure parameters can be used on the left hand side of '<-'"
                        )
                    )
                    return node
                }

                let resultInnerBinding = context.makeUniqueName("value")
                let stmt: StmtSyntax =
                    """

                    switch \(rightOperand) {
                        case let .success(\(resultInnerBinding)):
                            \(leftOperand) = \(resultInnerBinding)
                        case let .failure(\(resultInnerBinding)):
                            return .failure(\(resultInnerBinding))
                    }

                    """

                node.item = .stmt(stmt)
                return node
            case let .stmt(stmt):
                if let throwStmt = stmt.as(ThrowStmtSyntax.self) {
                    node.item = .stmt(
                        """

                        return .failure(\(throwStmt.expression))

                        """
                    )
                }
                return node
            case .decl:
                return node
        }
    }

    // Don't recurse yet
    public override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
        return ExprSyntax(node)
    }
}

class ResultMacroRewriter<Context: MacroExpansionContext>: SyntaxRewriter {
    var context: Context
    var errors: [any Error]

    init(context: Context) {
        self.context = context
        errors = []
    }

    public override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
        do {
            return try ResultMacro.expansion(of: node, in: context)
        } catch {
            errors.append(error)
            return ExprSyntax(node)
        }
    }
}

public struct ResultMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard node.argumentList.isEmpty, node.additionalTrailingClosures.isEmpty else {
            throw MacroError("#result expects a single trailing closure")
        }

        guard var closure = node.trailingClosure else {
            throw MacroError("#result expects a closure")
        }

        guard
            let parameterClause = closure.signature?.parameterClause?
                .as(ClosureParameterClauseSyntax.self)
        else {
            throw MacroError("#result expects trailing closure with single tuple parameter")
        }

        var contextVariables: [String: TypeSyntax] = [:]
        for parameter in parameterClause.parameters {
            guard let type = parameter.type, parameter.secondName == nil else {
                throw MacroError(
                    "#result expects closure each parameter to have a single label and a type annotation"
                )
            }
            contextVariables[parameter.firstName.text] = type
        }

        let rewriter = ArrowSyntaxRewriter(context: context, contextVariables: contextVariables)
        closure.statements = rewriter.rewrite(closure.statements, detach: true).as(
            CodeBlockItemListSyntax.self)!
        closure.signature?.parameterClause = ClosureParameterClauseSyntax.init(parameters: [])
            .as(ClosureSignatureSyntax.ParameterClause.self)

        guard rewriter.diagnostics.isEmpty else {
            for diagnostic in rewriter.diagnostics {
                context.diagnose(
                    DiagnosticBuilder(for: closure._syntaxNode).message("\(diagnostic)").build()
                )
            }
            throw MacroError("Expansion of #result failed")
        }

        var contextVariableDecls: [CodeBlockItemSyntax] = []
        for (ident, type) in contextVariables {
            contextVariableDecls.append(
                """

                let \(raw: ident): \(raw: type)

                """
            )
        }
        closure.statements = contextVariableDecls + closure.statements

        let resultMacroRewriter = ResultMacroRewriter(context: context)
        closure.statements = resultMacroRewriter.rewrite(closure.statements, detach: true)
            .as(CodeBlockItemListSyntax.self)!

        guard resultMacroRewriter.errors.isEmpty else {
            for diagnostic in resultMacroRewriter.errors {
                context.diagnose(
                    DiagnosticBuilder(for: closure._syntaxNode).message("\(diagnostic)").build()
                )
            }
            throw MacroError(
                "Recursive expansion of #result failed (is allowed but failed to expand)"
            )
        }

        return "\(closure)()"
    }
}
