//
//  ContentView.swift
//  ColoringPrototype
//
//  Created by Brian C K on 03.02.26.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Global Variables
// Pixel buffer
var workingPixels: [Pixel]? = nil
var workingWidth: Int = 0
var workingHeight: Int = 0


// View

struct ContentView: View {
    // State Variables
    @State private var imageFrame: CGRect = .zero
    @State private var renderedImageSize: CGSize = .zero
    @State private var didRunTest = false
    
    // Image state
    @State private var filledImage: CGImage? = nil

    // Selected fill color
    @State private var selectedFill: Pixel = Pixel(r: 255, g: 0, b: 0, a: 255)
    
    @State private var history: [[Pixel]] = []
    @State private var historyLimit: Int = 10
    @State private var snapshotThreshold: Int = 500
    
    // Palette definition (RGBA Pixel and display Color)
    private let palette: [(Pixel, Color)] = [
        (Pixel(r: 255, g: 255, b: 255, a: 255), .white),
        (Pixel(r: 255, g: 0, b: 0, a: 255), .red),
        (Pixel(r: 0, g: 255, b: 0, a: 255), .green),
        (Pixel(r: 0, g: 0, b: 255, a: 255), .blue),
        (Pixel(r: 255, g: 255, b: 0, a: 255), .yellow),
        (Pixel(r: 255, g: 165, b: 0, a: 255), .orange),
        (Pixel(r: 255, g: 0, b: 255, a: 255), Color(red: 1, green: 0, blue: 1)),
        (Pixel(r: 0, g: 255, b: 255, a: 255), Color(red: 0, green: 1, blue: 1))
    ]
    
