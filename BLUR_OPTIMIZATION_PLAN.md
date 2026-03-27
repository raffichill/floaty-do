# Backdrop Blur Performance Optimization Plan

## Summary

Replace the per-frame `SCScreenshotManager` + `CIGaussianBlur` pipeline with a
continuous `SCStream` at quarter resolution, GPU-resident blur, and zero-copy
display. The existing `PanelSurfaceView.swift` `compositedTranslucent` mode is
the only code path affected.

## Current Product Decision

For now, FloatyDo ships with a solid panel background and the transparency /
opacity controls are hidden from Settings.

We tried both exposed options:

- full transparency is always behaviorally correct, but it regularly hurts
  readability when dense content sits behind the panel
- system blur looks better when it works, but stale backdrop states break trust
  because the panel can show the wrong thing

The current product call is that a consistently correct solid surface is better
than either of those compromised experiences. This plan stays here so we can
revisit live blur later if Apple improves the system path or if we decide to
build a custom blur renderer.

---

## Current Architecture (what to replace)

The `compositedTranslucent` path in `PanelSurfaceView` currently does this
**12 times per second**:

1. `SCShareableContent.excludingDesktopWindows()` — IPC to WindowServer to
   enumerate every window/app/display. ~10-30ms per call.
2. Build an `SCContentFilter` with exclusion logic. Allocates each frame.
3. `SCScreenshotManager.captureImage()` — one-shot capture with full
   setup/teardown per frame.
4. `CIFilter("CIGaussianBlur")` at **full backing resolution** (e.g.,
   1600×1200px on Retina). Radius is 20-36 backing pixels.
5. `CIContext.createCGImage()` — forces GPU→CPU readback.
6. Wrap in `NSImage`, assign to `NSImageView.image` — re-uploads to GPU.

### Why it's slow

| Bottleneck | Cost |
|---|---|
| `SCShareableContent` every frame | 10-30ms IPC per frame |
| `SCScreenshotManager` one-shot | Full setup/teardown overhead × 12/s |
| Blur at full Retina resolution | ~1.92M pixels × 73 taps = ~140M samples |
| GPU→CPU→GPU round-trip | Two expensive transfers per frame |

---

## Target Architecture

```
SCStream (full display, 1/4 res, set up once)
  → CMSampleBuffer arrives on background queue
    → IOSurface from sample buffer (zero-copy)
    → CIImage(ioSurface:) — no CPU copy
    → CIGaussianBlur (radius ~9 at quarter res ≈ radius 36 at full res)
    → .cropped(to: windowRect / 4) — only compute pixels we need
    → CIContext.render(_:to: metalTexture) — stays on GPU
    → CAMetalLayer displays the texture — zero CPU involvement
```

---

## Implementation Steps

### Step 1: Create a persistent `SCStream`

Replace the per-frame screenshot approach with a long-lived stream.

**New private properties on `PanelSurfaceView`:**

```swift
private var captureStream: SCStream?
private var captureStreamOutput: BackdropStreamOutput?  // see Step 2
private var cachedContentFilter: SCContentFilter?
private var cachedDisplayID: CGDirectDisplayID?
private var cachedDisplayBounds: CGRect = .zero
```

**Stream setup** (called once when entering `compositedTranslucent` mode, and
when the display changes):

```swift
private func startBackdropStream() async throws {
    // Stop any existing stream
    try? await captureStream?.stopCapture()

    guard let window, let screen = window.screen,
          let displayID = screen.deviceDescription[
              NSDeviceDescriptionKey("NSScreenNumber")
          ] as? CGDirectDisplayID else { return }

    let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true
    )
    guard let display = content.displays.first(where: {
        $0.displayID == displayID
    }) else { return }

    // Exclude our own app
    let excludedApps = content.applications.filter {
        $0.processID == ProcessInfo.processInfo.processIdentifier
    }
    let filter = SCContentFilter(
        display: display,
        excludingApplications: excludedApps,
        exceptingWindows: []
    )

    let config = SCStreamConfiguration()
    let scale = screen.backingScaleFactor
    let displaySize = screen.frame.size

    // Capture at 1/4 point resolution (1/2 backing scale)
    config.width = Int(displaySize.width / 2)
    config.height = Int(displaySize.height / 2)
    config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 FPS
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = false
    config.backgroundColor = CGColor.clear
    config.captureDynamicRange = .SDR
    config.queueDepth = 3  // triple buffer

    cachedDisplayID = displayID
    cachedDisplayBounds = screen.frame
    cachedContentFilter = filter

    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
    let output = BackdropStreamOutput(surfaceView: self)
    stream.addStreamOutput(output, type: .screen,
                           sampleHandlerQueue: .global(qos: .userInteractive))
    try await stream.startCapture()

    captureStream = stream
    captureStreamOutput = output
}
```

**Key design decisions:**
- Capture the **full display**, not just the window rect. This means we never
  need to reconfigure the stream during drag/resize — we just change which
  region we crop from.
- Capture at **half point resolution** (= quarter backing resolution on 2x
  Retina). The blur destroys high-frequency detail anyway.
