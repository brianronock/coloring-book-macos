//
//  ContentView.swift
//  ColoringPrototype
//
//  Phase 0.5 — Strict fill + preprocessing gate + child hint
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ContentView: View {

    // MARK: - Actor
    private let pixelActor = PixelBufferActor()

    // MARK: - Layout tracking
    @State private var imageFrame: CGRect = .zero
    @State private var renderedImageSize: CGSize = .zero

    @State private var pixelSize: CGSize = .zero

    // Start -> freeze
    @State private var isColoringStarted = false
    @State private var fixedCanvasSize: CGSize? = nil

    // Generation token (ignore stale async fill results after reset/reload)
    @State private var generation: Int = 0

    // MARK: - Image state
    @State private var filledImage: CGImage? = nil
    @State private var currentImageName: String = "drawing01"
    @State private var showingImageSelector: Bool = false
    @State private var showingWelcome: Bool = true

    @State private var undoStack: [[(offset: Int, previous: Pixel)]] = []
    private let undoLimit: Int = 10

    @State private var redoStack: [[(offset: Int, previous: Pixel)]] = []
    private let redoLimit: Int = 5

    // MARK: - Palette
    @State private var selectedFill: Pixel = Pixel(r: 255, g: 0, b: 0, a: 255)

    // No black / near-black
    private let palette: [(Pixel, Color)] = [
        // Core bold colors
        (Pixel(r: 255, g: 0, b: 0, a: 255), .red),
        (Pixel(r: 0, g: 140, b: 255, a: 255), Color(red: 0, green: 0.55, blue: 1)),
        (Pixel(r: 0, g: 200, b: 0, a: 255), .green),
        (Pixel(r: 255, g: 200, b: 0, a: 255), .yellow),
        (Pixel(r: 255, g: 120, b: 0, a: 255), .orange),
        (Pixel(r: 190, g: 0, b: 200, a: 255), Color(red: 0.75, green: 0, blue: 0.78)),

        // Additional palette entries (pastels, white, gray)
        (Pixel(r: 255, g: 255, b: 255, a: 255), .white), // white
        (Pixel(r: 38, g: 38, b: 38, a: 255), Color(white: 0.55)), // gray
        (Pixel(r: 242, g: 198, b: 203, a: 255), Color(red: 0.95, green: 0.78, blue: 0.80)), // pastel pink
        (Pixel(r: 242, g: 217, b: 179, a: 255), Color(red: 0.95, green: 0.85, blue: 0.70)), // pastel peach
        (Pixel(r: 250, g: 242, b: 179, a: 255), Color(red: 0.98, green: 0.95, blue: 0.70)), // pastel yellow
        (Pixel(r: 204, g: 237, b: 204, a: 255), Color(red: 0.80, green: 0.93, blue: 0.80)), // pastel mint
        (Pixel(r: 191, g: 224, b: 242, a: 255), Color(red: 0.75, green: 0.88, blue: 0.95)), // pastel blue
        (Pixel(r: 204, g: 204, b: 242, a: 255), Color(red: 0.80, green: 0.80, blue: 0.95)), // pastel lavender
        (Pixel(r: 150, g: 75, b: 0, a: 255), Color(red: 0.59, green: 0.29, blue: 0.00)), // brown
        (Pixel(r: 230, g: 204, b: 230, a: 255), Color(red: 0.90, green: 0.80, blue: 0.90)) // pastel mauve
    ]

    // MARK: - Hint (child UX safety net)

    @State private var consecutiveMisses: Int = 0
    @State private var lastMissPoint: CGPoint? = nil
    @State private var hintVisible: Bool = false
    @State private var lastHintShownAt: Date? = nil
    @State private var hintTask: Task<Void, Never>? = nil

    private let missRadius: CGFloat = 30
    private let hintCooldownSeconds: TimeInterval = 6
    private let hintDismissSeconds: UInt64 = 4

    private let hintText = "Try tapping 🎨 in the middle! ✨"

    // MARK: - Body

    var body: some View {
        GeometryReader { _ in
            ZStack {
                // Image
                Group {
                    if let filledImage {
                        Image(decorative: filledImage, scale: 1.0)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(currentImageName)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    GeometryReader { imageGeo in
                        Color.clear
                            .onAppear {
                                if !isColoringStarted {
                                    imageFrame = imageGeo.frame(in: .named("imageSpace"))
                                    renderedImageSize = imageGeo.size
                                }
                            }
                            .onChange(of: imageGeo.size) { _, _ in
                                if !isColoringStarted {
                                    imageFrame = imageGeo.frame(in: .named("imageSpace"))
                                    renderedImageSize = imageGeo.size
                                }
                            }
                    }
                )

                // Palette + Reset (testing convenience)
                paletteOverlay

                // Back to Main (image selector) button — top-left
                VStack {
                    HStack {
                        Button {
                            showingImageSelector = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2")
                                Text("Back")
                            }
                            .font(.caption.weight(.semibold))
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                            .foregroundStyle(.white)
                        }
                        .padding([.top, .leading], 8)
                        Spacer()
                    }
                    Spacer()
                }
                .sheet(isPresented: $showingImageSelector) {
                    ImageSelectorView(
                        images: (1...12).map { String(format: "drawing%02d", $0) },
                        onSelect: { name in
                            currentImageName = name
                            resetToLayoutMode()
                            showingImageSelector = false
                        }
                    )
                }
                #if os(iOS) || os(tvOS) || os(visionOS)
                .fullScreenCover(isPresented: $showingWelcome) {
                    WelcomeView(start: {
                        showingWelcome = false
                        showingImageSelector = true
                    })
                }
                #else
                .sheet(isPresented: $showingWelcome) {
                    WelcomeView(start: {
                        showingWelcome = false
                        showingImageSelector = true
                    })
                }
                #endif

                // Bottom-left controls: Undo + Redo + Reset
                VStack {
                    Spacer()
                    HStack {
                        Button {
                            guard let last = undoStack.popLast() else { return }
                            Task.detached(priority: .userInitiated) {
                                let result = await pixelActor.undo(applying: last)
                                await MainActor.run {
                                    if let img = result.image { filledImage = img }
                                    // Push redo deltas and cap
                                    redoStack.append(result.redoDeltas)
                                    if redoStack.count > redoLimit { redoStack.removeFirst(redoStack.count - redoLimit) }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.body.weight(.semibold))
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                                .foregroundStyle(.white)
                        }

                        Button {
                            guard let last = redoStack.popLast() else { return }
                            Task.detached(priority: .userInitiated) {
                                // Reapply redo deltas by calling undo with the redo deltas' previous values swapped back
                                // We can reuse `undo(applying:)` because it sets pixels to the provided previous values; here, redo deltas represent the state before undo, so applying them restores the post-fill state.
                                let result = await pixelActor.undo(applying: last)
                                await MainActor.run {
                                    if let img = result.image { filledImage = img }
                                    // Pushing inverse back onto undo stack
                                    undoStack.append(result.redoDeltas)
                                    if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.body.weight(.semibold))
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                                .foregroundStyle(.white)
                        }

                        Button {
                            resetToLayoutMode()
                        } label: {
                            Text("Reset")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.2)))
                                .foregroundStyle(.white)
                        }
                        .accessibilityIdentifier("resetButton")

                        Spacer()
                    }
                    .padding([.leading, .bottom], 8)
                }

                // Start Coloring overlay
                if !isColoringStarted {
                    startOverlay
                } else {
                    lockOverlay
                }

                // Hint overlay
                if hintVisible {
                    hintOverlay
                        .transition(.opacity)
                }
            }
            .coordinateSpace(name: "imageSpace")
            .onAppear {
                Task { await loadImageIntoActor(named: currentImageName) }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("imageSpace"))
                    .onEnded { value in
                        handleTap(at: value.location)
                    }
            )
        }
    }

    // MARK: - UI Pieces

    private var paletteOverlay: some View {
        ScrollView(.vertical, showsIndicators: false) {
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
                        .onTapGesture { selectedFill = entry.0 }
                }
            }
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
        .fixedSize(horizontal: false, vertical: true)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var startOverlay: some View {
        Button {
            isColoringStarted = true
            fixedCanvasSize = renderedImageSize
        } label: {
            Text("Start Coloring")
                .font(.title2)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.accentColor))
                .foregroundColor(.white)
                .shadow(radius: 3)
        }
        .disabled(renderedImageSize == .zero || pixelSize == .zero)
        .opacity((renderedImageSize == .zero || pixelSize == .zero) ? 0.6 : 1.0)
    }

    private var lockOverlay: some View {
        VStack {
            HStack {
                Text("Locked")
                    .font(.caption2)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3)))
                    .foregroundColor(.white)
                    .padding([.top, .leading], 8)
                Spacer()
            }
            Spacer()
        }
    }

    private var hintOverlay: some View {
        Text(hintText)
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.92))
            )
            .foregroundStyle(Color.black)
            .shadow(radius: 6)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint) {
        guard isColoringStarted else { return }
        guard let fixedCanvasSize else { return }
        guard imageFrame.contains(location) else { return }
        guard pixelSize.width > 0, pixelSize.height > 0 else { return }

        // LAYOUT DEBUG: Capture frames/sizes at tap time
        print("Layout Debug: imageFrame=\(imageFrame), renderedImageSize=\(renderedImageSize), fixedCanvasSize=\(String(describing: fixedCanvasSize)), pixelSize=\(pixelSize)")

        let localX = location.x - imageFrame.minX
        let localY = location.y - imageFrame.minY

        // Frozen mapping after Start Coloring
        let scaleX = pixelSize.width / fixedCanvasSize.width
        let scaleY = pixelSize.height / fixedCanvasSize.height

        // FIX: Use round() instead of Int() to avoid systematic truncation offset
        let pixelX = Int(round(localX * scaleX))
        let pixelY = Int(round(localY * scaleY))

        let imgW = Int(pixelSize.width)
        let imgH = Int(pixelSize.height)

        guard pixelX >= 0, pixelY >= 0, pixelX < imgW, pixelY < imgH else { return }

        // DEBUG: Log tap details (remove or #if debug before shipping)
        print("Tap Debug: location=\(location), local=(\(localX),\(localY)), scale=(\(scaleX),\(scaleY)), pixel=(\(pixelX),\(pixelY)), fixedSize=\(fixedCanvasSize), pixelSize=\(pixelSize)")

        let currentGen = generation
        let fill = selectedFill

        Task.detached(priority: .userInitiated) {
            let result = await pixelActor.performFill(startX: pixelX, startY: pixelY, fill: fill)

            await MainActor.run {
                // Ignore stale results (reset/reload happened)
                guard currentGen == generation else { return }

                if result.changed > 0, let img = result.image {
                    filledImage = img
                    // Push deltas for undo; cap size
                    undoStack.append(result.deltas)
                    if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
                    redoStack.removeAll()
                    registerSuccess()
                } else {
                    registerMiss(at: location)
                }
            }
        }
    }

    // MARK: - Hint Logic

    private func registerSuccess() {
        consecutiveMisses = 0
        lastMissPoint = nil
        hideHint()
    }

    private func registerMiss(at point: CGPoint) {
        // Update miss streak only if misses are in the same general area (radius)
        if let last = lastMissPoint {
            let dx = point.x - last.x
            let dy = point.y - last.y
            let dist = sqrt(dx*dx + dy*dy)

            if dist <= missRadius {
                consecutiveMisses += 1
            } else {
                consecutiveMisses = 1
            }
        } else {
            consecutiveMisses = 1
        }

        lastMissPoint = point

        // Trigger after 2 consecutive misses in the same area, with cooldown
        if consecutiveMisses >= 2 {
            let now = Date()
            let canShow: Bool = {
                guard let lastShown = lastHintShownAt else { return true }
                return now.timeIntervalSince(lastShown) >= hintCooldownSeconds
            }()

            if canShow {
                showHint()
            }
        }
    }

    private func showHint() {
        lastHintShownAt = Date()
        hintVisible = true

        hintTask?.cancel()
        hintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: hintDismissSeconds * 1_000_000_000)
            hintVisible = false
        }
    }

    private func hideHint() {
        hintTask?.cancel()
        hintTask = nil
        hintVisible = false
    }

    // MARK: - Lifecycle / Reset

    private func resetToLayoutMode() {
        generation += 1
        hideHint()
        consecutiveMisses = 0
        lastMissPoint = nil

        filledImage = nil
        isColoringStarted = false
        fixedCanvasSize = nil
        undoStack.removeAll()
        redoStack.removeAll()

        Task { await loadImageIntoActor(named: currentImageName) }
    }

    private func loadImageIntoActor(named name: String) async {
        #if canImport(UIKit)
        guard
            let uiImage = UIImage(named: name),
            let cgImage = uiImage.cgImage
        else { return }
        #elseif canImport(AppKit)
        guard
            let nsImage = NSImage(named: NSImage.Name(name)),
            let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        #else
        return
        #endif

        await pixelActor.load(from: cgImage)
        let s = await pixelActor.size
        await MainActor.run { pixelSize = s }
    }

    private func isSelected(_ p: Pixel) -> Bool {
        selectedFill == p
    }
}

#Preview {
    ContentView()
}

