## Enum subsets

i.e. tagging a certain subset of enum cases as and then allowing conversion to/from that subset seamlessly

```
enum Platform {
  subset ApplePlatform {
    func releaseYear() -> Int {
      switch self {
        case .macOS: 1998 // made up
        case .iOS: 2007
      }
    }
  }

  case macOS[ApplePlatform]
  case iOS[ApplePlatform]
  case linux

  func name() -> String {
    switch self {
      case .macOS: "macOS"
      case .iOS: "iOS"
      case .linux: "Linux"
    }
  }
}

func doApple(_ platform: Platform.ApplePlatform) {
  print("{platform.name()} was released in {platform.releaseYear()}")
}

switch platform {
  case .macOS, .iOS:
    doApple(platform)
  case .linux:
    print("Linux has always been released and always will be")
}
```

## Enum relabelling

Allow multiple versions of an enum with different labels; I often find myself with multiple
versions of the same enum for different contexts, and there's tons of annoying glue code
involved.

```
enum Direction {
  case up
  case down
  case left
  case right
}

enum Edge relabelling Direction {
  case top[up] // would need to think about this syntax a bit longer
  case bottom[down]
  case leading[left]
  case trailing[right]
}
```

## Automatic 'kind' enums

It can be useful to have both data enums and kind enums; yet there's usually a lot of boilerplate involved so
they're avoided.

```
enum OSVersion {
  case macOS(SemVer)
  case iOS(SemVer)
  case linux(KernelVersion)
  case windows(MSVersion)
}

typealias OS = OSVersion.Kind

let version: OSVersion = .macOS(SemVer(11, 2, 5))
let os = OS(version) // OS.macOS
```

## Follow Rust's lead with separating out conformance `impl`s from basic `impl`s

From my experience with generics in the SwiftCrossUI project, I've found that it's quite common
for conformances to silently become stale when default implementations are available which can
cause some pretty subtle bugs. If `impl` blocks for conformances can only define members
satisfying the conformance requirements then this whole source of bugs is eliminated.

## A first-class way to collect stacktraces using `Result`-based error handling

This could possibly be implemented by having a trait that you can implement to get a method called
on your struct whenever it's the return value of a function. This would work in most cases but could
be annoying if you try and nest the error within another error. Maybe structs can auto-implement the
trait when one of their fields implements it? It'd be interesting to have a way for users to define
a 'viral' interface that propagates up to enclosing types with a default implementation.

## Testing

It'd be pretty awesome to be able to have a system that only reruns tests that would've been affected
by the changes made since the last time they were run.

## Make panics catchable out of the box (e.g. index out of bounds etc.)?

Could get abused by exception lovers to avoid value-based error handling though.

## Auto conflict resolution

If the interpreter understood Git conflict markers than it'd be possible to get it to build
and test a merge-conflict-ridden project with various combinations of resolutions in an
attempt to fix the trivially solvable conflicts. This would require the developer to manually
resolve any merge conflicts in the test code first so that the tests can be used as a source
of truth.
