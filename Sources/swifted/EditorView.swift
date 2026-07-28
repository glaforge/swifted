//
//  Copyright 2026 Google LLC
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
import SwiftUI
import Cocoa
import SwiftTreeSitter
@MainActor
class HighlightCoordinator {
    let highlighter = Highlighter()
    var editVersion = 0
    var tokens: [(NSRange, String)] = []
    var onHighlightUpdated: (@MainActor () -> Void)?
    
    func setLanguageAndHighlight(fromExtension ext: String, currentText: String, onComplete: @escaping @MainActor () -> Void) {
        editVersion += 1
        let currentVersion = editVersion
        
        Task {
            await highlighter.setLanguage(fromExtension: ext)
            
            if self.editVersion != currentVersion { return }
            
            let startTS = CFAbsoluteTimeGetCurrent(); let highlightsList = await highlighter.highlight(text: currentText); print("TreeSitter highlighting took \(CFAbsoluteTimeGetCurrent() - startTS)s");
            
            if self.editVersion == currentVersion {
                let startFl = CFAbsoluteTimeGetCurrent(); self.tokens = self.flatten(highlightsList: highlightsList, textLength: currentText.utf16.count); print("Flatten took \(CFAbsoluteTimeGetCurrent() - startFl)s for \(highlightsList.count) tokens");
                onComplete()
            }
        }
    }
    
    func updateHighlights(edit: (UInt32, UInt32, UInt32)?, currentText: String, onComplete: @escaping @MainActor () -> Void) {
        editVersion += 1
        let currentVersion = editVersion
        let point = Point(row: 0, column: 0)
        
        Task {
            if let edit = edit {
                await highlighter.applyEdit(startByte: edit.0, oldEndByte: edit.1, newEndByte: edit.2, startPoint: point, oldEndPoint: point, newEndPoint: point)
            }
            
            if self.editVersion != currentVersion { return }
            
            let startTS = CFAbsoluteTimeGetCurrent(); let highlightsList = await highlighter.highlight(text: currentText); print("TreeSitter highlighting took \(CFAbsoluteTimeGetCurrent() - startTS)s");
            
            if self.editVersion == currentVersion {
                let startFl = CFAbsoluteTimeGetCurrent(); self.tokens = self.flatten(highlightsList: highlightsList, textLength: currentText.utf16.count); print("Flatten took \(CFAbsoluteTimeGetCurrent() - startFl)s for \(highlightsList.count) tokens");
                onComplete()
            }
        }
    }
    
    private func flatten(highlightsList: [(NSRange, String)], textLength: Int) -> [(NSRange, String)] {
        if textLength == 0 || highlightsList.isEmpty { return [] }
        
        let sortedHighlights = highlightsList.sorted { $0.0.length > $1.0.length }
        
        struct Event: Comparable {
            let position: Int
            let type: Int // 1 for start, 0 for end
            let priority: Int
            let token: String
            
            static func < (lhs: Event, rhs: Event) -> Bool {
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.type < rhs.type
            }
        }
        
        var events: [Event] = []
        events.reserveCapacity(sortedHighlights.count * 2)
        
        for (index, highlight) in sortedHighlights.enumerated() {
            let start = max(0, highlight.0.location)
            let end = min(highlight.0.location + highlight.0.length, textLength)
            if start < end {
                events.append(Event(position: start, type: 1, priority: index, token: highlight.1))
                events.append(Event(position: end, type: 0, priority: index, token: highlight.1))
            }
        }
        
        events.sort()
        
        var flatTokens: [(NSRange, String)] = []
        var activeTokens: [(priority: Int, token: String)] = []
        
        var currentStart = 0
        var currentToken: String? = nil
        
        var i = 0
        let n = events.count
        while i < n {
            let pos = events[i].position
            
            // Process all events at this position
            while i < n && events[i].position == pos {
                let ev = events[i]
                if ev.type == 1 {
                    let newElement = (priority: ev.priority, token: ev.token)
                    if let insertIdx = activeTokens.firstIndex(where: { $0.priority > ev.priority }) {
                        activeTokens.insert(newElement, at: insertIdx)
                    } else {
                        activeTokens.append(newElement)
                    }
                } else {
                    if let removeIdx = activeTokens.firstIndex(where: { $0.priority == ev.priority }) {
                        activeTokens.remove(at: removeIdx)
                    }
                }
                i += 1
            }
            
            let nextToken = activeTokens.last?.token
            
            if nextToken != currentToken {
                if let ct = currentToken, currentStart < pos {
                    flatTokens.append((NSRange(location: currentStart, length: pos - currentStart), ct))
                }
                currentStart = pos
                currentToken = nextToken
            }
        }
        
        return flatTokens
    }
}

