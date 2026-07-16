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

extension Notification.Name {
    static let zoomIn = Notification.Name("AppZoomIn")
    static let zoomOut = Notification.Name("AppZoomOut")
    static let zoomReset = Notification.Name("AppZoomReset")
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { self.rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

enum AppFontSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        }
    }
    
    var iconName: String {
        switch self {
        case .small: return "textformat.size.smaller"
        case .medium: return "textformat"
        case .large: return "textformat.size.larger"
        }
    }
    
    var codeSize: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 16
        case .large: return 24
        }
    }
    
    var uiSize: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 16
        case .large: return 22
        }
    }
    
    var controlSize: ControlSize {
        switch self {
        case .small: return .small
        case .medium: return .regular
        case .large: return .large
        }
    }
    
    var uiFont: Font {
        return .system(size: uiSize)
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case code = "Code"
    case preview = "Preview"
    var id: String { self.rawValue }
    
    var iconName: String {
        switch self {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .preview: return "eye"
        }
    }
}

struct ContentView: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("appFontSize") private var appFontSize: AppFontSize = .medium
    @AppStorage("appWordWrap") private var appWordWrap: Bool = false
    
    @State private var rootURL: URL = {
        if CommandLine.arguments.count > 1 {
            let arg = CommandLine.arguments[1]
            let url = URL(fileURLWithPath: arg)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    return url
                } else {
                    return url.deletingLastPathComponent()
                }
            }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }()
    
    @State private var selectedFile: URL? = {
        if CommandLine.arguments.count > 1 {
            let arg = CommandLine.arguments[1]
            let url = URL(fileURLWithPath: arg)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if !isDir.boolValue {
                    return url
                }
            }
        }
        return nil
    }()
    
    @State private var viewMode: ViewMode = .code
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    private var isRenderable: Bool {
        guard let file = selectedFile else { return false }
        let ext = file.pathExtension.lowercased()
        return ["html", "htm", "md", "markdown"].contains(ext)
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedFile: $selectedFile, rootURL: $rootURL)
        } detail: {
            Group {
                if let file = selectedFile {
                    FileViewer(fileURL: file, viewMode: $viewMode)
                } else {
                    Text("Select a file to open")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(minWidth: 800, minHeight: 600)
        .background {
            Button("Toggle Preview") {
                if isRenderable {
                    viewMode = viewMode == .code ? .preview : .code
                }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .hidden()
            
            Button("Toggle Sidebar") {
                if columnVisibility == .all || columnVisibility == .automatic {
                    columnVisibility = .detailOnly
                } else {
                    columnVisibility = .all
                }
            }
            .keyboardShortcut("b", modifiers: .command)
            .hidden()
            
            Button("Zoom In (+)") { NotificationCenter.default.post(name: .zoomIn, object: nil) }
            .keyboardShortcut("+", modifiers: .command)
            .hidden()

            Button("Zoom In (=)") { NotificationCenter.default.post(name: .zoomIn, object: nil) }
            .keyboardShortcut("=", modifiers: .command)
            .hidden()

            Button("Zoom Out") { NotificationCenter.default.post(name: .zoomOut, object: nil) }
            .keyboardShortcut("-", modifiers: .command)
            .hidden()

            Button("Zoom Reset") { NotificationCenter.default.post(name: .zoomReset, object: nil) }
            .keyboardShortcut("0", modifiers: .command)
            .hidden()
        }
        .onChange(of: selectedFile) { _, _ in
            viewMode = .code
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenFileURL"))) { notification in
            if let url = notification.object as? URL {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        rootURL = url
                        selectedFile = nil
                    } else {
                        rootURL = url.deletingLastPathComponent()
                        selectedFile = url
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if let file = selectedFile {
                    CustomTitleView(fileURL: file, rootURL: rootURL)
                } else {
                    Button(action: {}) {
                        Text("swifted").font(.headline).bold()
                    }
                    .buttonStyle(.plain)
                }
            }
            .hideSharedBackgroundIfAvailable()
            
            if isRenderable {
                ToolbarItem(placement: .automatic) {
                    Picker("Mode", selection: $viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Image(systemName: mode.iconName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Toggle Preview Mode")
                    .controlSize(appFontSize.controlSize)
                }
            }
            
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $appWordWrap) {
                    Label("Word Wrap", systemImage: "return")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .help("Toggle Word Wrap")
                .controlSize(appFontSize.controlSize)
            }
            
            ToolbarItem(placement: .automatic) {
                Picker("Font Size", selection: $appFontSize) {
                    ForEach(AppFontSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .help("Select Font Size")
                .controlSize(appFontSize.controlSize)
            }
            
            ToolbarItem(placement: .automatic) {
                Picker("Theme", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Image(systemName: theme.iconName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .help("Select Application Theme")
                .controlSize(appFontSize.controlSize)
            }
        }
        .preferredColorScheme(appTheme.colorScheme)
        .toolbarRole(.editor)
        .navigationTitle("")
        .navigationSubtitle("")
    }
}

struct CustomTitleView: View {
    let fileURL: URL
    let rootURL: URL
    @AppStorage("appFontSize") private var appFontSize: AppFontSize = .medium
    @AppStorage("appWordWrap") private var appWordWrap: Bool = false
    
    var customText: Text {
        let (baseDir, subdirs) = formatPath()
        
        var text = Text(baseDir)
            .font(appFontSize.uiFont)
            .bold()
            .foregroundColor(.primary)
        
        if !subdirs.isEmpty {
            text = text + Text(" / ")
                .font(appFontSize.uiFont)
                .foregroundColor(.secondary.opacity(0.5))
            
            text = text + Text(subdirs.joined(separator: " / "))
                .font(appFontSize.uiFont.weight(.regular))
                .foregroundColor(.secondary)
        }
        
        text = text + Text(" / ")
            .font(appFontSize.uiFont)
            .foregroundColor(.secondary.opacity(0.5))
        
        text = text + Text(fileURL.lastPathComponent)
            .font(appFontSize.uiFont)
            .bold()
            .foregroundColor(.primary)
            
        return text
    }

    var body: some View {
        Button(action: {
            NotificationCenter.default.post(name: Notification.Name("RenameItem"), object: nil)
        }) {
            customText
        }
        .buttonStyle(.plain)
    }
    
    func formatPath() -> (String, [String]) {
        let rootPath = rootURL.path
        let filePath = fileURL.deletingLastPathComponent().path
        
        var baseDir = ""
        var subdirs: [String] = []
        
        if filePath.hasPrefix(rootPath) {
            baseDir = rootURL.lastPathComponent
            let relative = filePath.dropFirst(rootPath.count)
            let relativePath = relative.hasPrefix("/") ? String(relative.dropFirst()) : String(relative)
            if !relativePath.isEmpty {
                subdirs = relativePath.components(separatedBy: "/")
            }
        } else {
            let comps = fileURL.deletingLastPathComponent().pathComponents
            if let first = comps.first {
                baseDir = first
            }
            subdirs = Array(comps.dropFirst())
        }
        
        if subdirs.count > 3 {
            subdirs = ["…", subdirs[subdirs.count - 2], subdirs[subdirs.count - 1]]
        }
        
        return (baseDir, subdirs)
    }
}



struct FileViewer: View {
    var fileURL: URL
    @Binding var viewMode: ViewMode
    
    var body: some View {
        let ext = fileURL.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "tiff", "heic", "webp", "icns", "svg"].contains(ext) {
            if let nsImage = NSImage(contentsOf: fileURL) {
                NativeImageViewer(image: nsImage, fileURL: fileURL)
            } else {
                Text("Failed to load image")
                    .foregroundColor(.secondary)
            }
        } else if ["html", "htm", "md", "markdown"].contains(ext) && viewMode == .preview {
            PreviewView(fileURL: fileURL)
                .id(fileURL)
        } else if ext == "pdf" {
            NativePDFViewer(fileURL: fileURL)
                .id(fileURL)
        } else {
            EditorView(fileURL: fileURL)
                .id(fileURL) // Force a new editor instance if we want, or rely on updateNSView
        }
    }
}

struct NativeImageViewer: NSViewRepresentable {
    var image: NSImage
    var fileURL: URL
    @Environment(\.colorScheme) var colorScheme
    
    class Coordinator: NSObject, @unchecked Sendable {
        var lastImage: NSImage?
        var currentURL: URL?
        var boundsObserver: NSObjectProtocol?
        var magnificationObservation: NSKeyValueObservation?
        weak var scrollView: NSScrollView?
        
        @MainActor @objc func handleZoomIn() {
            if let sv = scrollView, sv.window != nil {
                sv.animator().magnification += 0.2
                if let url = currentURL { ViewStateStore.shared.saveMagnification(sv.magnification, autoScales: false, for: url) }
            }
        }
        
        @MainActor @objc func handleZoomOut() {
            if let sv = scrollView, sv.window != nil {
                sv.animator().magnification -= 0.2
                if let url = currentURL { ViewStateStore.shared.saveMagnification(sv.magnification, autoScales: false, for: url) }
            }
        }
        
        @MainActor @objc func handleZoomReset() {
            if let sv = scrollView, sv.window != nil {
                applyAutoScale(to: sv)
                if let url = currentURL { ViewStateStore.shared.saveMagnification(sv.magnification, autoScales: true, for: url) }
            }
        }
        
        @MainActor func applyAutoScale(to sv: NSScrollView) {
            guard let image = lastImage, image.size.width > 0, image.size.height > 0 else { return }
            let viewSize = sv.contentSize
            let scaleX = viewSize.width / image.size.width
            let scaleY = viewSize.height / image.size.height
            let minScale = min(scaleX, scaleY)
            if minScale < 1.0 {
                if sv.magnification != minScale { sv.magnification = minScale }
            } else {
                if sv.magnification != 1.0 { sv.magnification = 1.0 }
            }
        }
        
        deinit {
            magnificationObservation?.invalidate()
            if let obs = boundsObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 10.0
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.drawsBackground = true
        scrollView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        
        let imageView = FlippedImageView(image: image)
        imageView.frame = CGRect(origin: .zero, size: image.size)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        
        scrollView.documentView = imageView
        
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            if let url = coordinator?.currentURL {
                Task { @MainActor in
                    ViewStateStore.shared.saveScrollPosition(scrollView.contentView.bounds.origin, for: url)
                    if ViewStateStore.shared.getAutoScales(for: url) ?? true {
                        if let sv = coordinator?.scrollView {
                            coordinator?.applyAutoScale(to: sv)
                        }
                    }
                }
            }
        }
        
        context.coordinator.scrollView = scrollView
        context.coordinator.magnificationObservation = scrollView.observe(\.magnification, options: [.new]) { [weak coordinator = context.coordinator] (sv, change) in
            if let url = coordinator?.currentURL, let mag = change.newValue {
                Task { @MainActor in
                    ViewStateStore.shared.saveMagnification(mag, for: url)
                }
            }
        }
        
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleZoomIn), name: .zoomIn, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleZoomOut), name: .zoomOut, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleZoomReset), name: .zoomReset, object: nil)
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let newAppearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        if nsView.appearance != newAppearance {
            nsView.appearance = newAppearance
            nsView.setNeedsDisplay(nsView.bounds)
        }
        
        if let imageView = nsView.documentView as? NSImageView {
            let isNewImage = context.coordinator.lastImage !== image
            
            imageView.image = image
            imageView.frame = CGRect(origin: .zero, size: image.size)
            
            if isNewImage || context.coordinator.currentURL != fileURL {
                context.coordinator.lastImage = image
                context.coordinator.currentURL = fileURL
                
                let savedMag = ViewStateStore.shared.getMagnification(for: fileURL)
                let savedAutoScales = ViewStateStore.shared.getAutoScales(for: fileURL)
                let savedPos = ViewStateStore.shared.getScrollPosition(for: fileURL)
                
                DispatchQueue.main.async {
                    if let auto = savedAutoScales {
                        if auto {
                            context.coordinator.applyAutoScale(to: nsView)
                        } else if let mag = savedMag {
                            if nsView.magnification != mag { nsView.magnification = mag }
                        }
                    } else if let mag = savedMag {
                        if nsView.magnification != mag { nsView.magnification = mag }
                    } else {
                        context.coordinator.applyAutoScale(to: nsView)
                    }
                    
                    if let pos = savedPos {
                        nsView.documentView?.scroll(pos)
                    } else {
                        nsView.documentView?.scroll(.zero)
                    }
                }
            }
        }
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func hideSharedBackgroundIfAvailable() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

class FlippedImageView: NSImageView {
    override var isFlipped: Bool { return true }
}
