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

    func centerCroppedSquare() -> UIImage {
        guard let cgImage = self.cgImage else { return self }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        guard size.width > 0, size.height > 0 else { return self }

        let contentRect = trimmedContentRect(of: cgImage, size: size)
        let side = min(contentRect.width, contentRect.height)
        let square = CGRect(
            x: contentRect.origin.x + (contentRect.width - side) / 2,
            y: contentRect.origin.y + (contentRect.height - side) / 2,
            width: side,
            height: side
        )

        guard let cropped = cgImage.cropping(to: square) else { return self }
        return UIImage(cgImage: cropped, scale: self.scale, orientation: self.imageOrientation)
    }

    /// Scans the image at reduced resolution to find the bounding box of non-black content,
    /// removing uniform (black) borders
    private func trimmedContentRect(of cgImage: CGImage, size: CGSize) -> CGRect {
        let maxDim = 160
        let scale = min(1.0, CGFloat(maxDim) / max(size.width, size.height))
        let w = max(1, Int(size.width * scale))
        let h = max(1, Int(size.height * scale))

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * w
        var raw = [UInt8](repeating: 0, count: w * h * bytesPerPixel)
        guard let ctx = CGContext(
            data: &raw,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return CGRect(origin: .zero, size: size) }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        let isBlack: (Int, Int) -> Bool = { x, y in
            let o = y * bytesPerRow + x * bytesPerPixel
            let r = Double(raw[o]) / 255.0
            let g = Double(raw[o + 1]) / 255.0
            let b = Double(raw[o + 2]) / 255.0
            return (r + g + b) / 3.0 < 0.08
        }

        let blackRatioThreshold = 0.9

        func columnIsBorder(_ x: Int) -> Bool {
            var black = 0
            for y in 0..<h where isBlack(x, y) { black += 1 }
            return Double(black) / Double(h) >= blackRatioThreshold
        }
        func rowIsBorder(_ y: Int) -> Bool {
            var black = 0
            for x in 0..<w where isBlack(x, y) { black += 1 }
            return Double(black) / Double(w) >= blackRatioThreshold
        }

        var minX = 0
        while minX < w && columnIsBorder(minX) { minX += 1 }
        var maxX = w - 1
        while maxX > minX && columnIsBorder(maxX) { maxX -= 1 }
        var minY = 0
        while minY < h && rowIsBorder(minY) { minY += 1 }
        var maxY = h - 1
        while maxY > minY && rowIsBorder(maxY) { maxY -= 1 }

        guard maxX > minX, maxY > minY else { return CGRect(origin: .zero, size: size) }

        let rx = CGFloat(minX) / scale
        let ry = CGFloat(minY) / scale
        let rw = CGFloat(maxX - minX + 1) / scale
        let rh = CGFloat(maxY - minY + 1) / scale
        return CGRect(x: rx, y: ry, width: rw, height: rh)
    }
}
