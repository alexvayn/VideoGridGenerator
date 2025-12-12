//
//  Models.swift
//  VideoGridGenerator
//
//  Created by Alexander Vaynshteyn on 12/11/25.
//

import Foundation
import AppKit
import AVFoundation

// MARK: - Frame Data

struct ExtractedFrame {
    let image: NSImage
    let timestamp: CMTime
}
