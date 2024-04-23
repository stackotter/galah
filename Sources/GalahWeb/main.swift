import GalahInterpreter
import JavaScriptKit

@discardableResult
func create(
    _ tag: String,
    in parent: JSValue? = nil,
    _ configure: (inout JSValue) -> Void
) -> JSValue {
    var element = JSObject.global.document.createElement(tag)
    configure(&element)

    if let parent {
        _ = parent.appendChild(element)
    } else {
        _ = JSObject.global.document.body.appendChild(element)
    }

    return element
}

create("style") { stylesheet in
    stylesheet.innerHTML =
        """
        html {
            font-family: sans-serif;
        }

        body {
            display: block;
            margin: auto;
            width: 100%;
            max-width: 80rem;
        }

        h1 {
            margin-top: 1rem;
        }

        #split {
            display: flex;
            flex-direction: row;
            width: 100%;
            height: 30rem;
            margin: auto;
        }

        #code, #output {
            width: 50%;
        }

        #code {
            margin-right: 1rem;
        }

        #output, #code {
            border: 1px solid black;
            font-family: monospace;
            padding: 0.5rem;
            font-size: 1rem;
        }

        #output {
            margin: 0;
        }

        button {
            margin-top: 1rem;
            background: blue;
            color: white;
            height: 2rem;
            width: 10rem;
            border: none;
            font-weight: bold;
        }
        """
}

create("h1") { $0.textContent = "Galah playgrnd" }

create("p") {
    $0.innerHTML =
        """
        Galah is a scripting language with the goal of being lightweight and embeddable in Swift applications.
        Visit <a href="https://github.com/stackotter/galah">the Galah GitHub repository</a> to find out more.
        """
}

let split = create("div") { $0.id = "split" }
let textarea = create("textarea", in: split) { textarea in
    textarea.id = "code"
    textarea.value =
        """
        fn fibonacci(n: Int) -> Int {
            if n == 0 {
                return 0
            } else if n == 1 {
                return 1
            } else {
                let result = fibonacci(n - 1) + fibonacci(n - 2)
                return result
            }
        }

        fn main() {
            print("The 20th fibonacci number is:")
            print(fibonacci(20))
        }
        """
}
var output = create("pre", in: split) { $0.id = "output" }
var button = create("button") { $0.textContent = "Run" }

button.onclick = .object(
    JSClosure { _ in
        let value: JSValue = textarea.value
        let code = value.string!

        var outputString = ""
        func customPrint(_ message: String) {
            outputString += message + "\n"
        }
        func customPrint(_ message: Int) {
            outputString += "\(message)\n"
        }

        let builtinFns =
            Interpreter.defaultBuiltinFns.filter { $0.signature.ident.inner != "print" } + [
                BuiltinFn("print") { (x: Int) in
                    customPrint(x)
                },
                BuiltinFn("print") { (x: String) in
                    customPrint(x)
                },
            ]

        do {
            try Interpreter.run(code, builtinFns: builtinFns) { diagnostic in
                customPrint(diagnostic.formatted(withSourceCode: code))
            }
        } catch let error as Diagnostic {
            customPrint(error.formatted(withSourceCode: code))
        } catch {
            customPrint("\(error)")
        }

        output.textContent = .string(outputString)

        return .undefined
    }
)
