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
import SwiftTreeSitter
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterTypeScript
import TreeSitterMarkdown
import TreeSitterBash
import TreeSitterPython
import TreeSitterKotlin
import TreeSitterGroovy
import TreeSitterJSON
import TreeSitterSwift
import TreeSitterJavaQueries
import TreeSitterJavaScriptQueries
import TreeSitterTypeScriptQueries
import TreeSitterMarkdownQueries
import TreeSitterBashQueries
import TreeSitterPythonQueries
import TreeSitterJSONQueries
import TreeSitterSwiftQueries
import TreeSitterGo
import TreeSitterC
import TreeSitterCPP
import TreeSitterGoQueries
import TreeSitterCQueries
import TreeSitterCPPQueries
import TreeSitterHTML
import TreeSitterHTMLQueries
import TreeSitterCSS
import TreeSitterCSSQueries

private func createLang<T>(_ ptr: UnsafePointer<T>?) -> Language? {
    guard let ptr = ptr else { return nil }
    return Language(language: OpaquePointer(ptr))
}

private func createLang(_ ptr: UnsafeRawPointer?) -> Language? {
    guard let ptr = ptr else { return nil }
    return Language(language: OpaquePointer(ptr))
}

private func createLang(_ ptr: UnsafeMutableRawPointer?) -> Language? {
    guard let ptr = ptr else { return nil }
    return Language(language: OpaquePointer(ptr))
}

private func createLang(_ ptr: OpaquePointer?) -> Language? {
    guard let ptr = ptr else { return nil }
    return Language(language: ptr)
}

enum SupportedLanguage: String {
    case java = "java"
    case javascript = "js"
    case typescript = "ts"
    case markdown = "md"
    case bash = "sh"
    case python = "py"
    case kotlin = "kt"
    case groovy = "groovy"
    case gradle = "gradle"
    case json = "json"
    case swift = "swift"
    case go = "go"
    case c = "c"
    case h = "h"
    case cpp = "cpp"
    case hpp = "hpp"
    case cc = "cc"
    case html = "html"
    case css = "css"
    
    var language: Language? {
        switch self {
        case .java: return createLang(tree_sitter_java())
        case .javascript: return createLang(tree_sitter_javascript())
        case .typescript: return createLang(tree_sitter_typescript())
        case .markdown: return createLang(tree_sitter_markdown())
        case .bash: return createLang(tree_sitter_bash())
        case .python: return createLang(tree_sitter_python())
        case .kotlin: return createLang(tree_sitter_kotlin())
        case .groovy, .gradle: return createLang(tree_sitter_groovy())
        case .json: return createLang(tree_sitter_json())
        case .swift: return createLang(tree_sitter_swift())
        case .go: return createLang(tree_sitter_go())
        case .c, .h: return createLang(tree_sitter_c())
        case .cpp, .hpp, .cc: return createLang(tree_sitter_cpp())
        case .html: return createLang(tree_sitter_html())
        case .css: return createLang(tree_sitter_css())
        }
    }
}

actor QueryCache {
    static let shared = QueryCache()
    var cache: [SupportedLanguage: SwiftTreeSitter.Query] = [:]
    func get(_ lang: SupportedLanguage) -> SwiftTreeSitter.Query? { return cache[lang] }
    func set(_ lang: SupportedLanguage, query: SwiftTreeSitter.Query) { cache[lang] = query }
}

