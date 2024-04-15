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

    func run() throws {
        do {
            let contents = try String(contentsOf: file)
            try Interpreter.run(contents)
        } catch {
            print(error, to: &standardError)
        }
    }
}
