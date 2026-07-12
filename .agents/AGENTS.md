# Swifted - Agent Instructions

Welcome to the `swifted` codebase! This document contains project-scoped rules and architectural context to help coding agents navigate and contribute to this project effectively.

## Architecture & Core Technologies

1. **Language & UI Framework**: The app is a native macOS application written in **Swift** and built heavily around **SwiftUI**.
2. **Text Rendering**: We use **TextKit 2** natively (`NSTextContentStorage`, `NSTextLayoutManager`) for performance, particularly to benefit from its lazy layout engine on large files.
   - *CRITICAL*: Because of TextKit 2's lazy layout, DO NOT manually override `NSTextView.frame` heights based on document sizes. For scroll restorations or programmatic updates that invalidate fragments, rely on the asynchronous UI pipeline (e.g. `textView.layoutSubtreeIfNeeded()` or simulating scroll jiggles) to encourage TextKit 2 to lay out fragments.
   - **Line Numbers**: Line numbers are rendered natively using a custom `LineNumberGutterView` that integrates with TextKit 2's layout fragments instead of using legacy TextKit 1 rulers.
3. **Data Structures**: The underlying text buffer uses a custom **Piece Table** implementation (`PieceTable.swift` & `PieceTableTextStorage.swift`) to ensure lightning-fast insertions and deletions for massive files. 
   - Avoid creating new copies of massive strings if possible.
4. **Syntax Highlighting**: We use **SwiftTreeSitter** for syntax parsing (`Highlighter.swift`). Highlighting happens asynchronously. Do NOT block the main thread for highlighting. TreeSitter grammars are stored in the root `Grammars` directory.
5. **State Management**: We maintain global view states using `ViewStateStore.swift` to remember user contexts (like scroll position and semantic zooming/magnification levels per URL). We use `@AppStorage` for app-wide user settings, such as `appFontSize` and `showLineNumbers`.

## Development & Build Workflow

- **Build System**: This is a standard Swift Package Manager executable project.
- **Compiling**: Use `swift build`.
- **Running locally**: Use `killall swifted && swift run swifted <folder_to_open>`.

## Core Components

- `EditorView.swift`: The main code editor view, wrapping `NSTextView` in a `NSViewRepresentable`. It connects the `PieceTableTextStorage` with TextKit 2.
- `LineNumberRulerView.swift`: Provides a custom gutter view (`LineNumberGutterView`) for rendering line numbers correctly alongside TextKit 2 fragments.
- `PreviewView.swift`: Handles rendering HTML and Markdown content (via `WKWebView`).
- `NativeImageViewer`: Custom image viewer logic handled via `ContentView.swift`.
- `SidebarView.swift`: The file explorer panel on the left side of the app.
- `TestRunner.swift`: Custom test suite for asserting functionality across core components (e.g., `PieceTable`, `ViewStateStore`, and `Highlighter`).

## General Guidelines

- **UI Aesthetics**: Keep a sleek, native macOS look. Respect Dark/Light modes.
- **Performance**: Always prioritize parsing/rendering performance. The app is meant to handle massive files smoothly. Avoid synchronous full-document operations.
- **Dependencies**: Do not introduce new heavy dependencies without explicit user consent.
