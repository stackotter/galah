public protocol GalahRepresentable {
    static var type: Type { get }
}

extension Int: GalahRepresentable {
    public static let type = Type.nominal("Int")
}

extension String: GalahRepresentable {
    public static let type = Type.nominal("String")
}

extension Bool: GalahRepresentable {
    public static let type = Type.nominal("Bool")
}
