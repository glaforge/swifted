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
import Foundation
import AppKit

// ANSI Escape Codes for Premium Console Styling
private let green = "\u{001B}[32m"
private let red = "\u{001B}[31m"
private let cyan = "\u{001B}[36m"
private let bold = "\u{001B}[1m"
private let reset = "\u{001B}[0m"

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    let file: String
    let line: UInt
    
    var description: String {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        return "\(message) at \(fileName):\(line)"
    }
}

// MARK: - Assertion Utilities
func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: UInt = #line) throws {
    if actual != expected {
        throw TestFailure(message: "Assertion failed: Expected '\(expected)', but got '\(actual)'" + (message.isEmpty ? "" : " - \(message)"), file: file, line: line)
    }
}

func assertNil(_ value: Any?, _ message: String = "", file: String = #file, line: UInt = #line) throws {
    if value != nil {
        throw TestFailure(message: "Assertion failed: Expected nil, but got non-nil value" + (message.isEmpty ? "" : " - \(message)"), file: file, line: line)
    }
}

func assertNotNil(_ value: Any?, _ message: String = "", file: String = #file, line: UInt = #line) throws {
    if value == nil {
        throw TestFailure(message: "Assertion failed: Expected non-nil, but got nil" + (message.isEmpty ? "" : " - \(message)"), file: file, line: line)
    }
}

func assertTrue(_ value: Bool, _ message: String = "", file: String = #file, line: UInt = #line) throws {
    if !value {
        throw TestFailure(message: "Assertion failed: Expected true, but got false" + (message.isEmpty ? "" : " - \(message)"), file: file, line: line)
    }
}

func assertFalse(_ value: Bool, _ message: String = "", file: String = #file, line: UInt = #line) throws {
    if value {
        throw TestFailure(message: "Assertion failed: Expected false, but got true" + (message.isEmpty ? "" : " - \(message)"), file: file, line: line)
    }
}

// MARK: - Test Runner
@MainActor
public enum TestRunner {
    public static func runAll() async -> Bool {
        print("\n\(cyan)\(bold)==================================================\(reset)")
        print("\(cyan)\(bold)           Swifted Custom Test Suite             \(reset)")
        print("\(cyan)\(bold)==================================================\(reset)\n")
        
        var passedCount = 0
        var failedCount = 0
        
        let tests: [(name: String, block: () async throws -> Void)] = [
            // PieceTable Tests
            ("PieceTable: Empty Initialization", testPieceTableEmpty),
            ("PieceTable: Insert at Start", testPieceTableInsertAtStart),
            ("PieceTable: Insert at End", testPieceTableInsertAtEnd),
            ("PieceTable: Insert in Middle", testPieceTableInsertInMiddle),
            ("PieceTable: Multiple Non-Contiguous Inserts", testPieceTableMultipleInserts),
            ("PieceTable: Delete Full", testPieceTableDeleteFull),
            ("PieceTable: Delete Partial (Split Piece)", testPieceTableDeletePartial),
            ("PieceTable: Delete Overlap (Multi Piece)", testPieceTableDeleteOverlap),
            ("PieceTable: Compaction", testPieceTableCompaction),
            ("PieceTable: UTF-16 Multi-byte Correctness", testPieceTableUTF16),
            
            // ViewStateStore Tests
            ("ViewStateStore: Scroll Position Retention", testViewStateStoreScroll),
            ("ViewStateStore: Magnification & Auto-Scales", testViewStateStoreMagnification),
            
            // Highlighter Tests
            ("Highlighter: JavaScript Parsing", testHighlighterJS),
            ("Highlighter: Kotlin Parsing", testHighlighterKotlin),
            ("Highlighter: Swift Parsing", testHighlighterSwift)
        ]
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for (name, testBlock) in tests {
            print("  Running \(name)...", terminator: "")
            fflush(stdout)
            
            do {
                try await testBlock()
                print("\r  \(green)✓ Passed\(reset) - \(name)")
                passedCount += 1
            } catch {
                print("\r  \(red)✗ Failed\(reset) - \(name)")
                print("    \(red)\(error)\(reset)\n")
                failedCount += 1
            }
        }
        
        let elapsedTime = CFAbsoluteTimeGetCurrent() - startTime
        
        print("\n\(cyan)\(bold)--------------------------------------------------\(reset)")
        print("\(bold)Test Execution Summary:\(reset)")
        print("  Total Tests: \(tests.count)")
        print("  \(green)Passed:      \(passedCount)\(reset)")
        if failedCount > 0 {
            print("  \(red)Failed:      \(failedCount)\(reset)")
        } else {
            print("  \(green)Failed:      \(failedCount)\(reset)")
        }
        print(String(format: "  Duration:    %.3f seconds", elapsedTime))
        print("\(cyan)\(bold)==================================================\(reset)\n")
        
        return failedCount == 0
    }
    
