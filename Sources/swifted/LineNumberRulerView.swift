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
import AppKit

class LineNumberGutterView: NSView {
    weak var textView: NSTextView?
    weak var textContentStorage: NSTextContentStorage?
    weak var textLayoutManager: NSTextLayoutManager?
    
    private var cachedLineNumber: Int = 1
    private var cachedLocation: Int = 0
    
    var baseFontSize: CGFloat = 11.0 {
        didSet {
            self.invalidateIntrinsicContentSize()
            self.needsDisplay = true
        }
    }
    
    init(textView: NSTextView, textContentStorage: NSTextContentStorage, textLayoutManager: NSTextLayoutManager) {
        self.textView = textView
        self.textContentStorage = textContentStorage
        self.textLayoutManager = textLayoutManager
        super.init(frame: .zero)
        
        // Observe text bounds and frame changes to trigger redraws
        self.postsFrameChangedNotifications = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var isFlipped: Bool {
        return true
    }
    
    override var intrinsicContentSize: NSSize {
        guard let textView = self.textView else { return NSSize(width: 45, height: NSView.noIntrinsicMetric) }
        let stringLength = textView.string.count
        
        // Safely estimate the max digits (minimum 3 digits)
        let estimatedMaxDigits = max(3, String(stringLength).count)
        let sampleString = String(repeating: "8", count: estimatedMaxDigits)
        
        let mag = textView.enclosingScrollView?.magnification ?? 1.0
        let fontSize = baseFontSize * mag
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        ]
        
        let size = (sampleString as NSString).size(withAttributes: attributes)
        
        // Add 10 points padding for the left and right margins
        return NSSize(width: size.width + 10, height: NSView.noIntrinsicMetric)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let textView = self.textView,
              let textLayoutManager = self.textLayoutManager,
              let textContentStorage = self.textContentStorage,
              let scrollView = textView.enclosingScrollView else {
            return
        }
        
        // Draw background
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        
        // Draw right border
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: self.bounds.maxX - 0.5, y: self.bounds.minY))
        borderPath.line(to: NSPoint(x: self.bounds.maxX - 0.5, y: self.bounds.maxY))
        borderPath.lineWidth = 1.0
        NSColor.separatorColor.setStroke()
        borderPath.stroke()
        
        let visibleRect = scrollView.documentVisibleRect
        let string = textView.string as NSString
        
        // Enumerate only within the visible area
        textLayoutManager.enumerateTextLayoutFragments(from: textContentStorage.documentRange.location, options: []) { fragment in
            if fragment.layoutFragmentFrame.intersects(visibleRect) {
                drawFragment(fragment, visibleRect: visibleRect, string: string, textContentStorage: textContentStorage)
            }
            return fragment.layoutFragmentFrame.maxY <= visibleRect.maxY
        }
    }
    
    private func drawFragment(_ fragment: NSTextLayoutFragment, visibleRect: NSRect, string: NSString, textContentStorage: NSTextContentStorage) {
        guard let textElement = fragment.textElement,
              let elementRange = textElement.elementRange,
              let textView = self.textView,
              let scrollView = textView.enclosingScrollView else { return }
        
        // Only draw line numbers for the first fragment of a paragraph
        let isFirstFragment = fragment.rangeInElement.location.compare(elementRange.location) == .orderedSame
        if !isFirstFragment { return }
        
        let offset = textContentStorage.offset(from: textContentStorage.documentRange.location, to: elementRange.location)
        let currentLineNumber = computeLineNumber(for: offset, string: string)
        
        // layoutFragmentFrame is in textContainer coordinates, so we must add textContainerOrigin
        var fragmentRect = fragment.layoutFragmentFrame
        
        // Align with the first line of the fragment (fixes wrapped lines and tall last fragments)
        if let firstLine = fragment.textLineFragments.first {
            fragmentRect.origin.y += firstLine.typographicBounds.minY
            fragmentRect.size.height = firstLine.typographicBounds.height
        }
        
        fragmentRect.origin.y += textView.textContainerOrigin.y
        fragmentRect.origin.x += textView.textContainerOrigin.x
        
        // Convert to gutter's coordinate system (handles zoom and scrolling)
        let rectInGutter = textView.convert(fragmentRect, to: self)
        
        let fontSize = baseFontSize * scrollView.magnification
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        
        let attrString = NSAttributedString(string: "\(currentLineNumber)", attributes: attributes)
        let size = attrString.size()
        
        // Vertically center the line number within the specific line's frame
        let yOffset = (rectInGutter.height - size.height) / 2.0
        let yPosInGutter = rectInGutter.minY + yOffset
        
        attrString.draw(at: NSPoint(x: self.bounds.width - size.width - 5, y: yPosInGutter))
    }
    
    private func computeLineNumber(for location: Int, string: NSString) -> Int {
        if location == cachedLocation { return cachedLineNumber }
        
        if location == 0 {
            cachedLineNumber = 1
            cachedLocation = 0
            return 1
        }
        
        var lines = 1
        var start = 0
        if location >= cachedLocation {
            lines = cachedLineNumber
            start = cachedLocation
        }
        
        let rangeToScan = NSRange(location: start, length: location - start)
        var count = 0
        
        var searchRange = rangeToScan
        while searchRange.location < NSMaxRange(rangeToScan) {
            let foundRange = string.range(of: "\n", options: .literal, range: searchRange)
            if foundRange.location != NSNotFound {
                count += 1
                searchRange = NSRange(location: foundRange.location + 1, length: NSMaxRange(rangeToScan) - (foundRange.location + 1))
            } else {
                break
            }
        }
        
        lines += count
        cachedLineNumber = lines
        cachedLocation = location
        return lines
    }
}
