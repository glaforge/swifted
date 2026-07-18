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

struct FileItem: Hashable, Identifiable {
    let id: URL
    let url: URL
    var children: [FileItem]?
    
    var name: String { url.lastPathComponent }
}

struct FlatFileItem: Identifiable {
    let id: URL
    let item: FileItem
    let depth: Int
}

struct SidebarView: View {
    @Binding var selectedFile: URL?
    @State private var files: [FileItem] = []
    @State private var expandedStates: Set<URL> = []
    @State private var showNewFileAlert = false
    @State private var newFileName = ""
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var itemToRename: URL?
    @State private var showRenameAlert = false
    @State private var renameTargetName = ""
    @State private var itemToDelete: URL?
    @State private var showDeleteAlert = false
    @Binding var rootURL: URL
    @AppStorage("appFontSize") private var appFontSize: AppFontSize = .medium
    
    @State private var eventMonitor: Any?
    
    var flatFiles: [FlatFileItem] {
        func flatten(_ files: [FileItem], depth: Int) -> [FlatFileItem] {
            var result = [FlatFileItem]()
            for file in files {
                result.append(FlatFileItem(id: file.url, item: file, depth: depth))
                if expandedStates.contains(file.url), let children = file.children {
                    result.append(contentsOf: flatten(children, depth: depth + 1))
                }
            }
            return result
        }
        return flatten(files, depth: 0)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedFile) {
                ForEach(flatFiles) { flatItem in
                    SidebarRow(flatItem: flatItem, expandedStates: $expandedStates, selectedFile: $selectedFile, onRename: startRename, onDelete: startDelete)
                        .id(flatItem.id)
                }
            }
            .onChange(of: selectedFile) { _, newValue in
                if let newSelection = newValue {
                    proxy.scrollTo(newSelection)
                }
            }
        }
        .navigationTitle("Explorer")
        .onAppear {
            loadFiles()
            setupEventMonitor()
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        .onChange(of: expandedStates) {
            loadFiles()
        }
        .toolbar {
            Button(action: { showNewFileAlert = true }) {
                Image(systemName: "plus").font(appFontSize.uiFont)
            }
            .controlSize(appFontSize.controlSize)
            .help("New File")
            
            Button(action: { showNewFolderAlert = true }) {
                Image(systemName: "folder.badge.plus").font(appFontSize.uiFont)
            }
            .controlSize(appFontSize.controlSize)
            .help("New Folder")
            
            Button(action: openPicker) {
                Image(systemName: "folder").font(appFontSize.uiFont)
            }
            .controlSize(appFontSize.controlSize)
            .help("Open Folder")
            
            Button(action: loadFiles) {
                Image(systemName: "arrow.clockwise").font(appFontSize.uiFont)
            }
            .controlSize(appFontSize.controlSize)
            .help("Refresh")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenFilePicker"))) { _ in
            openPicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NewFile"))) { _ in
            showNewFileAlert = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NewFolder"))) { _ in
            showNewFolderAlert = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RenameItem"))) { _ in
            if let selected = selectedFile {
                startRename(url: selected)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DeleteItem"))) { _ in
            if let selected = selectedFile {
                startDelete(url: selected)
            }
        }
        .alert("New File", isPresented: $showNewFileAlert) {
            TextField("File name", text: $newFileName)
            Button("Create") { createNewFile() }
            Button("Cancel", role: .cancel) { newFileName = "" }
        }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") { createNewFolder() }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .alert("Rename", isPresented: $showRenameAlert) {
            TextField("New name", text: $renameTargetName)
            Button("Rename") { renameItem() }
            Button("Cancel", role: .cancel) { itemToRename = nil }
        }
        .alert("Delete", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteItem() }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: {
            Text("Are you sure you want to delete '\(itemToDelete?.lastPathComponent ?? "")'?")
        }
    }
    
    private func openPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            // If they picked a file, we could just set the root to its folder, or just set selectedFile.
            // But if they pick a folder, we want it to be the new root.
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            
            if isDir.boolValue {
                self.rootURL = url
                self.loadFiles()
            } else {
                // If it's a file, we select it, and maybe change root to its parent
                self.rootURL = url.deletingLastPathComponent()
                self.loadFiles()
                self.selectedFile = url
            }
        }
    }
    
    private func loadFiles() {
        files = getFileItems(for: rootURL)
    }
    
    private func getFileItems(for url: URL) -> [FileItem] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) else {
            return []
        }
        
        var items: [FileItem] = []
        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    let children = expandedStates.contains(fileURL) ? getFileItems(for: fileURL) : []
                    items.append(FileItem(id: fileURL, url: fileURL, children: children))
                } else {
                    items.append(FileItem(id: fileURL, url: fileURL, children: nil))
                }
            }
        }
        
        // Sort directories first, then files
        return items.sorted {
            if $0.children != nil && $1.children == nil { return true }
            if $0.children == nil && $1.children != nil { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    
    private func getTargetFolder() -> URL {
        if let selected = selectedFile {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: selected.path, isDirectory: &isDir), isDir.boolValue {
                return selected
            } else {
                return selected.deletingLastPathComponent()
            }
        }
        return rootURL
    }
    
    private func createNewFile() {
        guard !newFileName.isEmpty else { return }
        let targetFolder = getTargetFolder()
        let newURL = targetFolder.appendingPathComponent(newFileName)
        
        FileManager.default.createFile(atPath: newURL.path, contents: Data())
        newFileName = ""
        
        if targetFolder != rootURL {
            expandedStates.insert(targetFolder)
        }
        loadFiles()
        selectedFile = newURL
    }
    
    private func createNewFolder() {
        guard !newFolderName.isEmpty else { return }
        let targetFolder = getTargetFolder()
        let newURL = targetFolder.appendingPathComponent(newFolderName)
        
        try? FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        newFolderName = ""
        
        if targetFolder != rootURL {
            expandedStates.insert(targetFolder)
        }
        loadFiles()
        selectedFile = newURL
    }
    
    private func startRename(url: URL) {
        itemToRename = url
        renameTargetName = url.lastPathComponent
        showRenameAlert = true
    }
    
    private func renameItem() {
        guard let oldURL = itemToRename, !renameTargetName.isEmpty else { return }
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(renameTargetName)
        
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            if selectedFile == oldURL || selectedFile?.path.hasPrefix(oldURL.path + "/") == true {
                // If it was the selected file itself, update the selection
                if selectedFile == oldURL {
                    selectedFile = newURL
                } else if let selected = selectedFile {
                    let suffix = selected.path.dropFirst(oldURL.path.count)
                    let newSelectedPath = newURL.path + suffix
                    selectedFile = URL(fileURLWithPath: newSelectedPath)
                }
            }
        } catch {
            print("Failed to rename: \(error)")
        }
        
        itemToRename = nil
        loadFiles()
    }
    
    private func startDelete(url: URL) {
        itemToDelete = url
        showDeleteAlert = true
    }
    
    private func deleteItem() {
        guard let url = itemToDelete else { return }
        do {
            try FileManager.default.removeItem(at: url)
            if selectedFile == url || selectedFile?.path.hasPrefix(url.path + "/") == true {
                selectedFile = nil
            }
        } catch {
            print("Failed to delete: \(error)")
        }
        itemToDelete = nil
        loadFiles()
    }
    
    private func setupEventMonitor() {
        if eventMonitor != nil { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 123 is Left Arrow, 124 is Right Arrow
            if event.keyCode == 123 || event.keyCode == 124 {
                // Check if the current firstResponder is an NSTableView (which backs SwiftUI Lists on macOS)
                if let firstResponder = NSApp.keyWindow?.firstResponder {
                    let typeName = String(describing: type(of: firstResponder))
                    if typeName.contains("TableView") || typeName.contains("OutlineView") || typeName.contains("List") {
                        let direction: MoveCommandDirection = event.keyCode == 123 ? .left : .right
                        handleMoveCommand(direction)
                        return nil // Consume the event
                    }
                }
            }
            return event
        }
    }
    
    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        let flats = flatFiles
        guard !flats.isEmpty else { return }
        
        var currentIndex = -1
        if let selected = selectedFile {
            currentIndex = flats.firstIndex(where: { $0.id == selected }) ?? -1
        }
        
        switch direction {
        case .up:
            if currentIndex > 0 {
                selectedFile = flats[currentIndex - 1].id
            } else if currentIndex == -1 {
                selectedFile = flats.last?.id
            }
        case .down:
            if currentIndex < flats.count - 1 && currentIndex != -1 {
                selectedFile = flats[currentIndex + 1].id
            } else if currentIndex == -1 {
                selectedFile = flats.first?.id
            }
        case .right:
            if currentIndex != -1 {
                let flatItem = flats[currentIndex]
                if flatItem.item.children != nil {
                    if !expandedStates.contains(flatItem.id) {
                        expandedStates.insert(flatItem.id)
                        loadFiles()
                    } else if currentIndex < flats.count - 1 {
                        if flats[currentIndex + 1].depth > flatItem.depth {
                            selectedFile = flats[currentIndex + 1].id
                        }
                    }
                }
            }
        case .left:
            if currentIndex != -1 {
                let flatItem = flats[currentIndex]
                if flatItem.item.children != nil && expandedStates.contains(flatItem.id) {
                    expandedStates.remove(flatItem.id)
                    loadFiles()
                } else {
                    let parentURL = flatItem.id.deletingLastPathComponent()
                    if parentURL.path.hasPrefix(rootURL.path) && parentURL != rootURL {
                        selectedFile = parentURL
                    }
                }
            }
        @unknown default:
            break
        }
    }
}