    // MARK: - PieceTable Test Cases
    
    private static func testPieceTableEmpty() throws {
        let pt = PieceTable()
        try assertEqual(pt.length, 0)
        try assertEqual(pt.piecesCount, 0)
        try assertEqual(pt.text, "")
    }
    
    private static func testPieceTableInsertAtStart() throws {
        let pt = PieceTable(text: "World")
        pt.insert(text: "Hello, ", at: 0)
        try assertEqual(pt.text, "Hello, World")
        try assertEqual(pt.length, 12)
        try assertEqual(pt.piecesCount, 2)
    }
    
    private static func testPieceTableInsertAtEnd() throws {
        let pt = PieceTable(text: "Hello")
        pt.insert(text: ", World", at: 5)
        try assertEqual(pt.text, "Hello, World")
        try assertEqual(pt.length, 12)
        try assertEqual(pt.piecesCount, 2)
    }
    
    private static func testPieceTableInsertInMiddle() throws {
        let pt = PieceTable(text: "Hello World")
        pt.insert(text: ",", at: 5)
        try assertEqual(pt.text, "Hello, World")
        try assertEqual(pt.length, 12)
        try assertEqual(pt.piecesCount, 3) // [Hello], [,], [ World]
    }
    
    private static func testPieceTableMultipleInserts() throws {
        let pt = PieceTable(text: "A C E")
        pt.insert(text: "B", at: 1) // "AB C E"
        pt.insert(text: "D", at: 4) // "AB CD E"
        try assertEqual(pt.text, "AB CD E")
    }
    
    private static func testPieceTableDeleteFull() throws {
        let pt = PieceTable(text: "DeleteMe")
        pt.delete(at: 0, length: 8)
        try assertEqual(pt.text, "")
        try assertEqual(pt.length, 0)
        try assertEqual(pt.piecesCount, 0)
    }
    
    private static func testPieceTableDeletePartial() throws {
        let pt = PieceTable(text: "Hello World")
        pt.delete(at: 5, length: 1) // Remove space
        try assertEqual(pt.text, "HelloWorld")
        try assertEqual(pt.length, 10)
        try assertEqual(pt.piecesCount, 2) // [Hello], [World]
    }
    
    private static func testPieceTableDeleteOverlap() throws {
        let pt = PieceTable(text: "Hello")
        pt.insert(text: " Beautiful", at: 5) // "Hello Beautiful", 2 pieces
        pt.insert(text: " World", at: 15)   // "Hello Beautiful World", 3 pieces
        
        // Let's delete " Beautiful " across pieces.
        // Logical layout of pieces:
        // P0: "Hello" (len 5)
        // P1: " Beautiful" (len 10)
        // P2: " World" (len 6)
        // Let's delete from index 5 to index 16 (" Beautiful ")
        pt.delete(at: 5, length: 11)
        try assertEqual(pt.text, "HelloWorld")
        try assertEqual(pt.length, 10)
    }
    
