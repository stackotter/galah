import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct UtilityMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WithSpanMacro.self,
        ResultMacro.self,
    ]
}
