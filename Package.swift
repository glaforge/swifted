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
// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swifted",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter.git", from: "0.8.0"),
        .package(url: "https://github.com/simonbs/TreeSitterLanguages.git", branch: "main")
    ],
    targets: [
        .target(
            name: "TreeSitterKotlin",
            path: "Grammars/tree-sitter-kotlin",
            exclude: [
                "Cargo.lock",
                "Cargo.toml",
                "Makefile",
                "binding.gyp",
                "bindings/c",
                "bindings/go",
                "bindings/node",
                "bindings/python",
                "bindings/rust",
                "grammar.js",
                "package.json",
                "package-lock.json",
                "pyproject.toml",
                "setup.py",
                "test",
                "examples",
                ".editorconfig",
                ".github",
                ".gitignore",
                ".gitattributes",
                "CONTRIBUTING.md",
                "Icon128.png",
                "LICENSE",
                "Package.swift",
                "README.md",
                "go.mod",
                "grammar-reference.js",
                "playground-screenshot.png",
                "queries",
                "tools",
                "tree-sitter.json",
            ],
            sources: [
                "src/parser.c",
                "src/scanner.c",
            ],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterGroovy",
            path: "Grammars/tree-sitter-groovy",
            exclude: [
                "Cargo.lock",
                "Cargo.toml",
                "Makefile",
                "binding.gyp",
                "bindings/c",
                "bindings/go",
                "bindings/node",
                "bindings/python",
                "bindings/rust",
                "grammar.js",
                "package.json",
                "package-lock.json",
                "pnpm-lock.yaml",
                "pyproject.toml",
                "setup.py",
                "test",
                "examples",
                ".editorconfig",
                ".github",
                ".gitignore",
                ".gitattributes",
                "LICENSE",
                "Package.swift",
                "README.md",
                "build",
                "node_modules",
                "tree-sitter",
            ],
            sources: [
                "src/parser.c",
            ],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
        .executableTarget(
            name: "swifted",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "TreeSitterJava", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJavaScript", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterTypeScript", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterMarkdown", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterBash", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterPython", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJSON", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterSwift", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterGo", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterC", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCPP", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterHTML", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCSS", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJavaQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJavaScriptQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterTypeScriptQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterMarkdownQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterBashQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterPythonQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJSONQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterSwiftQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterGoQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCPPQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterHTMLQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCSSQueries", package: "TreeSitterLanguages"),
                "TreeSitterKotlin",
                "TreeSitterGroovy"
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "swiftedTests",
            dependencies: ["swifted"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