class PieceTableTextStorage: NSTextStorage, @unchecked Sendable {
    private var pieceTable = PieceTable()
    let coordinator: HighlightCoordinator
    private var cachedString: String?
    var baseFontSize: CGFloat = 14
    
    private var unsafeSelf: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }
    
    override init() {
        self.coordinator = MainActor.assumeIsolated { HighlightCoordinator() }
        super.init()
    }
    
    required init?(coder: NSCoder) {
        self.coordinator = MainActor.assumeIsolated { HighlightCoordinator() }
        super.init(coder: coder)
    }
    
    required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        self.coordinator = MainActor.assumeIsolated { HighlightCoordinator() }
        super.init(pasteboardPropertyList: propertyList, ofType: type)
    }
    
    override var string: String {
        if let cached = self.cachedString {
            return cached
        }
        let str = self.pieceTable.text
        self.cachedString = str
        return str
    }
    
    // Search match state
    var searchMatches: [NSRange] = []
    var currentMatchIndex: Int = -1
    
    func findMatches(query: String, caseSensitive: Bool) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let nsText = self.string as NSString
        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var matches: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsText.length)
        
        while searchRange.location < nsText.length {
            let found = nsText.range(of: query, options: options, range: searchRange)
            if found.location == NSNotFound || found.length == 0 {
                break
            }
            matches.append(found)
            let nextStart = found.location + max(1, found.length)
            if nextStart >= nsText.length {
                break
            }
            searchRange = NSRange(location: nextStart, length: nsText.length - nextStart)
        }
        return matches
    }
    
    func updateSearchMatches(matches: [NSRange], currentIndex: Int) {
        self.searchMatches = matches
        self.currentMatchIndex = currentIndex
        self.beginEditing()
        self.edited(.editedAttributes, range: NSRange(location: 0, length: self.length), changeInLength: 0)
        self.endEditing()
    }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any] {
        if location >= self.length {
            return [:]
        }
        
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: self.baseFontSize, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]
        let limit = self.length
        var foundRange: NSRange? = nil
        var foundToken: String? = nil
        
        nonisolated(unsafe) let ptr = self.unsafeSelf
        let tokens = MainActor.assumeIsolated {
            let storage = Unmanaged<PieceTableTextStorage>.fromOpaque(ptr).takeUnretainedValue()
            return storage.coordinator.tokens
        }
        
        // Binary search to find the exact non-overlapping run
        var left = 0
        var right = tokens.count - 1
        
        while left <= right {
            let mid = left + (right - left) / 2
            let (highlightRange, tokenStr) = tokens[mid]
            
            if location < highlightRange.location {
                right = mid - 1
            } else if location >= NSMaxRange(highlightRange) {
                left = mid + 1
            } else {
                foundToken = tokenStr
                foundRange = highlightRange
                break
            }
        }
        
        if let token = foundToken {
            nonisolated(unsafe) let ptr = self.unsafeSelf
            let color = MainActor.assumeIsolated {
                let storage = Unmanaged<PieceTableTextStorage>.fromOpaque(ptr).takeUnretainedValue()
                return storage.coordinator.highlighter.colorMap[token]
            }
            if let c = color, c != NSColor.textColor {
                attrs[.foregroundColor] = c
            }
            
            if token == "text.strong" || token == "strong" || token == "strong_emphasis" {
                attrs[.font] = NSFont.monospacedSystemFont(ofSize: self.baseFontSize, weight: .bold)
            } else if token == "text.emphasis" || token == "emphasis" {
                if let baseFont = attrs[.font] as? NSFont {
                    let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.italic)
                    if let newFont = NSFont(descriptor: descriptor, size: self.baseFontSize) {
                        attrs[.font] = newFont
                    }
                }
            } else if token == "text.title" || token == "title" {
                attrs[.font] = NSFont.monospacedSystemFont(ofSize: self.baseFontSize + 2, weight: .bold)
            }
        }
        
        if let range = range {
            if let hr = foundRange {
                let maxLen = min(hr.length, self.length - hr.location)
                range.pointee = NSRange(location: hr.location, length: maxLen)
            } else {
                // Use the binary search insertion index to find the next token
                var nextTokenLocation = limit
                if left < tokens.count {
                    nextTokenLocation = tokens[left].0.location
                }
                let maxLen = min(nextTokenLocation - location, self.length - location)
                range.pointee = NSRange(location: location, length: maxLen)
            }
        }
        
        if !self.searchMatches.isEmpty {
            var sLeft = 0
            var sRight = self.searchMatches.count - 1
            var foundMatchIdx: Int? = nil
            
            while sLeft <= sRight {
                let sMid = sLeft + (sRight - sLeft) / 2
                let mRange = self.searchMatches[sMid]
                if location < mRange.location {
                    sRight = sMid - 1
                } else if location >= NSMaxRange(mRange) {
                    sLeft = sMid + 1
                } else {
                    foundMatchIdx = sMid
                    break
                }
            }
            
            if let mIdx = foundMatchIdx {
                if mIdx == self.currentMatchIndex {
                    attrs[.backgroundColor] = NSColor.systemOrange.withAlphaComponent(0.55)
                } else {
                    attrs[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(0.3)
                }
            }
            
            if let range = range {
                let currentEff = range.pointee
                if let mIdx = foundMatchIdx {
                    let mRange = self.searchMatches[mIdx]
                    let newEnd = min(NSMaxRange(currentEff), NSMaxRange(mRange))
                    let newLen = max(0, newEnd - location)
                    range.pointee = NSRange(location: location, length: newLen)
                } else {
                    var nextSearchMatchLoc = limit
                    if sLeft < self.searchMatches.count {
                        nextSearchMatchLoc = self.searchMatches[sLeft].location
                    }
                    if nextSearchMatchLoc < NSMaxRange(currentEff) {
                        let newEnd = min(NSMaxRange(currentEff), nextSearchMatchLoc)
                        let newLen = max(0, newEnd - location)
                        range.pointee = NSRange(location: location, length: newLen)
                    }
                }
            }
        }
        
        return attrs
    }
    
    override func replaceCharacters(in range: NSRange, with str: String) {
        self.beginEditing()
        
        let startByte = UInt32(range.location)
        let oldEndByte = UInt32(range.location + range.length)
        let newEndByte = UInt32(range.location + (str as NSString).length)
        
        self.pieceTable.delete(at: range.location, length: range.length)
        if !str.isEmpty {
            self.pieceTable.insert(text: str, at: range.location)
        }
        
        if self.pieceTable.piecesCount > 1000 {
            self.pieceTable.compact()
        }
        
        self.cachedString = nil
        
        let changeInLength = (str as NSString).length - range.length
        self.edited(.editedCharacters, range: range, changeInLength: changeInLength)
        
        let currentText = self.string
        nonisolated(unsafe) let ptr = self.unsafeSelf
        
        MainActor.assumeIsolated {
            let storage = Unmanaged<PieceTableTextStorage>.fromOpaque(ptr).takeUnretainedValue()
            storage.coordinator.updateHighlights(edit: (startByte, oldEndByte, newEndByte), currentText: currentText) {
                storage.beginEditing()
                storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
                storage.endEditing()
                storage.coordinator.onHighlightUpdated?()
            }
        }
        
        self.endEditing()
    }
    
    override func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, range: NSRange) {
        self.beginEditing()
        self.edited(.editedAttributes, range: range, changeInLength: 0)
        self.endEditing()
    }
    
    func load(text: String, fileExtension: String) {
        beginEditing()
        let oldLength = self.length
        pieceTable = PieceTable(text: text)
        cachedString = nil
        edited(.editedCharacters, range: NSRange(location: 0, length: oldLength), changeInLength: pieceTable.length - oldLength)
        endEditing()
        
        let currentText = self.string
        nonisolated(unsafe) let ptr = self.unsafeSelf
        
        MainActor.assumeIsolated {
            let storage = Unmanaged<PieceTableTextStorage>.fromOpaque(ptr).takeUnretainedValue()
            storage.coordinator.setLanguageAndHighlight(fromExtension: fileExtension, currentText: currentText) {
                storage.beginEditing()
                storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
                storage.endEditing()
                storage.coordinator.onHighlightUpdated?()
            }
        }
    }
}

