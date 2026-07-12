//
//  Copyright 2026 The Swifted Authors
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
import XCTest
@testable import swifted

final class swiftedTests: XCTestCase {
    func testHighlighterPerf() async throws {
        let url = URL(fileURLWithPath: "Sources/swifted/Resources/marked.min.js")
        let text = try String(contentsOf: url, encoding: .utf8)
        
        let h = Highlighter()
        let start = CFAbsoluteTimeGetCurrent()
        await h.setLanguage(fromExtension: "js")
        let langTime = CFAbsoluteTimeGetCurrent()
        print("Language loaded in \(langTime - start) s")
        
        let tokens = await h.highlight(text: text)
        let hiTime = CFAbsoluteTimeGetCurrent()
        print("Highlight computed in \(hiTime - langTime) s, found \(tokens.count) tokens")
    }
}