struct SidebarRow: View {
    let flatItem: FlatFileItem
    @Binding var expandedStates: Set<URL>
    @Binding var selectedFile: URL?
    var onRename: (URL) -> Void
    var onDelete: (URL) -> Void
    @AppStorage("appFontSize") private var appFontSize: AppFontSize = .medium
    
    var item: FileItem { flatItem.item }
    
    var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedStates.contains(item.url) },
            set: { isExpanding in
                if isExpanding {
                    expandedStates.insert(item.url)
                } else {
                    expandedStates.remove(item.url)
                }
            }
        )
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if item.children != nil {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(appFontSize.uiFont)
                    .foregroundColor(.secondary)
                    .frame(width: appFontSize.uiSize, alignment: .center)
                    .onTapGesture {
                        withAnimation {
                            isExpanded.wrappedValue.toggle()
                        }
                    }
            } else {
                Spacer()
                    .frame(width: appFontSize.uiSize)
            }
            
            Label(item.name, systemImage: item.children != nil ? "folder" : "doc")
                .font(appFontSize.uiFont)
                .foregroundColor(selectedFile == item.url ? .white : (item.children != nil ? .blue : .secondary))
                .lineLimit(1)
        }
        .padding(.leading, CGFloat(flatItem.depth) * appFontSize.uiSize)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if item.children != nil {
                withAnimation { isExpanded.wrappedValue.toggle() }
            }
        }
        .simultaneousGesture(TapGesture(count: 1).onEnded {
            selectedFile = item.url
        })
        .contextMenu {
            Button("Rename...") { onRename(item.url) }
            Button("Delete...") { onDelete(item.url) }
        }
        .tag(item.url)
    }
}
