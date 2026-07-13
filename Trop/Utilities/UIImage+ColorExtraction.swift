//
//  UIImage+ColorExtraction.swift
//  Trop
//
//  Created by 686udjie on 13/07/2026.
//

import UIKit
import SwiftUI

extension UIImage {
    /// Extracts a list of dominant vibrant colors from the image.
    /// Returns a fallback set if extraction fails.
    func extractDominantColors() -> [Color] {
        guard let cgImage = self.cgImage else {
            return [Color(red: 0.15, green: 0.15, blue: 0.2), Color(red: 0.05, green: 0.05, blue: 0.08)]
        }
        
        let width = 8
        let height = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return [Color(red: 0.15, green: 0.15, blue: 0.2), Color(red: 0.05, green: 0.05, blue: 0.08)]
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        
        struct RGBA {
            let r: Double
            let g: Double
            let b: Double
            let a: Double
            
            var luminance: Double {
                return 0.299 * r + 0.587 * g + 0.114 * b
            }
            
            var saturation: Double {
                let maxVal = max(r, g, b)
                let minVal = min(r, g, b)
                return maxVal == 0 ? 0 : (maxVal - minVal) / maxVal
            }
        }
        
        var pixels: [RGBA] = []
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = Double(rawData[offset]) / 255.0
                let g = Double(rawData[offset + 1]) / 255.0
                let b = Double(rawData[offset + 2]) / 255.0
                let a = Double(rawData[offset + 3]) / 255.0
                if a > 0.8 {
                    pixels.append(RGBA(r: r, g: g, b: b, a: a))
                }
            }
        }
        
        guard !pixels.isEmpty else {
            return [Color(red: 0.15, green: 0.15, blue: 0.2), Color(red: 0.05, green: 0.05, blue: 0.08)]
        }
        
        // Sort by saturation and luminance
        let sortedByVibrancy = pixels.sorted { p1, p2 in
            let score1 = p1.saturation * 0.8 + (1.0 - abs(p1.luminance - 0.5)) * 0.2
            let score2 = p2.saturation * 0.8 + (1.0 - abs(p2.luminance - 0.5)) * 0.2
            return score1 > score2
        }
        
        let primary = sortedByVibrancy.first ?? RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1.0)
        
        var secondary = primary
        for pixel in sortedByVibrancy {
            let distance = abs(pixel.r - primary.r) + abs(pixel.g - primary.g) + abs(pixel.b - primary.b)
            if distance > 0.4 {
                secondary = pixel
                break
            }
        }
        
        if secondary.r == primary.r && secondary.g == primary.g && secondary.b == primary.b {
            secondary = RGBA(r: max(0, primary.r - 0.2), g: max(0, primary.g - 0.2), b: max(0, primary.b - 0.2), a: 1.0)
        }
        
        return [
            Color(red: primary.r, green: primary.g, blue: primary.b),
            Color(red: secondary.r, green: secondary.g, blue: secondary.b)
        ]
    }
}