class AutoFocusSearchField: NSSearchField {
    var focusSignal: UUID? {
        didSet {
            if focusSignal != oldValue {
                focusSelf()
            }
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusSelf()
    }
    
    func focusSelf() {
        guard let win = self.window else { return }
        DispatchQueue.main.async {
            win.makeFirstResponder(self)
            if let fieldEditor = self.currentEditor() {
                fieldEditor.selectAll(nil)
            }
        }
    }
}

struct FindQueryField: NSViewRepresentable {
    @Binding var text: String
    var focusSignal: UUID
    var onNext: () -> Void
    var onPrevious: () -> Void
    var onClose: () -> Void
    
    @AppStorage("appFontSize") private var appFontSize: AppFontSize = .medium
    
    @MainActor
    class Coordinator: NSObject, NSSearchFieldDelegate, NSTextFieldDelegate {
        var parent: FindQueryField
        
        init(_ parent: FindQueryField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let tf = obj.object as? NSTextField {
                parent.text = tf.stringValue
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    parent.onPrevious()
                } else {
                    parent.onNext()
                }
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onClose()
                return true
            }
            return false
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeNSView(context: Context) -> AutoFocusSearchField {
        let field = AutoFocusSearchField()
        field.placeholderString = "Find"
        field.delegate = context.coordinator
        field.controlSize = appFontSize.nsControlSize
        let size: CGFloat = appFontSize == .small ? 11 : (appFontSize == .large ? 18 : 13)
        field.font = NSFont.systemFont(ofSize: size)
        field.focusSignal = focusSignal
        return field
    }
    