- 30 FPS is smooth enough. The current 12 FPS will feel better at 30.
- `queueDepth = 3` for triple buffering — prevents stalls.

### Step 2: Stream output handler

Create a class that receives frames and processes them:

```swift
private final class BackdropStreamOutput: NSObject, SCStreamOutput {
    weak var surfaceView: PanelSurfaceView?
    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false
    ])

    init(surfaceView: PanelSurfaceView) {
        self.surfaceView = surfaceView
    }

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutput.OutputType) {
        guard type == .screen,
              let surfaceView,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }

        // Zero-copy: wrap the pixel buffer directly as a CIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Get the current window rect in capture coordinates
        // (this is the only thing that changes per frame)
        let cropRect = surfaceView.currentCropRect()
        guard !cropRect.isNull else { return }

        // Apply blur — CIImage is lazy, so this just builds the graph.
        // CIContext will only compute pixels inside cropRect.
        let blurRadius = surfaceView.currentBlurRadius()
        let blurred = ciImage
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur",
                            parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: cropRect)

        // Render to the display layer (see Step 3)
        surfaceView.renderBlurredFrame(blurred, context: ciContext,
                                       outputSize: cropRect.size)
    }
}
```

**Why `CIImage(cvPixelBuffer:)` instead of `CIImage(cgImage:)`:** The pixel
buffer from SCStream is backed by an IOSurface that lives on the GPU. Wrapping
it in a CIImage is zero-copy. The old path went
GPU→CGImage(CPU)→CIImage→blur→CGImage(CPU)→NSImage→GPU. This stays on the GPU
the entire time.

**Blur radius adjustment:** Since we're capturing at 1/2 point scale (1/4
backing pixels), the blur radius should be halved:

```swift
func currentBlurRadius() -> Double {
    // appliedPreferences.backdropBlurRadius is designed for full-res.
    // At 1/2 point scale, halve the radius for equivalent visual result.
    return appliedPreferences.backdropBlurRadius / 2.0
}
```

### Step 3: Display with `CAMetalLayer` or IOSurface-backed layer

Replace the `NSImageView` (`compositedBackdropView`) with a layer that can
receive GPU-rendered content without a CPU round-trip.

**Option A: Render into the layer's backing store via CIContext**

The simplest approach — use `CIContext.render(_:to:bounds:colorSpace:)` to
render directly into a `CALayer`'s IOSurface backing. No `CAMetalLayer` needed.

```swift
@MainActor
func renderBlurredFrame(_ image: CIImage, context: CIContext,
                        outputSize: CGSize) {
    guard let layer = compositedBackdropView.layer else { return }

    // Ensure the layer has a contents backing
    let bounds = CGRect(origin: .zero, size: outputSize)

    // Render CIImage directly to a CGImage — but use the Metal-backed context
    // so this is a GPU→GPU blit, not a readback
    if let rendered = context.createCGImage(image, from: image.extent) {
        DispatchQueue.main.async {
            layer.contents = rendered
        }
    }
}
```

> **Note:** If profiling shows `createCGImage` is still a bottleneck, upgrade
> to a `CAMetalLayer` approach where you `render(_:to: MTLTexture)` and set
> `metalLayer.nextDrawable().texture` as the target. But start simple — at 1/4
> resolution the `createCGImage` path is likely fast enough.

**Option B (advanced): CAMetalLayer**

```swift
// Replace compositedBackdropView (NSImageView) with a CAMetalLayer
private let metalDevice = MTLCreateSystemDefaultDevice()!
private lazy var metalLayer: CAMetalLayer = {
    let layer = CAMetalLayer()
    layer.device = metalDevice
    layer.pixelFormat = .bgra8Unorm
    layer.framebufferOnly = true
    layer.contentsScale = window?.backingScaleFactor ?? 2.0
    return layer
}()

private lazy var ciContext = CIContext(mtlDevice: metalDevice, options: [
    .cacheIntermediates: false
])

func renderBlurredFrame(_ image: CIImage, outputSize: CGSize) {
    metalLayer.drawableSize = outputSize
    guard let drawable = metalLayer.nextDrawable() else { return }
    let commandBuffer = metalDevice.makeCommandQueue()!.makeCommandBuffer()!

    ciContext.render(image,
                     to: drawable.texture,
                     commandBuffer: commandBuffer,
                     bounds: image.extent,
                     colorSpace: CGColorSpaceCreateDeviceRGB())

    commandBuffer.present(drawable)
    commandBuffer.commit()
}
```

This is truly zero-copy GPU-only, but adds complexity. Recommend starting with
Option A and only upgrading if profiling shows it matters.

### Step 4: Crop rect calculation

Add a method that computes the window's position in capture-texture coordinates.
This replaces the per-frame `makeBackdropCaptureRequest()`:

