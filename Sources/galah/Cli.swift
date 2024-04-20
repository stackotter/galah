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

@main
struct Cli: ParsableCommand {
    @Argument(help: "Script to run", transform: URL.init(fileURLWithPath:))
    var file: URL

    func run() {
        let sourceCode: String
        do {
            sourceCode = try String(contentsOf: file)
        } catch {
            print("Failed to read '\(file.path)'", to: &standardError)
            return
        }

        do {
            try Interpreter.run(sourceCode)
        } catch let error as RichError {
            print(error.formatted(withSourceCode: sourceCode), to: &standardError)
        } catch {
            print(error, to: &standardError)
        }
    }
}