    private static func testPieceTableCompaction() throws {
        let pt = PieceTable(text: "Hello")
        pt.insert(text: " Beautiful", at: 5)
        pt.insert(text: " World", at: 15)
        try assertTrue(pt.piecesCount > 1)
        
        pt.compact()
        try assertEqual(pt.text, "Hello Beautiful World")
        try assertEqual(pt.piecesCount, 1)
    }
    
    private static func testPieceTableUTF16() throws {
        // "👨‍👩‍👧‍👦" is 1 emoji but 11 UTF-16 code units.
        // "🇺🇸" is 1 flag but 4 UTF-16 code units.
        let pt = PieceTable(text: "Hello 👨‍👩‍👧‍👦 World")
        
        let textNSString = pt.text as NSString
        try assertEqual(pt.length, textNSString.length)
        
        // Let's delete the emoji
        pt.delete(at: 6, length: 11)
        try assertEqual(pt.text, "Hello  World")
    }
    
    // MARK: - ViewStateStore Test Cases
    
    private static func testViewStateStoreScroll() throws {
        let url = URL(fileURLWithPath: "/tmp/test_file.txt")
        let store = ViewStateStore.shared
        
        store.saveScrollPosition(CGPoint(x: 120.5, y: 340.0), for: url)
        let pos = store.getScrollPosition(for: url)
        
        try assertNotNil(pos)
        try assertEqual(pos?.x, 120.5)
        try assertEqual(pos?.y, 340.0)
    }
    
    private static func testViewStateStoreMagnification() throws {
        let url = URL(fileURLWithPath: "/tmp/test_file_2.txt")
        let store = ViewStateStore.shared
        
        store.saveMagnification(1.5, autoScales: true, for: url)
        
        let mag = store.getMagnification(for: url)
        let auto = store.getAutoScales(for: url)
        
        try assertEqual(mag, 1.5)
        try assertEqual(auto, true)
    }
    
    // MARK: - Highlighter Test Cases
    
    private static func testHighlighterJS() async throws {
        let h = Highlighter()
        await h.setLanguage(fromExtension: "js")
        
        let text = """
        // Simple JS Function
        function greet(name) {
            console.log("Hello, " + name);
            return 42;
        }
        """
        
        let tokens = await h.highlight(text: text)
        try assertTrue(tokens.count > 0)
        
        // Verify keyword "function" is captured
        let hasFunctionKeyword = tokens.contains { range, name in
            name == "keyword" && (text as NSString).substring(with: range) == "function"
        }
        try assertTrue(hasFunctionKeyword, "Expected to find function keyword")
        
        // Verify string is captured
        let hasString = tokens.contains { range, name in
            name == "string" && (text as NSString).substring(with: range).contains("Hello")
        }
        try assertTrue(hasString, "Expected to find string token")
    }
    
    private static func testHighlighterKotlin() async throws {
        let h = Highlighter()
        await h.setLanguage(fromExtension: "kt")
        
        let text = """
        package com.example
        
        val LOG = Logger()
        fun main() {
            println("Hello Kotlin")
        }
        """
        
        let tokens = await h.highlight(text: text)
        try assertTrue(tokens.count > 0)
        
        // Check keyword
        let hasFunKeyword = tokens.contains { range, name in
            name == "keyword" && (text as NSString).substring(with: range) == "fun"
        }
        try assertTrue(hasFunKeyword, "Expected fun keyword")
    }
    
    private static func testHighlighterSwift() async throws {
        let h = Highlighter()
        await h.setLanguage(fromExtension: "swift")
        
        let text = """
        import Foundation
        
        struct User {
            let name: String
            var age: Int = 18
        }
        """
        
        let tokens = await h.highlight(text: text)
        try assertTrue(tokens.count > 0)
        
        // Check Struct keyword
        let hasStructKeyword = tokens.contains { range, name in
            name == "keyword" && (text as NSString).substring(with: range) == "struct"
        }
        try assertTrue(hasStructKeyword, "Expected struct keyword")
    }
}
