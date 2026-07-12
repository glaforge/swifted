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
import WebKit

struct PreviewView: NSViewRepresentable {
    var fileURL: URL
    
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, @unchecked Sendable {
        var parent: PreviewView
        var loadedURL: URL?
        var loadedContentHash: Int?
        var magnificationObservation: NSKeyValueObservation?
        weak var webView: WKWebView?
        
        init(_ parent: PreviewView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "scrollHandler", let dict = message.body as? [String: CGFloat], let x = dict["x"], let y = dict["y"], let url = loadedURL {
                ViewStateStore.shared.saveScrollPosition(CGPoint(x: x, y: y), for: url)
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = loadedURL {
                if let mag = ViewStateStore.shared.getMagnification(for: url) {
                    if webView.magnification != mag { webView.magnification = mag }
                } else {
                    if webView.magnification != 1.0 { webView.magnification = 1.0 }
                }
                
                if let pos = ViewStateStore.shared.getScrollPosition(for: url) {
                    webView.evaluateJavaScript("window.scrollTo(\(pos.x), \(pos.y))", completionHandler: nil)
                }
            }
        }
        
        @MainActor @objc func handleZoomIn() {
            if let wv = webView, wv.window != nil { wv.animator().magnification += 0.2 }
        }
        
        @MainActor @objc func handleZoomOut() {
            if let wv = webView, wv.window != nil { wv.animator().magnification -= 0.2 }
        }
        
        @MainActor @objc func handleZoomReset() {
            if let wv = webView, wv.window != nil { wv.animator().magnification = 1.0 }
        }
        
        deinit {
            magnificationObservation?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground") // For transparent background
        webView.allowsMagnification = true
        
        // Inject color-scheme meta tag to support dark mode text automatically
        let scriptSource = """
        let meta = document.createElement('meta');
        meta.name = 'color-scheme';
        meta.content = 'light dark';
        document.head.appendChild(meta);
        """
        let script = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
        
        // Inject script to track scrolling
        let scrollScriptSource = """
        window.addEventListener('scroll', function() {
            window.webkit.messageHandlers.scrollHandler.postMessage({x: window.scrollX, y: window.scrollY});
        });
        """
        let scrollScript = WKUserScript(source: scrollScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(scrollScript)
        
        webView.configuration.userContentController.add(context.coordinator, name: "scrollHandler")
        webView.navigationDelegate = context.coordinator
        
        context.coordinator.webView = webView
        context.coordinator.magnificationObservation = webView.observe(\.magnification, options: [.new]) { [weak coordinator = context.coordinator] (wv, change) in
            Task { @MainActor in
                if let url = coordinator?.loadedURL, let mag = change.newValue {
                    ViewStateStore.shared.saveMagnification(mag, for: url)
                }
            }
        }
        
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleZoomIn), name: .zoomIn, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleZoomOut), name: .zoomOut, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleZoomReset), name: .zoomReset, object: nil)
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let ext = fileURL.pathExtension.lowercased()
        
        do {
            let content = try String(contentsOf: fileURL)
            let contentHash = content.hashValue
            
            if context.coordinator.loadedURL == fileURL && context.coordinator.loadedContentHash == contentHash {
                return // Already loaded this exact content
            }
            context.coordinator.loadedURL = fileURL
            context.coordinator.loadedContentHash = contentHash
            
            if ext == "html" || ext == "htm" {
                webView.loadHTMLString(content, baseURL: fileURL.deletingLastPathComponent())
            } else if ext == "md" || ext == "markdown" {
                // Load local assets
                let jsURL = Bundle.module.url(forResource: "marked.min", withExtension: "js")
                let cssURL = Bundle.module.url(forResource: "github-markdown.min", withExtension: "css")
                
                let jsContent = (try? String(contentsOf: jsURL!)) ?? ""
                let cssContent = (try? String(contentsOf: cssURL!)) ?? ""
                
                // Escape markdown to inject into JS template literal
                // We must escape backslashes, backticks, and dollar signs to prevent JS syntax errors/interpolation
                let escapedMarkdown = content
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "$", with: "\\$")
                
                let htmlTemplate = """
                <!DOCTYPE html>
                <html>
                <head>
                  <meta charset="utf-8">
                  <style>
                    \(cssContent)
                    body {
                        box-sizing: border-box;
                        min-width: 200px;
                        max-width: 980px;
                        margin: 0 auto;
                        padding: 45px;
                    }
                    @media (prefers-color-scheme: dark) {
                        body {
                            background-color: transparent; /* match webview transparent background */
                        }
                    }
                  </style>
                  <script>
                    \(jsContent)
                  </script>
                </head>
                <body class="markdown-body">
                  <div id="content"></div>
                  <script>
                    document.getElementById('content').innerHTML = marked.parse(`\(escapedMarkdown)`);
                  </script>
                </body>
                </html>
                """
                webView.loadHTMLString(htmlTemplate, baseURL: fileURL.deletingLastPathComponent())
            }
        } catch {
            let errorHTML = "<html><body><h3>Error loading file:</h3><p>\(error.localizedDescription)</p></body></html>"
            webView.loadHTMLString(errorHTML, baseURL: nil)
        }
    }
}
