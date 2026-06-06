import Foundation

/// Maps an LSP `SymbolKind` integer (1...26) to a display name and an SF Symbol
/// name for the Go to Symbol overlay. AppKit-free and pure so it is unit-testable.
public enum SymbolKindLabel {
    /// Human-readable kind name (e.g. 5 -> "Class"). Unknown kinds are "Symbol".
    public static func name(for kind: Int) -> String {
        names[kind] ?? "Symbol"
    }

    /// SF Symbol name representing the kind, for the row icon. Unknown kinds fall
    /// back to a neutral glyph.
    public static func systemImage(for kind: Int) -> String {
        symbols[kind] ?? "smallcircle.filled.circle"
    }

    private static let names: [Int: String] = [
        1: "File", 2: "Module", 3: "Namespace", 4: "Package", 5: "Class",
        6: "Method", 7: "Property", 8: "Field", 9: "Constructor", 10: "Enum",
        11: "Interface", 12: "Function", 13: "Variable", 14: "Constant",
        15: "String", 16: "Number", 17: "Boolean", 18: "Array", 19: "Object",
        20: "Key", 21: "Null", 22: "Enum Member", 23: "Struct", 24: "Event",
        25: "Operator", 26: "Type Parameter",
    ]

    private static let symbols: [Int: String] = [
        1: "doc", 2: "shippingbox", 3: "number", 4: "shippingbox", 5: "c.square",
        6: "function", 7: "p.square", 8: "f.square", 9: "wrench", 10: "e.square",
        11: "i.square", 12: "function", 13: "v.square", 14: "k.square",
        15: "quote.opening", 16: "number.square", 17: "checkmark.square",
        18: "list.number", 19: "curlybraces", 20: "key", 21: "circle.slash",
        22: "e.square", 23: "s.square", 24: "bolt", 25: "plusminus", 26: "t.square",
    ]
}