    func updateNSView(_ nsView: AutoFocusSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        let targetControlSize = appFontSize.nsControlSize
        if nsView.controlSize != targetControlSize {
            nsView.controlSize = targetControlSize
        }
        let targetFontSize: CGFloat = appFontSize == .small ? 11 : (appFontSize == .large ? 18 : 13)
        if nsView.font?.pointSize != targetFontSize {
            nsView.font = NSFont.systemFont(ofSize: targetFontSize)
        }
        if nsView.focusSignal != focusSignal {
            nsView.focusSignal = focusSignal
        }
    }
}

extension AppFontSize {
    var nsControlSize: NSControl.ControlSize {
        switch self {
        case .small: return .small
        case .medium: return .regular
        case .large: return .large
        }
    }
}

struct FindBarView: View {
    @Binding var searchQuery: String
    @Binding var isCaseSensitive: Bool
    var focusSignal: UUID
    var matchCount: Int
    var currentIndex: Int
    var onNext: () -> Void
    var onPrevious: () -> Void
    var onClose: () -> Void
    
    @AppStorage("appFontSize") private var appFontSize: AppFontSize = .medium
    
    private var fieldHeight: CGFloat {
        switch appFontSize {
        case .small: return 22
        case .medium: return 26
        case .large: return 34
        }
    }
    
    private var fieldWidth: CGFloat {
        switch appFontSize {
        case .small: return 180
        case .medium: return 230
        case .large: return 320
        }
    }
    
    private var fontSize: CGFloat {
        switch appFontSize {
        case .small: return 11
        case .medium: return 13
        case .large: return 18
        }
    }
    
