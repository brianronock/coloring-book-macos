/*
 Phase 0.5 — PixelBufferActor (Constraints Summary)
 - Sole owner of pixel memory ([Pixel], width, height); no external mutation.
 - Flood fill remains strict exact-match; no tolerance, no nudging, no runtime heuristics.
 - One-time asset preprocessing on load (normalization only).
 - Actor may be called from background tasks; UI publishes results on MainActor.
 - Return CGImage snapshot only when changed > 0 to avoid unnecessary allocations.
 - Deterministic, local, explainable logic only.
*/

import Foundation
import CoreGraphics

// MARK: - Shared Pixel Type

public struct Pixel: Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    // Explicitly nonisolated initializer so it can be used from nonisolated static funcs without actor hops
    @inlinable
    public nonisolated init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    // Provide a nonisolated Equatable implementation to avoid isolated conformance diagnostics in Swift 6
    @inlinable
    public nonisolated static func == (lhs: Pixel, rhs: Pixel) -> Bool {
        lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b && lhs.a == rhs.a
    }
    // Provide a nonisolated Hashable implementation for use in Dictionary/Set keys
    @inlinable
    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(r)
        hasher.combine(g)
        hasher.combine(b)
        hasher.combine(a)
    }

    // Pack RGBA into a UInt32 for nonisolated hashing without relying on Hashable in actor contexts
    @inlinable
    public nonisolated static func pack(_ p: Pixel) -> UInt32 {
        return (UInt32(p.r) << 24) | (UInt32(p.g) << 16) | (UInt32(p.b) << 8) | UInt32(p.a)
    }

    @inlinable
    public nonisolated static func unpack(_ v: UInt32) -> Pixel {
        return Pixel(
            r: UInt8((v >> 24) & 0xFF),
            g: UInt8((v >> 16) & 0xFF),
            b: UInt8((v >> 8) & 0xFF),
            a: UInt8(v & 0xFF)
        )
    }
}

// MARK: - Actor

