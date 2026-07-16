import AppKit

let symbols = ["text.wrap", "arrow.turn.down.left", "arrow.uturn.backward", "text.word.spacing", "return"]
for name in symbols {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    print("\(name): \(image != nil ? "EXISTS" : "MISSING")")
}