    var body: some View {
        HStack(spacing: appFontSize == .large ? 12 : 8) {
            FindQueryField(
                text: $searchQuery,
                focusSignal: focusSignal,
                onNext: onNext,
                onPrevious: onPrevious,
                onClose: onClose
            )
            .frame(width: fieldWidth, height: fieldHeight)
            
            Text(matchCount > 0 ? "\(currentIndex + 1) of \(matchCount)" : (searchQuery.isEmpty ? "" : "No results"))
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(matchCount > 0 ? .secondary : (searchQuery.isEmpty ? .secondary : .red))
                .frame(minWidth: appFontSize == .large ? 90 : 65, alignment: .leading)
            
            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
                    .font(.system(size: fontSize, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .controlSize(appFontSize.controlSize)
            .disabled(matchCount == 0)
            .help("Previous Match (Shift+Cmd+G)")
            
            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: fontSize, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .controlSize(appFontSize.controlSize)
            .disabled(matchCount == 0)
            .help("Next Match (Cmd+G)")
            
            Button(action: {
                isCaseSensitive.toggle()
            }) {
                Text("Aa")
                    .font(.system(size: fontSize, weight: isCaseSensitive ? .bold : .regular))
                    .foregroundColor(isCaseSensitive ? .accentColor : .secondary)
                    .padding(.horizontal, appFontSize == .large ? 6 : 4)
                    .padding(.vertical, appFontSize == .large ? 4 : 2)
                    .background(isCaseSensitive ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .controlSize(appFontSize.controlSize)
            .help("Match Case")
            
            Spacer()
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: fontSize + 2))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .controlSize(appFontSize.controlSize)
            .help("Close (Escape)")
        }
        .padding(.horizontal, appFontSize == .large ? 14 : 10)
        .padding(.vertical, appFontSize == .large ? 10 : 6)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
}

struct EditorView: View {
    var fileURL: URL
    
    @State private var showFindBar: Bool = false
    @State private var searchQuery: String = ""
    @State private var isCaseSensitive: Bool = false
    @State private var currentMatchIndex: Int = 0
    @State private var matchRanges: [NSRange] = []
    @State private var focusSignal: UUID = UUID()
    @State private var navSignal: UUID = UUID()
    @State private var navDirection: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            if showFindBar {
                FindBarView(
                    searchQuery: $searchQuery,
                    isCaseSensitive: $isCaseSensitive,
                    focusSignal: focusSignal,
                    matchCount: matchRanges.count,
                    currentIndex: currentMatchIndex,
                    onNext: { navigateMatch(direction: 1) },
                    onPrevious: { navigateMatch(direction: -1) },
                    onClose: { closeFindBar() }
                )
            }
            
            EditorRepresentable(
                fileURL: fileURL,
                showFindBar: showFindBar,
                searchQuery: searchQuery,
                isCaseSensitive: isCaseSensitive,
                navSignal: navSignal,
                navDirection: navDirection,
                onMatchesUpdated: { matches, idx in
                    self.matchRanges = matches
                    self.currentMatchIndex = idx
                },
                onSelectedTextExtracted: { selectedText in
                    if !selectedText.isEmpty {
                        self.searchQuery = selectedText
                    }
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .findToggle)) { _ in
            if !showFindBar {
                showFindBar = true
                focusSignal = UUID()
            } else {
                focusSignal = UUID()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findNext)) { _ in
            if !showFindBar {
                showFindBar = true
                focusSignal = UUID()
            } else {
                navigateMatch(direction: 1)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findPrevious)) { _ in
            if !showFindBar {
                showFindBar = true
                focusSignal = UUID()
            } else {
                navigateMatch(direction: -1)
            }
        }
        .onChange(of: fileURL) { _, _ in
            showFindBar = false
            searchQuery = ""
            matchRanges = []
            currentMatchIndex = 0
        }
    }
    
    private func navigateMatch(direction: Int) {
        guard !matchRanges.isEmpty else { return }
        navDirection = direction
        navSignal = UUID()
    }
    
    private func closeFindBar() {
        showFindBar = false
    }
}

struct EditorRepresentable: NSViewRepresentable {
    var fileURL: URL
    var showFindBar: Bool
    var searchQuery: String
    var isCaseSensitive: Bool
    var navSignal: UUID
    var navDirection: Int
    var onMatchesUpdated: ([NSRange], Int) -> Void
    var onSelectedTextExtracted: ((String) -> Void)?
    
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("showLineNumbers") var showLineNumbers: Bool = true
    @AppStorage("appFontSize") var appFontSize: AppFontSize = .medium
    @AppStorage("appWordWrap") var appWordWrap: Bool = false
    
    func makeNSView(context: Context) -> NSStackView {
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 0
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.5
        scrollView.maxMagnification = 4.0
        
        let textContentStorage = NSTextContentStorage()
        let textStorage = PieceTableTextStorage()
        textStorage.baseFontSize = appFontSize.codeSize
        textContentStorage.textStorage = textStorage
        
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)
        
        let textContainer = NSTextContainer(size: CGSize(width: appWordWrap ? 0 : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = appWordWrap
        textLayoutManager.textContainer = textContainer
        
        let textView = NSTextView(frame: CGRect(x: 0, y: 0, width: 10000, height: 10000), textContainer: textContainer)
        textView.minSize = NSSize(width: 0.0, height: 0.0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !appWordWrap
        textView.autoresizingMask = appWordWrap ? [.width] : [] // Allow width to track scrollview if wrapping
        textView.font = NSFont.monospacedSystemFont(ofSize: appFontSize.codeSize, weight: .regular)
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        
        scrollView.documentView = textView
        
        let gutterView = LineNumberGutterView(textView: textView, textContentStorage: textContentStorage, textLayoutManager: textLayoutManager)
        gutterView.baseFontSize = max(9.0, appFontSize.codeSize - 3.0)
        
        stackView.addArrangedSubview(gutterView)
        stackView.addArrangedSubview(scrollView)
        stackView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak coordinator = context.coordinator, weak scrollView, weak gutterView] _ in
            Task { @MainActor in
                gutterView?.needsDisplay = true
                if let url = coordinator?.currentURL, let sv = scrollView {
                    ViewStateStore.shared.saveScrollPosition(sv.contentView.bounds.origin, for: url)
                }
            }
        }
        
        context.coordinator.scrollView = scrollView
        context.coordinator.magnificationObservation = scrollView.observe(\.magnification, options: [.new]) { [weak coordinator = context.coordinator, weak gutterView] (sv, change) in
            Task { @MainActor in
                gutterView?.invalidateIntrinsicContentSize()
                gutterView?.needsDisplay = true
                if let url = coordinator?.currentURL, let mag = change.newValue {
                    ViewStateStore.shared.saveMagnification(mag, for: url)
                }
            }
        }
        
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleZoomIn), name: .zoomIn, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleZoomOut), name: .zoomOut, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleZoomReset), name: .zoomReset, object: nil)
        