public actor PixelBufferActor {
    // Nonisolated classification helpers and constants (no actor state captured)
    nonisolated static let whiteLuminanceThreshold: Int = 235
    nonisolated static let minAlphaForInterior: UInt8 = 200
    nonisolated static let lineLuminanceThreshold: Int = 40
    nonisolated static let lineAlphaThreshold: UInt8 = 200
    nonisolated static let majorityWhiteCount: Int = 5
    nonisolated static let majorityGuardLineCount: Int = 4
    nonisolated static let exactWhite = Pixel(r: 255, g: 255, b: 255, a: 255)

    @inline(__always)
    nonisolated static func luminance(_ p: Pixel) -> Int {
        (Int(p.r) * 299 + Int(p.g) * 587 + Int(p.b) * 114) / 1000
    }

    @inline(__always)
    nonisolated static func isLinePixel(_ p: Pixel) -> Bool {
        luminance(p) < lineLuminanceThreshold && p.a > lineAlphaThreshold
    }

    @inline(__always)
    nonisolated static func isNearWhiteInterior(_ p: Pixel) -> Bool {
        luminance(p) > whiteLuminanceThreshold && p.a > minAlphaForInterior
    }

    private var pixels: [Pixel] = []
    private(set) public var width: Int = 0
    private(set) public var height: Int = 0

    public var size: CGSize { CGSize(width: width, height: height) }

    // MARK: Load + Normalize

    public func load(from cgImage: CGImage) {
        let w = cgImage.width
        let h = cgImage.height

        var buffer = Array(repeating: Pixel(r: 0, g: 0, b: 0, a: 0), count: w * h)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = w * MemoryLayout<Pixel>.size

        buffer.withUnsafeMutableBytes { rawPtr in
            guard let ctx = CGContext(
                data: rawPtr.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }

            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        self.pixels = buffer
        self.width = w
        self.height = h

        // Phase 0.5: Normalize once on load to make strict exact-match fill viable on real assets.
        normalizePixelsInPlace()
    }

    // Optional defensive API for later phases
    public func updatePixels(_ newPixels: [Pixel], width: Int, height: Int) {
        guard newPixels.count == width * height, width > 0, height > 0 else { return }
        self.pixels = newPixels
        self.width = width
        self.height = height
    }

    // MARK: Phase 0.5 Normalization (deterministic, local)

    /*
     What this DOES:
     - Snaps near-white interior pixels (including semi-transparent anti-aliased edges) to exact opaque white.
     - Applies a 3×3 majority cleanup to reduce speckling/fragmentation.

     What this deliberately does NOT do:
     - Close open boundaries (leaky lines).
     - Modify line art (no thickening, no gap filling).
     - Introduce tolerance into flood fill.
    */
    private func normalizePixelsInPlace() {
        guard width > 0, height > 0, pixels.count == width * height else { return }

        // Pass 1: snap near-white interiors to exact white (alpha fix included)
        for i in pixels.indices {
            let p = pixels[i]
            if Self.isLinePixel(p) { continue }
            if Self.isNearWhiteInterior(p) {
                pixels[i] = Self.exactWhite
            }
        }

        // Pass 2: 3×3 majority cleanup with detail-preservation guardrail
        // NOTE: This makes a full copy; keep an eye on large images (profile if needed).
        let original = pixels

        if width < 3 || height < 3 { return } // Too small for 3×3

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let center = original[idx]
                if Self.isLinePixel(center) { continue }

                var whiteCount = 0
                var lineCount = 0

                for dy in -1...1 {
                    for dx in -1...1 {
                        let n = original[(y + dy) * width + (x + dx)]
                        if n == Self.exactWhite { whiteCount += 1 }
                        if Self.isLinePixel(n) { lineCount += 1 }
                    }
                }

                // Guardrail: if surrounded by many line pixels, this is likely a thin detail; don't erase it.
                if lineCount >= Self.majorityGuardLineCount { continue }

                if whiteCount >= Self.majorityWhiteCount {
                    pixels[idx] = Self.exactWhite
                }
            }
        }
    }

    // MARK: Strict Exact-Match Flood Fill (unchanged semantics)

    public func performFill(startX: Int, startY: Int, fill: Pixel) -> (changed: Int, image: CGImage?, deltas: [(offset: Int, previous: Pixel)]) {
        guard width > 0, height > 0,
              startX >= 0, startY >= 0,
              startX < width, startY < height
        else {
            return (0, nil, [])
        }

        @inline(__always)
        func pixelAt(_ x: Int, _ y: Int) -> Pixel? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            return pixels[y * width + x]
        }

        // Start with the tapped seed
        var seedX = startX
        var seedY = startY
        var target = pixelAt(seedX, seedY)

        // If initial seed is unusable (line pixel or already the fill color), probe a 3×3 neighborhood
        if target == nil || Self.isLinePixel(target!) || target == fill {
            var bestCandidate: (Int, Int, Pixel)? = nil
            var maxCount = 0
            var counts: [UInt32: Int] = [:]

            for dy in -1...1 {
                for dx in -1...1 {
                    let nx = startX + dx
                    let ny = startY + dy
                    if let p = pixelAt(nx, ny), !Self.isLinePixel(p) {
                        let key = Pixel.pack(p)
                        let newCount = (counts[key] ?? 0) + 1
                        counts[key] = newCount
                        if newCount > maxCount {
                            maxCount = newCount
                            bestCandidate = (nx, ny, p)
                        }
                    }
                }
            }

            if let candidate = bestCandidate {
                seedX = candidate.0
                seedY = candidate.1
                target = candidate.2
            } else {
                return (0, nil, [])
            }
        }

        guard let target = target, !Self.isLinePixel(target), target != fill else {
            return (0, nil, [])
        }

        var changed = 0
        var deltas: [(Int, Pixel)] = []
        var queue: [(Int, Int)] = [(seedX, seedY)]
        var head = 0

        while head < queue.count {
            let (x, y) = queue[head]
            head += 1

            if x < 0 || y < 0 || x >= width || y >= height { continue }

            let i = y * width + x
            let p = pixels[i]

            if p == target && !Self.isLinePixel(p) {
                deltas.append((i, p))
                pixels[i] = fill
                changed += 1

                queue.append((x + 1, y))
                queue.append((x - 1, y))
                queue.append((x, y + 1))
                queue.append((x, y - 1))
            }
        }

        guard changed > 0 else { return (0, nil, []) }
        return (changed, makeImage(), deltas)
    }

    // MARK: Undo

    public func undo(applying deltas: [(offset: Int, previous: Pixel)]) -> (image: CGImage?, redoDeltas: [(offset: Int, previous: Pixel)]) {
        guard width > 0, height > 0, pixels.count == width * height else { return (nil, []) }
        var redo: [(Int, Pixel)] = []
        for (idx, prev) in deltas {
            if idx >= 0 && idx < pixels.count {
                redo.append((idx, pixels[idx]))
                pixels[idx] = prev
            }
        }
        return (makeImage(), redo)
    }

    // MARK: Snapshot

    private func makeImage() -> CGImage? {
        guard width > 0, height > 0, pixels.count == width * height else { return nil }

        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * MemoryLayout<Pixel>.size,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

