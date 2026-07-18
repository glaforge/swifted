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
import PDFKit

struct NativePDFViewer: NSViewRepresentable {
    var fileURL: URL
    
    class Coordinator: NSObject, @unchecked Sendable {
        var currentURL: URL?
        var scaleObservation: NSKeyValueObservation?
        weak var pdfView: PDFView?
        var boundsObserver: NSObjectProtocol?
        
        @MainActor @objc func handleZoomIn() {
            if let pv = pdfView, pv.window != nil {
                pv.zoomIn(nil)
                if let url = currentURL { ViewStateStore.shared.saveMagnification(pv.scaleFactor, autoScales: false, for: url) }
            }
        }
        
        @MainActor @objc func handleZoomOut() {
            if let pv = pdfView, pv.window != nil {
                pv.zoomOut(nil)
                if let url = currentURL { ViewStateStore.shared.saveMagnification(pv.scaleFactor, autoScales: false, for: url) }
            }
        }
        
        @MainActor @objc func handleZoomReset() {
            if let pv = pdfView, pv.window != nil {
                pv.autoScales = true
                if let url = currentURL { ViewStateStore.shared.saveMagnification(pv.scaleFactor, autoScales: true, for: url) }
            }
        }
        
        deinit {
            scaleObservation?.invalidate()
            if let obs = boundsObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        
        context.coordinator.scaleObservation = pdfView.observe(\.scaleFactor, options: [.new]) { [weak coordinator = context.coordinator] (pv, change) in
            if let url = coordinator?.currentURL, let scale = change.newValue {
                Task { @MainActor in
                    ViewStateStore.shared.saveMagnification(scale, autoScales: pv.autoScales, for: url)
                }
            }
        }
        
        if let scrollView = pdfView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
            scrollView.contentView.postsBoundsChangedNotifications = true
            context.coordinator.boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak coordinator = context.coordinator] _ in
                if let url = coordinator?.currentURL {
                    Task { @MainActor in
                        ViewStateStore.shared.saveScrollPosition(scrollView.contentView.bounds.origin, for: url)
                    }
                }
            }
        }
        
        context.coordinator.pdfView = pdfView
        
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleZoomIn), name: .zoomIn, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleZoomOut), name: .zoomOut, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.handleZoomReset), name: .zoomReset, object: nil)
        
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        if context.coordinator.currentURL != fileURL {
            context.coordinator.currentURL = fileURL
            
            if let document = PDFDocument(url: fileURL) {
                nsView.document = document
                
                let savedMag = ViewStateStore.shared.getMagnification(for: fileURL)
                let savedAutoScales = ViewStateStore.shared.getAutoScales(for: fileURL)
                let savedPos = ViewStateStore.shared.getScrollPosition(for: fileURL)
                
                DispatchQueue.main.async {
                    if let auto = savedAutoScales {
                        if auto {
                            nsView.autoScales = true
                        } else if let mag = savedMag {
                            nsView.scaleFactor = mag
                        }
                    } else if let mag = savedMag {
                        nsView.scaleFactor = mag
                    } else {
                        nsView.autoScales = true
                    }
                    
                    if let pos = savedPos, let scrollView = nsView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
                        scrollView.contentView.scroll(to: pos)
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                    }
                }
            } else {
                nsView.document = nil
            }
        }
    }
}
