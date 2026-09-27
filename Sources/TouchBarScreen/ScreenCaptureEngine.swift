@preconcurrency import ScreenCaptureKit
import AppKit
import CoreImage
import CoreMedia

struct CapturableDisplay: Equatable {
    let id: CGDirectDisplayID
    let name: String
    let width: Int
    let height: Int
    let isMain: Bool
}

struct CapturedFrame {
    let image: CGImage
    let cursorPosition: CGPoint
}

enum CaptureError: LocalizedError {
    case displayUnavailable

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            return "所选显示器已不可用，请刷新显示器列表。"
        }
    }
}

final class ScreenCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((CapturedFrame) -> Void)?
    var onCursorPosition: ((CGPoint) -> Void)?
    var onStop: ((Error?) -> Void)?

    private let sampleQueue = DispatchQueue(
        label: "com.local.TouchBarScreen.capture",
        qos: .userInteractive
    )
    private let ciContext = CIContext(options: [
        .cacheIntermediates: false
    ])
    private var stream: SCStream?
    private var cursorTimer: DispatchSourceTimer?
    private var capturedDisplayBounds = CGRect.zero

    func availableDisplays() async throws -> [CapturableDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )

        let screensByID: [CGDirectDisplayID: NSScreen] = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
                guard let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber else {
                    return nil
                }
                return (CGDirectDisplayID(number.uint32Value), screen)
            }
        )
        let mainDisplayID = CGMainDisplayID()

        return content.displays.map { display in
            let screen = screensByID[display.displayID]
            let fallbackName = display.displayID == mainDisplayID
                ? "主显示器"
                : "显示器 \(display.displayID)"
            return CapturableDisplay(
                id: display.displayID,
                name: screen?.localizedName ?? fallbackName,
                width: display.width,
                height: display.height,
                isMain: display.displayID == mainDisplayID
            )
        }
        .sorted {
            if $0.isMain != $1.isMain {
                return !$0.isMain
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func start(displayID: CGDirectDisplayID, framesPerSecond: Int) async throws {
        await stop()

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let display = content.displays.first(where: {
            $0.displayID == displayID
        }) else {
            throw CaptureError.displayUnavailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        let scale = min(1, 2560 / Double(display.width))
        configuration.width = max(1, Int(Double(display.width) * scale))
        configuration.height = max(1, Int(Double(display.height) * scale))
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(framesPerSecond)
        )
        configuration.queueDepth = 2
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = false
        capturedDisplayBounds = CGDisplayBounds(displayID)

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        try stream.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: sampleQueue
        )
        self.stream = stream
        try await stream.startCapture()
        startCursorTracking()
    }

    func stop() async {
        cursorTimer?.cancel()
        cursorTimer = nil

        guard let stream else {
            return
        }

        self.stream = nil
        do {
            try await stream.stopCapture()
        } catch {
            // A stream may already have stopped after a display is disconnected.
        }
    }

    func stream(
        _ stream: SCStream,
        didStopWithError error: any Error
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else {
                return
            }
            self.stream = nil
            self.cursorTimer?.cancel()
            self.cursorTimer = nil
            self.onStop?(error)
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(
            image,
            from: image.extent
        ) else {
            return
        }

        let frame = CapturedFrame(
            image: cgImage,
            cursorPosition: normalizedCursorPosition()
        )
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(frame)
        }
    }

    private func normalizedCursorPosition() -> CGPoint {
        guard capturedDisplayBounds.width > 0,
              capturedDisplayBounds.height > 0,
              let location = CGEvent(source: nil)?.location else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let x = (location.x - capturedDisplayBounds.minX)
            / capturedDisplayBounds.width
        let y = (location.y - capturedDisplayBounds.minY)
            / capturedDisplayBounds.height
        return CGPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }

    private func startCursorTracking() {
        cursorTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        timer.schedule(
            deadline: .now(),
            repeating: .milliseconds(33),
            leeway: .milliseconds(5)
        )
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            let position = self.normalizedCursorPosition()
            DispatchQueue.main.async { [weak self] in
                self?.onCursorPosition?(position)
            }
        }
        cursorTimer = timer
        timer.resume()
    }
}