    // Body
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Group {
                    if let filledImage {
                        Image(decorative: filledImage, scale: 1.0)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image("drawing01")
                            .resizable()
                            .scaledToFit()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(
                    GeometryReader { imageGeo in
                        Color.clear
                            .onAppear {
                                imageFrame = imageGeo.frame(in: .named("imageSpace"))
                                renderedImageSize = imageGeo.size
                            }
                            .onChange(of: imageGeo.size) { _, _ in
                                imageFrame = imageGeo.frame(in: .named("imageSpace"))
                                renderedImageSize = imageGeo.size
                            }
                    }
                )
                .overlay(alignment: .trailing) {
                    PaletteView(
                        palette: palette,
                        selectedFill: selectedFill,
                        onSelect: { selectedFill = $0 },
                        onReset: {
                            filledImage = nil
                            loadWorkingBuffer()
                            history.removeAll()
                        },
                        canUndo: !history.isEmpty,
                        onUndo: {
                            guard let previous = history.popLast() else { return }
                            workingPixels = previous
                            filledImage = makeImage(from: previous, width: workingWidth, height: workingHeight)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .coordinateSpace(name: "imageSpace")
            .onAppear {
                guard workingPixels == nil else { return }
                loadWorkingBuffer()
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("imageSpace"))
                    .onEnded { value in
                        if imageFrame.contains(value.location) {
                            let localX = value.location.x - imageFrame.minX
                            let localY = value.location.y - imageFrame.minY

                            let scaleX = imagePixels.width / renderedImageSize.width
                            let scaleY = imagePixels.height / renderedImageSize.height

                            let pixelX = Int(localX * scaleX)
                            let pixelY = Int(localY * scaleY)

                            // Ensure tap is within image pixel bounds
                            guard pixelX >= 0, pixelY >= 0,
                                  pixelX < Int(workingWidth), pixelY < Int(workingHeight) else { return }

                            guard var pixels = workingPixels else { return }
                            
                            // Nudge seed if the tapped pixel is classified as a line (radius-2 ring search)
                            var startX = pixelX
                            var startY = pixelY
                            let tappedIndex = startY * workingWidth + startX
                            if tappedIndex >= 0 && tappedIndex < pixels.count {
                                let tappedPixel = pixels[tappedIndex]
                                if isLinePixel(tappedPixel) {
                                    var foundSeed: (Int, Int)? = nil
                                    let maxRadius = 2
                                    outer: for r in 1...maxRadius {
                                        for dy in -r...r {
                                            for dx in -r...r {
                                                if abs(dx) != r && abs(dy) != r { continue }
                                                let nx = startX + dx
                                                let ny = startY + dy
                                                if nx >= 0 && ny >= 0 && nx < workingWidth && ny < workingHeight {
                                                    let p = pixels[ny * workingWidth + nx]
                                                    if !isLinePixel(p) {
                                                        foundSeed = (nx, ny)
                                                        break outer
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    if let s = foundSeed {
                                        startX = s.0
                                        startY = s.1
                                    } else {
                                        // Surrounded by lines; abort fill
                                        return
                                    }
                                }
                            }

                            let changed = floodFill(
                                pixels: &pixels,
                                width: workingWidth,
                                height: workingHeight,
                                startX: startX,
                                startY: startY,
                                fill: selectedFill
                            )
                            
                            guard changed > 0 else { return }
                            
                            // Only snapshot when the fill region is substantial
                            if changed > snapshotThreshold {
                                if let current = workingPixels {
                                    history.append(current)
                                    if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
                                }
                            }
                            
                            // Only run halo post-process for larger fills
                            if changed > snapshotThreshold {
                                eatHalo(pixels: &pixels, width: workingWidth, height: workingHeight, fill: selectedFill, passes: 1)
                            }
                            
                            workingPixels = pixels
                            filledImage = makeImage(from: pixels, width: workingWidth, height: workingHeight)
                        }
                    }
            )
        }
    }
}

// MARK: - Extracted subviews and helpers

private struct PaletteView: View {
    let palette: [(Pixel, Color)]
    let selectedFill: Pixel
    let onSelect: (Pixel) -> Void
    let onReset: () -> Void
    let canUndo: Bool
    let onUndo: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<palette.count, id: \.self) { idx in
                let entry = palette[idx]
                Circle()
                    .fill(entry.1)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(isSelected(entry.0) ? Color.white : Color.clear, lineWidth: 3)
                    )
                    .onTapGesture {
                        onSelect(entry.0)
                    }
            }
            Button {
                onUndo()
            } label: {
                Text("Undo")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.white.opacity(canUndo ? 0.2 : 0.08))
                    )
                    .foregroundStyle(canUndo ? .white : .gray)
            }
            .disabled(!canUndo)
            .accessibilityIdentifier("undoButton")
            
            Button {
                onReset()
            } label: {
                Text("Reset")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.white.opacity(0.2))
                    )
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("resetButton")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .fixedSize(horizontal: true, vertical: false)
        .padding(.trailing, 8)
    }
    
    private func isSelected(_ p: Pixel) -> Bool {
        selectedFill.r == p.r &&
        selectedFill.g == p.g &&
        selectedFill.b == p.b &&
        selectedFill.a == p.a
    }
}

// Removed ImageGeometryOverlay, ImageGeometry, ImageGeometryPreferenceKey structures as instructed


// Helper methods

let imagePixels = imagePixelSize(named: "drawing01")

#if canImport(UIKit)
func imagePixelSize(named name: String) -> CGSize {
    guard
        let uiImage = UIImage(named: name),
        let cgImage = uiImage.cgImage
    else { return .zero }
    return CGSize(width: cgImage.width, height: cgImage.height)
}
#elseif canImport(AppKit)
func imagePixelSize(named name: String) -> CGSize {
    guard let nsImage = NSImage(named: NSImage.Name(name)) else { return .zero }
    // Prefer CGImage pixel size when available
    if let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        return CGSize(width: cgImage.width, height: cgImage.height)
    }
    // Fallback to size in points scaled by pixelsPerPoint
    let pixelsPerPoint = NSScreen.main?.backingScaleFactor ?? 2.0
    return CGSize(width: nsImage.size.width * pixelsPerPoint, height: nsImage.size.height * pixelsPerPoint)
}
#else
func imagePixelSize(named name: String) -> CGSize { .zero }
#endif

func loadWorkingBuffer() {
    #if canImport(UIKit)
    guard
        let uiImage = UIImage(named: "drawing01"),
        let cgImage = uiImage.cgImage
    else { return }
    #elseif canImport(AppKit)
    guard
        let nsImage = NSImage(named: NSImage.Name("drawing01")),
        let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return }
    #endif

    let (pixels, w, h) = loadPixelBuffer(from: cgImage)
    workingPixels = pixels
    workingWidth = w
    workingHeight = h
}


// Load image -> Pixel buffer
// Pixel buffer structure
struct Pixel {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
}

func loadPixelBuffer(from cgImage: CGImage) -> ([Pixel], Int, Int) {
    let width = cgImage.width
    let height = cgImage.height

    // Allocate pixel storage
    var pixels = Array(
        repeating: Pixel(r: 0, g: 0, b: 0, a: 0),
        count: width * height
    )

    // Create a CGContext that writes directly into our pixel array
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = width * MemoryLayout<Pixel>.size

    // Use premultipliedLast to match Pixel layout (RGBA, 8 bits each)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return ([], 0, 0)
    }

    // Draw the image into the context to populate the pixel buffer
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    return (pixels, width, height)
}

