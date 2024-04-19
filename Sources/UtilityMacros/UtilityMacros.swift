/// Only works when used on a method of `Parser`.
@attached(peer, names: suffixed(WithSpan))
public macro AlsoWithSpan() = #externalMacro(module: "UtilityMacrosPlugin", type: "WithSpanMacro")
