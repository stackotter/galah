## galah

A scripting language with the goal of being lightweight and embeddable in Swift applications.

### Trying it out

#### Online playground

The [Galah playground](https://stackotter.github.io/galah) uses WASM to run a Galah interpreter
in your browser! Visit it in a modern browser to try out Galah without the need to install it
locally.

#### Building locally

The following commands build the interpreter's CLI from source and run the `sample.galah` file
included in this repository,

```sh
git clone https://github.com/stackotter/galah
cd galah
swift run galah ./sample.galah
```

### Syntax (WIP, mostly not implemented yet)

This syntax is all bound to change! Nothing is set in stone, and even the style of the language
isn't completely decided yet.

The following example program is strongly typed but relies heavily on type inference instead of
type annotations. Still not sure whether omitting return type annotations is a good idea or not.
With good enough LSP support it should be fine, but LSPs won't always be that useful when using
user-provided built-in functions etc (there's a limit to how much the LSP can know without some
sort of interface file).

```swift
struct Citizen {
    let name: Str
    let age: Int

    // `name` is inferred to be of type `Str`.
    init(name) {
        self.name = name
        self.age = 0
    }

    fn randomName() -> Str {
        ["Steve Apple", "John Smith"].randomChoice()
    }

    // Return type is inferred as `(Str, Optional<Str>)`
    fn parsedName(self) {
        let parts = self.name.split(" ", maxSplits: 1)
        return (parts[0], parts.last)
    }

    // We could infer that it throws for the user, but that might not be a good idea. Note that
    // this method definitely shouldn't throw in any sane software, this is just an example.
    fn incrementAge(mut self) throws {
        self.age += 1
        if self.age > 100 || Int.random(0, 80) == 0 {
            throw "Citizen died"
        }
    }
}

fn main() {
    let stackotter = Citizen("stackotter")
    for _ in 0..<80 {
        do {
            try stackotter.incrementAge()
        } catch {
            eprint("stackotter died at {stackotter.age}")
            exit(1)
        }
    }

    print("stackotter is {stackotter.age}")
    let (first, last) = stackotter.parsedName()
    print("stackotter's first name is {first} and his last name is \(last ?? "unknown")")
}
```

Here's the same program but written in Python as a comparison,

```python
from typing import Optional

class Citizen:
    name: Str
    age: Int

    def init(self, name: str, age: int):
        self.name = name
        self.age = age

    @classmethod
    def randomName(cls) -> str {
        return ["Steve Apple", "John Smith"].randomChoice()

    def parsedName(self) -> (str, Optional[str]):
        let parts = self.name.split(" ", 1)
        return (parts[0], parts[1] if len(parts) == 2 else None)

    def incrementAge(self):
        self.age += 1
        if self.age > 100 or random.randrange(0, 80) == 0:
            raise Exception("Citizen died")

if __name__ == "__main__":
    stackotter = Citizen("stackotter")
    for _ in range(80):
        try:
            try stackotter.incrementAge()
        catch Exception:
            print("stackotter died at {stackotter.age}")
            exit(1)

    print(f"stackotter is {stackotter.age}")
    first, last = stackotter.parsedName()
    print(f"stackotter's first name is {first} and his last name is \(last ?? 'unknown')")
```