        context.coordinator.textStorage = textStorage
        textStorage.coordinator.onHighlightUpdated = { [weak scrollView, weak coordinator = context.coordinator, weak gutterView] in
            if let scrollView = scrollView, let textView = scrollView.documentView as? NSTextView {
                textView.layoutSubtreeIfNeeded()
                gutterView?.invalidateIntrinsicContentSize()
                gutterView?.needsDisplay = true
                
                if let url = coordinator?.currentURL, let savedPos = ViewStateStore.shared.getScrollPosition(for: url) {
                    scrollView.documentView?.scroll(savedPos)
                    
                    // Simulate a tiny scroll to force TextKit 2 to lay out the fragments
                    DispatchQueue.main.async {
                        if scrollView.documentView != nil {
                            let jigglePos = CGPoint(x: savedPos.x, y: max(0, savedPos.y - 1))
                            scrollView.documentView?.scroll(jigglePos)
                            scrollView.documentView?.scroll(savedPos)
                        }
                    }
                }
            }
        }
        loadText(from: fileURL, into: textStorage, scrollView: scrollView)
        
        return stackView
    }
    
    func updateNSView(_ nsView: NSStackView, context: Context) {
        guard let scrollView = nsView.arrangedSubviews.first(where: { $0 is NSScrollView }) as? NSScrollView else { return }
        
        if let gutterView = nsView.arrangedSubviews.first(where: { $0 is LineNumberGutterView }) as? LineNumberGutterView {
            gutterView.isHidden = !showLineNumbers
            let newGutterFontSize = max(9.0, appFontSize.codeSize - 3.0)
            if gutterView.baseFontSize != newGutterFontSize {
                gutterView.baseFontSize = newGutterFontSize
            }
        }
        
        if let textView = scrollView.documentView as? NSTextView, let textContainer = textView.textContainer {
            if textContainer.widthTracksTextView != appWordWrap {
                textContainer.widthTracksTextView = appWordWrap
                textContainer.size = CGSize(width: appWordWrap ? 0 : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                textView.isHorizontallyResizable = !appWordWrap
                if appWordWrap {
                    textView.autoresizingMask = [.width]
                    textView.frame.size.width = scrollView.contentSize.width
                } else {
                    textView.autoresizingMask = []
                    textView.frame.size.width = max(textView.frame.width, scrollView.contentSize.width)
                }
            }
        }
        
        let newAppearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        if nsView.appearance != newAppearance {
            nsView.appearance = newAppearance
            nsView.setNeedsDisplay(nsView.bounds)
        }
        
        let newFontSize = appFontSize.codeSize
        if let textStorage = context.coordinator.textStorage, textStorage.baseFontSize != newFontSize {
            if let textView = scrollView.documentView as? NSTextView {
                textView.font = NSFont.monospacedSystemFont(ofSize: newFontSize, weight: .regular)
            }
            textStorage.baseFontSize = newFontSize
            textStorage.beginEditing()
            textStorage.edited(.editedAttributes, range: NSRange(location: 0, length: textStorage.length), changeInLength: 0)
            textStorage.endEditing()
        }
        
        if context.coordinator.currentURL != fileURL {
            context.coordinator.currentURL = fileURL
            if let textStorage = context.coordinator.textStorage {
                loadText(from: fileURL, into: textStorage, scrollView: scrollView)
            }
        }
        
        // Handle Find bar updates & searching
        let coord = context.coordinator
        let isShowFindBarChanged = coord.lastShowFindBar != showFindBar
        coord.lastShowFindBar = showFindBar
        
        if showFindBar {
            if isShowFindBarChanged {
                if let sel = coord.getSelectedText() {
                    onSelectedTextExtracted?(sel)
                }
            }
            
            let queryChanged = coord.lastSearchQuery != searchQuery || coord.lastCaseSensitive != isCaseSensitive
            let navChanged = coord.lastNavSignal != navSignal
            
            coord.lastNavSignal = navSignal
            
            if queryChanged || isShowFindBarChanged {
                coord.lastSearchQuery = searchQuery
                coord.lastCaseSensitive = isCaseSensitive
                
                if let storage = coord.textStorage {
                    let matches = storage.findMatches(query: searchQuery, caseSensitive: isCaseSensitive)
                    var initialIdx = 0
                    if !matches.isEmpty {
                        if let sv = coord.scrollView, let tv = sv.documentView as? NSTextView {
                            let cursorPos = tv.selectedRange().location
                            if let foundIdx = matches.firstIndex(where: { $0.location >= cursorPos }) {
                                initialIdx = foundIdx
                            }
                        }
                        coord.scrollToMatch(index: initialIdx, matches: matches)
                    } else {
                        storage.updateSearchMatches(matches: [], currentIndex: -1)
                        coord.lastMatches = []
                        coord.lastMatchIndex = -1
                    }
                    DispatchQueue.main.async {
                        onMatchesUpdated(matches, initialIdx)
                    }
                }
            } else if navChanged && !coord.lastMatches.isEmpty {
                let matches = coord.lastMatches
                var newIdx = coord.lastMatchIndex
                if navDirection == 1 {
                    newIdx = (newIdx + 1) % matches.count
                } else if navDirection == -1 {
                    newIdx = (newIdx - 1 + matches.count) % matches.count
                }
                coord.scrollToMatch(index: newIdx, matches: matches)
                DispatchQueue.main.async {
                    onMatchesUpdated(matches, newIdx)
                }
            }
        } else if isShowFindBarChanged {
            coord.lastSearchQuery = ""
            coord.lastMatches = []
            coord.lastMatchIndex = -1
            if let storage = coord.textStorage {
                storage.updateSearchMatches(matches: [], currentIndex: -1)
            }
            coord.makeTextViewFirstResponder()
            DispatchQueue.main.async {
                onMatchesUpdated([], 0)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate, @unchecked Sendable {
        var parent: EditorRepresentable
        var currentURL: URL?
        var textStorage: PieceTableTextStorage?
        var boundsObserver: (any Sendable)?
        var magnificationObservation: NSKeyValueObservation?
        weak var scrollView: NSScrollView?
        private var saveTask: Task<Void, Never>?
        
        var lastShowFindBar: Bool = false
        var lastSearchQuery: String = ""
        var lastCaseSensitive: Bool = false
        var lastNavSignal: UUID? = nil
        var lastMatches: [NSRange] = []
        var lastMatchIndex: Int = -1
        
        init(_ parent: EditorRepresentable) {
            self.parent = parent
            self.currentURL = parent.fileURL
        }
        
        func scrollToMatch(index: Int, matches: [NSRange]) {
            self.lastMatches = matches
            self.lastMatchIndex = index
            guard let sv = scrollView, let textView = sv.documentView as? NSTextView, index >= 0, index < matches.count else { return }
            let range = matches[index]
            textStorage?.updateSearchMatches(matches: matches, currentIndex: index)
            textView.layoutSubtreeIfNeeded()
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }
        
        func getSelectedText() -> String? {
            guard let sv = scrollView, let textView = sv.documentView as? NSTextView else { return nil }
            let range = textView.selectedRange()
            if range.length > 0 && range.length < 200 {
                let str = (textView.string as NSString).substring(with: range)
                if !str.contains("\n") && !str.contains("\r") {
                    return str
                }
            }
            return nil
        }
        
        func makeTextViewFirstResponder() {
            guard let sv = scrollView, let textView = sv.documentView as? NSTextView else { return }
            textView.window?.makeFirstResponder(textView)
        }
        
        func textDidChange(_ notification: Notification) {
            guard let url = currentURL, let storage = textStorage else { return }
            
            saveTask?.cancel()
            let currentText = storage.string
            
            saveTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds debounce
                    try await Task.detached(priority: .background) {
                        try currentText.write(to: url, atomically: true, encoding: .utf8)
                    }.value
                } catch is CancellationError {
                    // Ignore cancellation
                } catch {
                    print("Failed to auto-save file: \(error)")
                }
            }
        }
        
        @MainActor @objc func handleZoomIn() {
            if let sv = scrollView, sv.window != nil { sv.animator().magnification += 0.2 }
        }
        
        @MainActor @objc func handleZoomOut() {
            if let sv = scrollView, sv.window != nil { sv.animator().magnification -= 0.2 }
        }
        
        @MainActor @objc func handleZoomReset() {
            if let sv = scrollView, sv.window != nil { sv.animator().magnification = 1.0 }
        }
        
        deinit {
            magnificationObservation?.invalidate()
            if let obs = boundsObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    private func loadText(from url: URL, into storage: PieceTableTextStorage, scrollView: NSScrollView) {
        Task { @MainActor in
            let loadedText: String
            
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            
            if isDir.boolValue {
                loadedText = ""
            } else {
                loadedText = await Task.detached {
                    do {
                        let data = try Data(contentsOf: url, options: .alwaysMapped)
                        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
                    } catch {
                        return "Error loading file: \(error.localizedDescription)"
                    }
                }.value
            }
            storage.load(text: loadedText, fileExtension: url.pathExtension)
            
            let savedMag = ViewStateStore.shared.getMagnification(for: url)
            let savedPos = ViewStateStore.shared.getScrollPosition(for: url)
            
            if let mag = savedMag {
                if scrollView.magnification != mag { scrollView.magnification = mag }
            } else {
                if scrollView.magnification != 1.0 { scrollView.magnification = 1.0 }
            }
            
            if let pos = savedPos {
                if let textView = scrollView.documentView as? NSTextView {
                    textView.layoutSubtreeIfNeeded()
                }
                scrollView.documentView?.scroll(pos)
            } else {
                scrollView.documentView?.scroll(.zero)
            }
        }
    }
}

