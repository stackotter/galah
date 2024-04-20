import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MacroToolkitExamplePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WithSpanMacro.self
    ]
}
