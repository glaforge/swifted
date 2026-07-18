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

struct ViewState {
    var scrollPosition: CGPoint?
    var magnification: CGFloat?
    var autoScales: Bool?
}

@MainActor
class ViewStateStore {
    static let shared = ViewStateStore()
    var states: [URL: ViewState] = [:]
    
    private init() {}
    
    func saveScrollPosition(_ pos: CGPoint, for url: URL) {
        if states[url] == nil {
            states[url] = ViewState()
        }
        states[url]?.scrollPosition = pos
    }
    
    func saveMagnification(_ mag: CGFloat, autoScales: Bool? = nil, for url: URL) {
        if states[url] == nil {
            states[url] = ViewState()
        }
        states[url]?.magnification = mag
        if let autoScales = autoScales {
            states[url]?.autoScales = autoScales
        }
    }
    
    func getScrollPosition(for url: URL) -> CGPoint? {
        return states[url]?.scrollPosition
    }
    
    func getMagnification(for url: URL) -> CGFloat? {
        return states[url]?.magnification
    }
    
    func getAutoScales(for url: URL) -> Bool? {
        return states[url]?.autoScales
    }
}
