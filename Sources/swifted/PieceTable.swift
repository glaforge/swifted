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

enum BufferType {
    case original
    case add
}

struct Piece {
    var buffer: BufferType
    var start: Int // UTF-16 offset
    var length: Int // UTF-16 length
}

public class PieceTable {
    private var originalBuffer: NSString
    private var addBuffer: NSMutableString
    private var pieces: [Piece]
    
    public init(text: String = "") {
        self.originalBuffer = text as NSString
        self.addBuffer = NSMutableString()
        self.pieces = []
        if text.utf16.count > 0 {
            self.pieces.append(Piece(buffer: .original, start: 0, length: text.utf16.count))
        }
    }
    
    public var length: Int {
        return pieces.reduce(0) { $0 + $1.length }
    }
    
    public var piecesCount: Int {
        return pieces.count
    }
    
    public func compact() {
        if pieces.count <= 1 { return }
        let currentText = self.text
        self.originalBuffer = currentText as NSString
        self.addBuffer = NSMutableString()
        if currentText.utf16.count > 0 {
            self.pieces = [Piece(buffer: .original, start: 0, length: currentText.utf16.count)]
        } else {
            self.pieces = []
        }
    }
    
    public var text: String {
        let result = NSMutableString()
        for piece in pieces {
            let buffer = piece.buffer == .original ? originalBuffer : addBuffer
            result.append(buffer.substring(with: NSRange(location: piece.start, length: piece.length)))
        }
        return result as String
    }

    public func insert(text: String, at offset: Int) {
        let nsText = text as NSString
        let newPieceStart = addBuffer.length
        let newPieceLength = nsText.length
        addBuffer.append(text)
        
        let newPiece = Piece(buffer: .add, start: newPieceStart, length: newPieceLength)
        
        if pieces.isEmpty {
            pieces.append(newPiece)
            return
        }
        
        var currentOffset = 0
        for (index, piece) in pieces.enumerated() {
            if currentOffset + piece.length >= offset {
                let offsetInPiece = offset - currentOffset
                
                if offsetInPiece == 0 {
                    pieces.insert(newPiece, at: index)
                } else if offsetInPiece == piece.length {
                    if index == pieces.count - 1 {
                        pieces.append(newPiece)
                    } else {
                        pieces.insert(newPiece, at: index + 1)
                    }
                } else {
                    let leftPiece = Piece(buffer: piece.buffer, start: piece.start, length: offsetInPiece)
                    let rightPiece = Piece(buffer: piece.buffer, start: piece.start + offsetInPiece, length: piece.length - offsetInPiece)
                    
                    pieces.remove(at: index)
                    pieces.insert(rightPiece, at: index)
                    pieces.insert(newPiece, at: index)
                    pieces.insert(leftPiece, at: index)
                }
                return
            }
            currentOffset += piece.length
        }
        
        pieces.append(newPiece)
    }

    public func delete(at offset: Int, length deleteLength: Int) {
        if deleteLength <= 0 { return }
        
        var remainingToDelete = deleteLength
        var currentLogicalOffset = 0
        var i = 0
        
        while i < pieces.count && remainingToDelete > 0 {
            let piece = pieces[i]
            
            if currentLogicalOffset + piece.length > offset {
                let offsetInPiece = max(0, offset - currentLogicalOffset)
                let lengthToDeleteInPiece = min(remainingToDelete, piece.length - offsetInPiece)
                
                if offsetInPiece == 0 && lengthToDeleteInPiece == piece.length {
                    pieces.remove(at: i)
                    remainingToDelete -= lengthToDeleteInPiece
                    continue
                } else if offsetInPiece == 0 {
                    pieces[i].start += lengthToDeleteInPiece
                    pieces[i].length -= lengthToDeleteInPiece
                } else if offsetInPiece + lengthToDeleteInPiece == piece.length {
                    pieces[i].length -= lengthToDeleteInPiece
                } else {
                    let rightPiece = Piece(buffer: piece.buffer, start: piece.start + offsetInPiece + lengthToDeleteInPiece, length: piece.length - offsetInPiece - lengthToDeleteInPiece)
                    pieces[i].length = offsetInPiece
                    pieces.insert(rightPiece, at: i + 1)
                }
                
                remainingToDelete -= lengthToDeleteInPiece
            }
            
            currentLogicalOffset += pieces[i].length
            i += 1
        }
    }
}
