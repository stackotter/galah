import ArgumentParser
import Foundation
import GalahInterpreter

var standardError = FileHandle.standardError

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        let data = Data(string.utf8)
        self.write(data)
    }
}

public func eprint(_ message: String) {
    print(message, to: &standardError)
}

@main
struct Cli: ParsableCommand {
    @Argument(help: "Script to run", transform: URL.init(fileURLWithPath:))
    var file: URL

    func run() {
        let sourceCode: String
        do {
            sourceCode = try String(contentsOf: file)
        } catch {
            eprint("Failed to read '\(file.path)'")
            return
        }

        do {
            let interpreter = try Interpreter(sourceCode) { diagnostic in
                eprint(diagnostic.formatted(withSourceCode: sourceCode))
            }
            try interpreter.evaluateMainFn()
        } catch let errors as [Diagnostic] {
            for error in errors {
                eprint(error.formatted(withSourceCode: sourceCode))
            }
        } catch {
            eprint("\(error)")
        }
    }
}