```swift
func currentCropRect() -> CGRect {
    guard let window, let screen = window.screen else { return .null }

    let boundsInWindow = convert(bounds, to: nil)
    let rectOnScreen = window.convertToScreen(boundsInWindow)
    let displayFrame = screen.frame

    // Convert to display-local coordinates (origin top-left for CG)
    let localRect = CGRect(
        x: rectOnScreen.minX - displayFrame.minX,
        y: displayFrame.maxY - rectOnScreen.maxY,
        width: rectOnScreen.width,
        height: rectOnScreen.height
    )

    // Scale to capture texture coordinates (we captured at 1/2 point res)
    let captureScale = 0.5
    return CGRect(
        x: localRect.origin.x * captureScale,
        y: localRect.origin.y * captureScale,
        width: localRect.width * captureScale,
        height: localRect.height * captureScale
    ).intersection(CGRect(
        origin: .zero,
        size: CGSize(
            width: displayFrame.width * captureScale,
            height: displayFrame.height * captureScale
        )
    ))
}
```

**This is the key to smooth dragging:** the crop rect is just arithmetic on the
current window frame. No async calls, no IPC, no stream reconfiguration. It
updates instantly on whatever thread processes the frame.

### Step 5: Stream lifecycle management

**When to start the stream:**
- When entering `compositedTranslucent` mode (in `apply(preferences:)`)
- When the window becomes visible

**When to stop the stream:**
- `stopBackdropCapture()` — add `try? await captureStream?.stopCapture()`
- When entering `solid` or `liveTranslucent` mode
- When window is occluded (optional optimization)
- In `deinit`

**When to rebuild the stream** (stop + start):
- Display change (user moves window to different monitor)
- Screen resolution change
- The existing `handleActiveApplicationChange` should NOT rebuild the stream —
  it just needs to keep receiving frames

**Suspension support:** The existing `setBackdropUpdatesSuspended` /
`areBackdropUpdatesSuspended` mechanism should pause/resume the stream rather
than the timer:

```swift
func setBackdropUpdatesSuspended(_ suspended: Bool) {
    if suspended {
        backdropUpdateSuspensionCount += 1
        // Don't stop the stream — just ignore incoming frames
        // (check areBackdropUpdatesSuspended in the stream output handler)
    } else {
        backdropUpdateSuspensionCount -= 1
        if backdropUpdateSuspensionCount == 0, needsBackdropRefreshAfterResume {
            needsBackdropRefreshAfterResume = false
            // Stream is still running, just start accepting frames again
        }
    }
}
```

### Step 6: Remove dead code

Once the stream approach works, remove:
- `backdropRefreshTimer` and all timer logic (`updateBackdropRefreshLoop`)
- `pendingBackdropCaptureRequest` / `BackdropCaptureRequest` struct
- `captureBlurredBackdropImage(for:)` static method
- `blurredImage(from:radius:)` static method
- `runBackdropCaptureLoop()` async method
- `makeBackdropCaptureRequest()` method
- `scheduleBackdropCapture()` method
- `backdropRefreshInterval` constant

The notification observers in `installBackdropRefreshObserversIfNeeded` should
remain — they're still useful for triggering stream rebuilds on display changes
and for the `liveTranslucent` path.

---

## Performance Comparison

| Metric | Current | Optimized |
|---|---|---|
| Window server queries/sec | 12 (`SCShareableContent`) | ~0 (once at setup) |
| Capture method | One-shot screenshot × 12/s | Continuous stream |
| Capture resolution | Full backing (e.g. 1600×1200) | 1/4 backing (400×300) |
| Pixels blurred per frame | ~1.92M | ~120K (just crop region) |
| Blur radius (backing px) | 20-36 | 5-9 (same visual result) |
| Blur samples per pixel | ~41-73 | ~11-19 |
| GPU→CPU transfers/frame | 2 | 0 (Option B) or 1 (Option A) |
| Frame rate | 12 FPS | 30 FPS |
| Latency during drag | 83ms + capture overhead | ~33ms, no reconfig needed |

---

## Things to Watch Out For

1. **Thread safety of `currentCropRect()`**: It reads `window.frame` which is
   main-thread-only. Either dispatch to main to read it, or cache the frame on
   main thread and read the cached value from the stream output queue.

2. **Stream error handling**: `SCStream` can fail silently if the user revokes
   screen recording permission. Implement `SCStreamDelegate.stream(_:didStopWithError:)`
   to fall back to the solid surface.

3. **Display changes**: If the user drags the window to a different monitor, the
   stream's display filter is wrong. Detect this via
   `NSWindow.didChangeScreenNotification` (or check `window.screen` in the
   existing `didMoveNotification` handler) and rebuild the stream.

4. **CIContext thread safety**: `CIContext` is thread-safe for rendering, but
   create one per `BackdropStreamOutput` instance, not a shared static. The
   existing `static let backdropBlurContext` should be replaced.

5. **Memory**: SCStream with `queueDepth = 3` holds 3 pixel buffers. At 1/4
   backing resolution of a 5K display that's ~3 × 1.4MB = ~4.2MB. Negligible.

6. **Preserve the suspension mechanism**: The `setBackdropUpdatesSuspended` API
   is called externally. Make sure the stream output handler checks
   `areBackdropUpdatesSuspended` and drops frames rather than stopping the
   stream entirely (stopping/starting has latency).
