/// Only works when used on a method of `Parser`.
@attached(peer, names: suffixed(WithSpan))
public macro AlsoWithSpan() = #externalMacro(module: "UtilityMacrosPlugin", type: "WithSpanMacro")

@freestanding(expression)
public macro result<T, P, U>(_ closure: (P) throws -> Result<T, U>) -> Result<T, U> =
    #externalMacro(module: "UtilityMacrosPlugin", type: "ResultMacro")

infix operator <-

public func <- <T, U>(_ value: T, result: Result<T, U>) {
    fatalError("<- can only be used in a #result context")
}
