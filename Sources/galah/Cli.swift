import GalahInterpreter
import ArgumentParser
import Foundation

var standardError = FileHandle.standardError

extension FileHandle: TextOutputStream {
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
            try Interpreter.run(sourceCode) { diagnostic in
                eprint(diagnostic.formatted(withSourceCode: sourceCode))
            }
        } catch let error as Diagnostic {
            eprint(error.formatted(withSourceCode: sourceCode))
        } catch {
            eprint("\(error)")
        }
    }
}