actor Highlighter {
    var parser = Parser()
    var tree: MutableTree?
    var language: SupportedLanguage?
    var currentTsLanguage: Language?
    var currentQuery: SwiftTreeSitter.Query?
    
    nonisolated let colorMap: [String: NSColor] = [
        "keyword": .systemPink,
        "include": .systemPink,
        "namespace": .systemPink,
        "conditional": .systemPink,
        "repeat": .systemPink,
        "exception": .systemPink,
        "boolean": .systemPink,
        "string": .systemRed,
        "character": .systemRed,
        "function": .systemBlue,
        "type": .systemTeal,
        "constructor": .systemTeal,
        "variable": .textColor,
        "parameter": .textColor,
        "comment": .systemGray,
        "number": .systemOrange,
        "float": .systemOrange,
        "operator": .systemGray,
        "property": .systemPurple,
        "attribute": .systemPurple,
        "constant": .systemOrange,
        
        // Markdown specific
        "text.title": .systemBlue,
        "text.literal": .systemOrange,
        "text.uri": .systemTeal,
        "text.reference": .systemTeal,
        "punctuation.special": .systemGray,
        "punctuation.delimiter": .systemGray,
        "string.escape": .systemPink,
        "text.strong": .textColor,
        "text.emphasis": .textColor
    ]
    
    init() {}
    
    private func findQueryURL(bundleName: String, fileName: String = "highlights", ext: String = "scm", fallback: () -> URL?) -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundleURL = resourceURL.appendingPathComponent("\(bundleName).bundle")
            let fileURL = bundleURL.appendingPathComponent("\(fileName).\(ext)")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }
        return fallback()
    }
    
    func setLanguage(fromExtension ext: String) async {
        let normalized = ext.lowercased()
        let mappedExt = (normalized == "plist" || normalized == "xml") ? "html" : normalized
        
        guard let lang = SupportedLanguage(rawValue: mappedExt),
              let tsLang = lang.language else {
            self.language = nil
            self.currentTsLanguage = nil
            self.currentQuery = nil
            self.parser = Parser()
            return
        }
        
        self.language = lang
        self.currentTsLanguage = tsLang
        do {
            try parser.setLanguage(tsLang)
        } catch {
            fatalError("FAILED TO SET LANGUAGE \(lang.rawValue): \(error)")
        }
        
        if let cached = await QueryCache.shared.get(lang) {
            self.currentQuery = cached
            return
        }
        
        var queryURL: URL?
        switch lang {
        case .java:
            queryURL = findQueryURL(bundleName: "TreeSitterLanguages_TreeSitterJavaQueries") { TreeSitterJavaQueries.Query.highlightsFileURL }
        case .javascript:
            queryURL = findQueryURL(bundleName: "TreeSitterLanguages_TreeSitterJavaScriptQueries") { TreeSitterJavaScriptQueries.Query.highlightsFileURL }
        case .typescript:
            queryURL = findQueryURL(bundleName: "TreeSitterLanguages_TreeSitterTypeScriptQueries") { TreeSitterTypeScriptQueries.Query.highlightsFileURL }
        case .markdown:
            queryURL = findQueryURL(bundleName: "TreeSitterLanguages_TreeSitterMarkdownQueries") { TreeSitterMarkdownQueries.Query.highlightsFileURL }
        case .bash:
            queryURL = findQueryURL(bundleName: "TreeSitterLanguages_TreeSitterBashQueries") { TreeSitterBashQueries.Query.highlightsFileURL }
        case .python:
            queryURL = findQueryURL(bundleName: "TreeSitterLanguages_TreeSitterPythonQueries") { TreeSitterPythonQueries.Query.highlightsFileURL }
        case .json:
            queryURL = findQueryURL(bundleName: "TreeSitterLanguages_TreeSitterJSONQueries") { TreeSitterJSONQueries.Query.highlightsFileURL }
        case .swift:
            queryURL = findQueryURL(bundleName: "TreeSitterLanguages_TreeSitterSwiftQueries") { TreeSitterSwiftQueries.Query.highlightsFileURL }
        case .go:
            queryURL = findQueryURL(bundleName: "TreeSitterLanguages_TreeSitterGoQueries") { TreeSitterGoQueries.Query.highlightsFileURL }
        case .c, .h:
            queryURL = findQueryURL(bundleName: "TreeSitterLanguages_TreeSitterCQueries") { TreeSitterCQueries.Query.highlightsFileURL }
        case .cpp, .hpp, .cc:
            queryURL = findQueryURL(bundleName: "TreeSitterLanguages_TreeSitterCPPQueries") { TreeSitterCPPQueries.Query.highlightsFileURL }
        case .html:
            queryURL = findQueryURL(bundleName: "TreeSitterLanguages_TreeSitterHTMLQueries") { TreeSitterHTMLQueries.Query.highlightsFileURL }
        case .css:
            queryURL = findQueryURL(bundleName: "TreeSitterLanguages_TreeSitterCSSQueries") { TreeSitterCSSQueries.Query.highlightsFileURL }
        case .kotlin:
            queryURL = findQueryURL(bundleName: "swifted_swifted", fileName: "kotlin") { Bundle.module.url(forResource: "kotlin", withExtension: "scm") }
        case .groovy, .gradle:
            queryURL = findQueryURL(bundleName: "swifted_swifted", fileName: "groovy") { Bundle.module.url(forResource: "groovy", withExtension: "scm") }
        }
        
        if let url = queryURL {
            do {
                let data = try Data(contentsOf: url)
                let query = try SwiftTreeSitter.Query(language: tsLang, data: data)
                self.currentQuery = query
                await QueryCache.shared.set(lang, query: query)
            } catch {
                self.currentQuery = nil
                print("QUERY COMPILATION FAILED FOR \(lang.rawValue): \(error)")
            }
        } else {
            self.currentQuery = nil
            print("QUERY URL IS NIL FOR \(lang.rawValue)")
        }
    }
    
    func applyEdit(startByte: UInt32, oldEndByte: UInt32, newEndByte: UInt32, startPoint: Point, oldEndPoint: Point, newEndPoint: Point) {
        let edit = InputEdit(startByte: startByte, oldEndByte: oldEndByte, newEndByte: newEndByte,
                             startPoint: startPoint, oldEndPoint: oldEndPoint, newEndPoint: newEndPoint)
        tree?.edit(edit)
    }
    
    func highlight(text: String) -> [(NSRange, String)] {
        guard let _ = currentTsLanguage, let query = currentQuery else { return [] }
        
        // Use old tree for incremental parsing
        tree = parser.parse(tree: tree, string: text)
        
        guard let tree = tree else { return [] }
        
        var highlights = [(NSRange, String)]()
        
        let cursor = query.execute(in: tree)
        
        while let match = cursor.next() {
            for capture in match.captures {
                guard let captureName = query.captureName(for: capture.index) else { continue }
                
                var token: String? = nil
                // Try full capture first
                if colorMap.keys.contains(captureName) {
                    token = captureName
                } else {
                    let parts = captureName.components(separatedBy: ".")
                    for part in parts {
                        if colorMap.keys.contains(part) {
                            token = part
                            break
                        }
                    }
                }
                
                if let token = token {
                    let nsRange = capture.node.range
                    // Sanity check to avoid out of bounds
                    if nsRange.location + nsRange.length <= (text as NSString).length {
                        highlights.append((nsRange, token))
                    }
                }
            }
        }
        
        return highlights
    }
}
