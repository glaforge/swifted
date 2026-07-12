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
import SwiftUI

@main
struct SwiftedApp: App {
    init() {
        if CommandLine.arguments.contains("--test") {
            Task {
                let success = await TestRunner.runAll()
                exit(success ? 0 : 1)
            }
        } else if CommandLine.arguments.contains("--bench") {
            print("Running Benchmark...")
            let h = Highlighter()
            Task {
                let url = URL(fileURLWithPath: "Sources/swifted/Resources/marked.min.js")
                let text = try! String(contentsOf: url, encoding: .utf8)
                let start = CFAbsoluteTimeGetCurrent()
                await h.setLanguage(fromExtension: "js")
                let langTime = CFAbsoluteTimeGetCurrent()
                print("Language loaded in \(langTime - start) s")
                let tokens = await h.highlight(text: text)
                let hiTime = CFAbsoluteTimeGetCurrent()
                print("Highlight computed in \(hiTime - langTime) s, found \(tokens.count) tokens")
                exit(0)
            }
            // Let the RunLoop continue so the Task can execute, but don't show UI
        } else {
            // Promote the SPM executable to a regular app that appears in the Dock and receives keyboard focus
            NSApplication.shared.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @AppStorage("showLineNumbers") var showLineNumbers: Bool = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    NotificationCenter.default.post(name: Notification.Name("OpenFileURL"), object: url)
                }
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button(showLineNumbers ? "Hide Line Numbers" : "Show Line Numbers") {
                    showLineNumbers.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .newItem) {
                Button("New File...") {
                    NotificationCenter.default.post(name: Notification.Name("NewFile"), object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("New Folder...") {
                    NotificationCenter.default.post(name: Notification.Name("NewFolder"), object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Rename...") {
                    NotificationCenter.default.post(name: Notification.Name("RenameItem"), object: nil)
                }
                .keyboardShortcut(.return, modifiers: [])
                
                Button("Delete...") {
                    NotificationCenter.default.post(name: Notification.Name("DeleteItem"), object: nil)
                }
                .keyboardShortcut(.delete, modifiers: .command)
                
                Divider()
                
                Button("Open...") {
                    NotificationCenter.default.post(name: Notification.Name("OpenFilePicker"), object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
