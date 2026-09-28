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
    let image: CIImage
    let cursorPosition: CGPoint
}

enum CaptureError: LocalizedError, Equatable {
    case displayUnavailable
    case screenRecordingPermissionDenied

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            return "所选显示器已不可用，请刷新显示器列表。"
        case .screenRecordingPermissionDenied:
            return "没有屏幕录制权限。请在系统设置的“隐私与安全性”中允许 TouchBarScreen 录制屏幕，然后重新启动应用。"
        }
    }

    var touchBarMessage: String {
        switch self {
        case .displayUnavailable:
            return "显示器不可用，正在等待恢复"
        case .screenRecordingPermissionDenied:
            return "需要屏幕录制权限"
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
    private let stateLock = NSLock()
    private var stream: SCStream?
    private var cursorTimer: DispatchSourceTimer?
    private var capturedDisplayBounds = CGRect.zero
    private var operationGeneration = 0
    private var activeStream: SCStream?
    private var pendingFrame: CapturedFrame?
    private var isFrameDeliveryScheduled = false

    @MainActor
    func availableDisplays() async throws -> [CapturableDisplay] {
        try ensureScreenRecordingPermission()
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

    @MainActor
    func start(displayID: CGDirectDisplayID, framesPerSecond: Int) async throws {
        operationGeneration += 1
        let generation = operationGeneration
        await stopCurrentStream()
        try ensureScreenRecordingPermission()

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard generation == operationGeneration else {
            throw CancellationError()
        }
        guard let display = content.displays.first(where: {
            $0.displayID == displayID
        }) else {
            throw CaptureError.displayUnavailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        let scale = min(1, 1280 / Double(display.width))
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
        setActiveStream(stream, displayBounds: CGDisplayBounds(displayID))

        do {
            try await stream.startCapture()
        } catch {
            if self.stream === stream {
                self.stream = nil
                clearActiveStream(stream)
            }
            throw error
        }

        guard generation == operationGeneration, self.stream === stream else {
            try? await stream.stopCapture()
            throw CancellationError()
        }
        startCursorTracking(for: stream)
    }

    @MainActor
    func stop() async {
        operationGeneration += 1
        await stopCurrentStream()
    }

    @MainActor
    private func stopCurrentStream() async {
        cursorTimer?.cancel()
        cursorTimer = nil

        guard let stream else {
            clearActiveStream(nil)
            return
        }

        self.stream = nil
        clearActiveStream(stream)
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
            guard let self else {
                return
            }
            Task { @MainActor in
                guard self.stream === stream else {
                    return
                }
                self.stream = nil
                self.clearActiveStream(stream)
                self.cursorTimer?.cancel()
                self.cursorTimer = nil
                self.onStop?(error)
            }
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer,
              isActiveStream(stream) else {
            return
        }

        let frame = CapturedFrame(
            image: CIImage(cvPixelBuffer: pixelBuffer),
            cursorPosition: normalizedCursorPosition()
        )
        enqueueLatestFrame(frame, from: stream)
    }

    private func normalizedCursorPosition() -> CGPoint {
        stateLock.lock()
        let displayBounds = capturedDisplayBounds
        stateLock.unlock()

        guard displayBounds.width > 0,
              displayBounds.height > 0,
              let location = CGEvent(source: nil)?.location else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let x = (location.x - displayBounds.minX) / displayBounds.width
        let y = (location.y - displayBounds.minY) / displayBounds.height
        return CGPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }

    private func startCursorTracking(for stream: SCStream) {
        cursorTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        timer.schedule(
            deadline: .now(),
            repeating: .milliseconds(33),
            leeway: .milliseconds(5)
        )
        timer.setEventHandler { [weak self] in
            guard let self, self.isActiveStream(stream) else {
                return
            }
            let position = self.normalizedCursorPosition()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActiveStream(stream) else {
                    return
                }
                self.onCursorPosition?(position)
            }
        }
        cursorTimer = timer
        timer.resume()
    }

    @MainActor
    private func ensureScreenRecordingPermission() throws {
        guard CGPreflightScreenCaptureAccess()
                || CGRequestScreenCaptureAccess() else {
            throw CaptureError.screenRecordingPermissionDenied
        }
    }

    private func setActiveStream(
        _ stream: SCStream,
        displayBounds: CGRect
    ) {
        stateLock.lock()
        activeStream = stream
        capturedDisplayBounds = displayBounds
        pendingFrame = nil
        isFrameDeliveryScheduled = false
        stateLock.unlock()
    }

    private func clearActiveStream(_ expectedStream: SCStream?) {
        stateLock.lock()
        if expectedStream == nil || activeStream === expectedStream {
            activeStream = nil
            capturedDisplayBounds = .zero
            pendingFrame = nil
            isFrameDeliveryScheduled = false
        }
        stateLock.unlock()
    }

    private func isActiveStream(_ stream: SCStream) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeStream === stream
    }

    private func enqueueLatestFrame(
        _ frame: CapturedFrame,
        from stream: SCStream
    ) {
        stateLock.lock()
        guard activeStream === stream else {
            stateLock.unlock()
            return
        }
        pendingFrame = frame
        guard !isFrameDeliveryScheduled else {
            stateLock.unlock()
            return
        }
        isFrameDeliveryScheduled = true
        stateLock.unlock()

        DispatchQueue.main.async { [weak self, weak stream] in
            guard let self, let stream else {
                return
            }
            self.deliverLatestFrame(from: stream)
        }
    }

    private func deliverLatestFrame(from stream: SCStream) {
        stateLock.lock()
        guard activeStream === stream else {
            stateLock.unlock()
            return
        }
        let frame = pendingFrame
        pendingFrame = nil
        isFrameDeliveryScheduled = false
        stateLock.unlock()

        if let frame {
            onFrame?(frame)
        }
    }
}