// Treat dark pixels as boundary/line pixels
func isLinePixel(_ p: Pixel) -> Bool {
    let luminance = (Int(p.r) * 299 + Int(p.g) * 587 + Int(p.b) * 114) / 1000
    return luminance < 40 && p.a > 240
}

// Manhattan distance between two pixels' RGB components
func colorDistance(_ a: Pixel, _ b: Pixel) -> Int {
    let dr = Int(a.r) - Int(b.r)
    let dg = Int(a.g) - Int(b.g)
    let db = Int(a.b) - Int(b.b)
    return abs(dr) + abs(dg) + abs(db)
}

// Halo post-process helpers

func luminance(_ p: Pixel) -> Int {
    (Int(p.r) * 299 + Int(p.g) * 587 + Int(p.b) * 114) / 1000
}

func eatHalo(
    pixels: inout [Pixel],
    width: Int,
    height: Int,
    fill: Pixel,
    passes: Int = 1
) {
    guard width > 2, height > 2 else { return }
    for _ in 0..<passes {
        var next = pixels
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let p = pixels[i]
                if isLinePixel(p) { continue }
                if p.r == fill.r && p.g == fill.g && p.b == fill.b && p.a == fill.a { continue }
                if luminance(p) < 200 { continue }
                let neighbors = [
                    pixels[i - 1], pixels[i + 1],
                    pixels[i - width], pixels[i + width]
                ]
                if neighbors.contains(where: { $0.r == fill.r && $0.g == fill.g && $0.b == fill.b && $0.a == fill.a }) {
                    next[i] = fill
                }
            }
        }
        pixels = next
    }
}

// Flood fill algorithm
func floodFill(
    pixels: inout [Pixel],
    width: Int,
    height: Int,
    startX: Int,
    startY: Int,
    fill: Pixel
) -> Int {
    let index = startY * width + startX
    let target = pixels[index]

    // Do not fill lines
    if isLinePixel(target) {
        return 0
    }

    if target.r == fill.r &&
       target.g == fill.g &&
       target.b == fill.b &&
       target.a == fill.a {
        return 0
    }

    var changed = 0
    var queue: [(Int, Int)] = [(startX, startY)]
    var head = 0

    while head < queue.count {
        let (x, y) = queue[head]
        head += 1
        if x < 0 || y < 0 || x >= width || y >= height { continue }

        let i = y * width + x
        let p = pixels[i]

        if !isLinePixel(p) && colorDistance(p, target) <= 60 {
            if pixels[i].r != fill.r || pixels[i].g != fill.g || pixels[i].b != fill.b || pixels[i].a != fill.a {
                pixels[i] = fill
                changed += 1
            }

            queue.append((x + 1, y))
            queue.append((x - 1, y))
            queue.append((x, y + 1))
            queue.append((x, y - 1))
        }
    }
    return changed
}


// Convert pixels -> Image
func makeImage(from pixels: [Pixel], width: Int, height: Int) -> CGImage {
    let data = pixels.withUnsafeBytes { Data($0) }

    let provider = CGDataProvider(data: data as CFData)!

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
    )!
}


// Test
#if canImport(UIKit)
func testFloodFill() {
    guard
        let uiImage = UIImage(named: "drawing01"),
        let cgImage = uiImage.cgImage
    else { return }

    var (pixels, w, h) = loadPixelBuffer(from: cgImage)

    let changed = floodFill(
        pixels: &pixels,
        width: w,
        height: h,
        startX: w / 2,
        startY: h / 2,
        fill: Pixel(r: 255, g: 0, b: 0, a: 255)
    )

    let filled = makeImage(from: pixels, width: w, height: h)
    print("Flood fill complete: changed=\(changed)", filled)
}
#elseif canImport(AppKit)
func testFloodFill() {
    guard
        let nsImage = NSImage(named: NSImage.Name("drawing01")),
        let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return }

    var (pixels, w, h) = loadPixelBuffer(from: cgImage)

    let changed = floodFill(
        pixels: &pixels,
        width: w,
        height: h,
        startX: w / 2,
        startY: h / 2,
        fill: Pixel(r: 255, g: 0, b: 0, a: 255)
    )

    let filled = makeImage(from: pixels, width: w, height: h)
    print("Flood fill complete: changed=\(changed)", filled)
}
#else
func testFloodFill() {}
#endif


#Preview {
    ContentView()
}

