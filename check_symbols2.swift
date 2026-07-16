import AppKit

let symbols = ["text.append", "arrow.right.to.line", "arrow.turn.down.left"]
for name in symbols {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    print("\(name): \(image != nil ? "EXISTS" : "MISSING")")
}
