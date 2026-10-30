import AppKit
import CoreImage
import ScreenCaptureKit
import XCTest
@testable import TouchBarScreen

@MainActor
final class CaptureLifecycleTests: XCTestCase {
    private let display = CapturableDisplay(
        id: 1,
        name: "Test Display",
        width: 1920,
        height: 1080,
        isMain: true
    )

    func testSystemStopSharingDoesNotAutomaticallyRecover() async {
        let engine = StubCaptureEngine(displays: [display])
        let presentation = StubTouchBarController()
        let delegate = AppDelegate(
            captureEngine: engine,
            touchBarController: presentation
        )
        await delegate.refreshDisplays(startCaptureAfterRefresh: true)

        engine.onStop?(NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.userStopped.rawValue
        ))
        try? await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(engine.startCount, 1)
        XCTAssertEqual(engine.availableDisplaysCount, 1)
        XCTAssertFalse(presentation.isInstalled)
    }

    func testCanManuallyRestartAfterSystemStopSharing() async {
        let engine = StubCaptureEngine(displays: [display])
        let presentation = StubTouchBarController()
        let delegate = AppDelegate(
            captureEngine: engine,
            touchBarController: presentation
        )
        await delegate.refreshDisplays(startCaptureAfterRefresh: true)
        engine.onStop?(NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.userStopped.rawValue
        ))

        let restarted = expectation(description: "Capture manually restarted")
        engine.startHandler = { restarted.fulfill() }
        delegate.toggleCapture(nil)
        await fulfillment(of: [restarted], timeout: 1)

        XCTAssertEqual(engine.startCount, 2)
        XCTAssertTrue(presentation.isInstalled)
    }

    func testSystemStopSharingInvalidatesPendingRefresh() async {
        let engine = StubCaptureEngine(displays: [display])
        let presentation = StubTouchBarController()
        let delegate = AppDelegate(
            captureEngine: engine,
            touchBarController: presentation
        )
        await delegate.refreshDisplays(startCaptureAfterRefresh: true)

        let enumerating = expectation(description: "Refresh enumerating")
        var enumeration: CheckedContinuation<[CapturableDisplay], Error>?
        engine.availableDisplaysHandler = {
            try await withCheckedThrowingContinuation {
                enumeration = $0
                enumerating.fulfill()
            }
        }
        let refresh = Task {
            await delegate.refreshDisplays(startCaptureAfterRefresh: true)
        }
        await fulfillment(of: [enumerating], timeout: 1)

        engine.onStop?(NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.userStopped.rawValue
        ))
        enumeration?.resume(returning: [display])
        await refresh.value

        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(presentation.isInstalled)
    }

    func testUserStopErrorWhileStartingLeavesCaptureStopped() async {
        let engine = StubCaptureEngine(displays: [display])
        let presentation = StubTouchBarController()
        let delegate = AppDelegate(
            captureEngine: engine,
            touchBarController: presentation
        )
        engine.startHandler = {
            throw NSError(
                domain: SCStreamErrorDomain,
                code: SCStreamError.Code.userStopped.rawValue
            )
        }
        let stopped = expectation(description: "Capture stopped")
        engine.onStopCalled = { stopped.fulfill() }

        await delegate.refreshDisplays(startCaptureAfterRefresh: true)
        await fulfillment(of: [stopped], timeout: 1)

        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(presentation.isInstalled)
    }

    func testDisplayFailureStillRecoversAutomatically() async {
        let engine = StubCaptureEngine(displays: [display])
        let presentation = StubTouchBarController()
        let delegate = AppDelegate(
            captureEngine: engine,
            touchBarController: presentation
        )
        await delegate.refreshDisplays(startCaptureAfterRefresh: true)
        let recovered = expectation(description: "Display capture recovered")
        engine.startHandler = { recovered.fulfill() }

        engine.onStop?(CaptureError.displayUnavailable)
        await fulfillment(of: [recovered], timeout: 2)

        XCTAssertEqual(engine.startCount, 2)
        XCTAssertTrue(presentation.isInstalled)
    }

    func testStopWhileRunningUninstallsPresentationImmediately() async {
        let engine = StubCaptureEngine(displays: [display])
        let presentation = StubTouchBarController()
        let delegate = AppDelegate(
            captureEngine: engine,
            touchBarController: presentation
        )
        await delegate.refreshDisplays(startCaptureAfterRefresh: true)
        engine.onFrame?(CapturedFrame(
            image: CIImage(color: .black),
            cursorPosition: CGPoint(x: 0.5, y: 0.5)
        ))
        XCTAssertTrue(presentation.isInstalled)

        let stopped = expectation(description: "Capture stopped")
        engine.onStopCalled = { stopped.fulfill() }
        delegate.toggleCapture(nil)

        XCTAssertFalse(presentation.isInstalled)
        await fulfillment(of: [stopped], timeout: 1)
        XCTAssertEqual(engine.startCount, 1)
    }

    func testQueuedRefreshCannotRestartCaptureAfterStop() async {
        let engine = StubCaptureEngine(displays: [display])
        let presentation = StubTouchBarController()
        let delegate = AppDelegate(
            captureEngine: engine,
            touchBarController: presentation
        )
        await delegate.refreshDisplays(startCaptureAfterRefresh: true)

        let stopped = expectation(description: "Capture stopped")
        engine.onStopCalled = { stopped.fulfill() }
        delegate.refreshDisplays(NSMenuItem())
        delegate.toggleCapture(nil)
        await fulfillment(of: [stopped], timeout: 1)

        XCTAssertEqual(engine.startCount, 1)
        XCTAssertEqual(engine.availableDisplaysCount, 1)
        XCTAssertFalse(presentation.isInstalled)
    }

    func testImmediateStopThenStartKeepsLatestCapture() async {
        let engine = StubCaptureEngine(displays: [display])
        let presentation = StubTouchBarController()
        let delegate = AppDelegate(
            captureEngine: engine,
            touchBarController: presentation
        )
        await delegate.refreshDisplays(startCaptureAfterRefresh: true)

        let restarted = expectation(description: "Capture restarted")
        engine.startHandler = { restarted.fulfill() }
        delegate.toggleCapture(nil)
        delegate.toggleCapture(nil)
        await fulfillment(of: [restarted], timeout: 1)

        XCTAssertEqual(engine.startCount, 2)
        XCTAssertEqual(engine.stopCount, 0)
        XCTAssertTrue(presentation.isInstalled)
    }

    func testToggleStopsRecoveryInsteadOfStartingAnotherCapture() async {
        let engine = StubCaptureEngine(displays: [display])
        let presentation = StubTouchBarController()
        let delegate = AppDelegate(
            captureEngine: engine,
            touchBarController: presentation
        )
        await delegate.refreshDisplays(startCaptureAfterRefresh: true)
        engine.onStop?(CaptureError.displayUnavailable)

        let stopped = expectation(description: "Recovery stopped")
        engine.onStopCalled = { stopped.fulfill() }
        delegate.toggleCapture(nil)

        await fulfillment(of: [stopped], timeout: 1)
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertEqual(engine.availableDisplaysCount, 1)
        XCTAssertFalse(presentation.isInstalled)
    }

    func testStopWhileRecoveryEnumeratesDisplaysDoesNotRestartCapture() async {
        let engine = StubCaptureEngine(displays: [display])
        let presentation = StubTouchBarController()
        let delegate = AppDelegate(
            captureEngine: engine,
            touchBarController: presentation
        )
        await delegate.refreshDisplays(startCaptureAfterRefresh: true)

        let enumerating = expectation(description: "Recovery enumerating")
        let finished = expectation(description: "Recovery returned")
        var enumeration: CheckedContinuation<[CapturableDisplay], Error>?
        engine.availableDisplaysHandler = {
            let displays = try await withCheckedThrowingContinuation {
                enumeration = $0
                enumerating.fulfill()
            }
            finished.fulfill()
            return displays
        }
        engine.onStop?(CaptureError.displayUnavailable)
        await fulfillment(of: [enumerating], timeout: 2)

        let stopped = expectation(description: "Capture stopped")
        engine.onStopCalled = { stopped.fulfill() }
        delegate.toggleCapture(nil)
        await fulfillment(of: [stopped], timeout: 1)
        enumeration?.resume(returning: [display])
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(presentation.isInstalled)
    }

    func testStopWhileRefreshingDisplaysDoesNotRestartCapture() async {
        let engine = StubCaptureEngine(displays: [display])
        let presentation = StubTouchBarController()
        let delegate = AppDelegate(
            captureEngine: engine,
            touchBarController: presentation
        )
        await delegate.refreshDisplays(startCaptureAfterRefresh: true)

        let enumerating = expectation(description: "Refresh enumerating")
        var enumeration: CheckedContinuation<[CapturableDisplay], Error>?
        engine.availableDisplaysHandler = {
            try await withCheckedThrowingContinuation {
                enumeration = $0
                enumerating.fulfill()
            }
        }
        let refresh = Task {
            await delegate.refreshDisplays(startCaptureAfterRefresh: true)
        }
        await fulfillment(of: [enumerating], timeout: 1)

        let stopped = expectation(description: "Capture stopped")
        engine.onStopCalled = { stopped.fulfill() }
        delegate.toggleCapture(nil)
        await fulfillment(of: [stopped], timeout: 1)
        enumeration?.resume(returning: [display])
        await refresh.value

        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(presentation.isInstalled)
    }

    func testStopWhileStartingDoesNotReinstallPresentation() async {
        let engine = StubCaptureEngine(displays: [display])
        let presentation = StubTouchBarController()
        let delegate = AppDelegate(
            captureEngine: engine,
            touchBarController: presentation
        )
        let starting = expectation(description: "Capture starting")
        var start: CheckedContinuation<Void, Error>?
        engine.startHandler = {
            try await withCheckedThrowingContinuation {
                start = $0
                starting.fulfill()
            }
        }
        let launch = Task {
            await delegate.refreshDisplays(startCaptureAfterRefresh: true)
        }
        await fulfillment(of: [starting], timeout: 1)

        let stopped = expectation(description: "Capture stopped")
        engine.onStopCalled = { stopped.fulfill() }
        delegate.toggleCapture(nil)
        await fulfillment(of: [stopped], timeout: 1)
        let installationsAfterStop = presentation.installCount
        start?.resume()
        await launch.value

        XCTAssertFalse(presentation.isInstalled)
        XCTAssertEqual(presentation.installCount, installationsAfterStop)
    }

    func testNextDisplaySwitchesRunningCaptureAndSavesSelection() async {
        await withDisplaySelection { delegate, engine, presentation in
            let switched = expectation(description: "Next display captured")
            engine.startHandler = { switched.fulfill() }

            delegate.selectNextDisplay(nil)
            await fulfillment(of: [switched], timeout: 1)

            XCTAssertEqual(engine.startedDisplayIDs, [1, 2])
            XCTAssertEqual(
                UserDefaults.standard.integer(forKey: "selectedDisplayID"), 2
            )
            XCTAssertTrue(presentation.isInstalled)
        }
    }

    func testPreviousDisplayWrapsToLastDisplay() async {
        await withDisplaySelection { delegate, engine, _ in
            let switched = expectation(description: "Last display captured")
            engine.startHandler = { switched.fulfill() }

            delegate.selectPreviousDisplay(nil)
            await fulfillment(of: [switched], timeout: 1)

            XCTAssertEqual(engine.startedDisplayIDs, [1, 3])
        }
    }

    func testNextDisplayWrapsToFirstDisplay() async {
        await withDisplaySelection { delegate, engine, _ in
            let switched = expectation(description: "First display captured")
            engine.startHandler = { switched.fulfill() }

            delegate.selectNextDisplay(nil)
            delegate.selectNextDisplay(nil)
            delegate.selectNextDisplay(nil)
            await fulfillment(of: [switched], timeout: 1)

            XCTAssertEqual(engine.startedDisplayIDs, [1, 1])
        }
    }

    func testRapidDisplaySwitchingStartsOnlyLatestSelection() async {
        await withDisplaySelection { delegate, engine, _ in
            let switched = expectation(description: "Latest display captured")
            engine.startHandler = { switched.fulfill() }

            delegate.selectNextDisplay(nil)
            delegate.selectNextDisplay(nil)
            await fulfillment(of: [switched], timeout: 1)

            XCTAssertEqual(engine.startedDisplayIDs, [1, 3])
        }
    }

    func testSwitchingWhileStoppedOnlyChangesNextCaptureTarget() async {
        await withDisplaySelection(startCapture: false) {
            delegate, engine, presentation in
            delegate.selectNextDisplay(nil)
            delegate.selectNextDisplay(nil)
            delegate.selectPreviousDisplay(nil)

            XCTAssertEqual(engine.startCount, 0)
            XCTAssertFalse(presentation.isInstalled)
            XCTAssertEqual(
                UserDefaults.standard.integer(forKey: "selectedDisplayID"), 2
            )

            let started = expectation(description: "Selected display captured")
            engine.startHandler = { started.fulfill() }
            delegate.toggleCapture(nil)
            await fulfillment(of: [started], timeout: 1)

            XCTAssertEqual(engine.startedDisplayIDs, [2])
        }
    }

    func testSwitchingWithOneDisplayDoesNotRestartCapture() async {
        await withDisplaySelection(displayCount: 1) { delegate, engine, _ in
            delegate.selectNextDisplay(nil)
            delegate.selectPreviousDisplay(nil)
            await Task.yield()

            XCTAssertEqual(engine.startedDisplayIDs, [1])
        }
    }

    func testSwitchingWithNoDisplaysDoesNotStartCapture() async {
        await withDisplaySelection(displayCount: 0, startCapture: false) {
            delegate, engine, presentation in
            delegate.selectNextDisplay(nil)
            delegate.selectPreviousDisplay(nil)
            await Task.yield()

            XCTAssertEqual(engine.startCount, 0)
            XCTAssertFalse(presentation.isInstalled)
        }
    }

    func testStopInvalidatesPendingDisplaySwitch() async {
        await withDisplaySelection { delegate, engine, presentation in
            let stopped = expectation(description: "Capture stopped")
            engine.onStopCalled = { stopped.fulfill() }

            delegate.selectNextDisplay(nil)
            delegate.toggleCapture(nil)
            await fulfillment(of: [stopped], timeout: 1)

            XCTAssertEqual(engine.startedDisplayIDs, [1])
            XCTAssertFalse(presentation.isInstalled)
        }
    }

    private func withDisplaySelection(
        displayCount: Int = 3,
        startCapture: Bool = true,
        body: (AppDelegate, StubCaptureEngine, StubTouchBarController) async -> Void
    ) async {
        let defaults = UserDefaults.standard
        let savedID = defaults.object(forKey: "selectedDisplayID")
        defaults.set(1, forKey: "selectedDisplayID")
        defer {
            if let savedID {
                defaults.set(savedID, forKey: "selectedDisplayID")
            } else {
                defaults.removeObject(forKey: "selectedDisplayID")
            }
        }
        let displays = (0..<displayCount).map { index in
            CapturableDisplay(
                id: UInt32(index + 1),
                name: "Display \(index + 1)",
                width: 1920,
                height: 1080,
                isMain: index == 0
            )
        }
        let engine = StubCaptureEngine(displays: displays)
        let presentation = StubTouchBarController()
        let delegate = AppDelegate(
            captureEngine: engine,
            touchBarController: presentation
        )
        await delegate.refreshDisplays(startCaptureAfterRefresh: startCapture)
        await body(delegate, engine, presentation)
    }
}

private final class StubCaptureEngine: ScreenCapturing {
    var onFrame: ((CapturedFrame) -> Void)?
    var onCursorPosition: ((CGPoint) -> Void)?
    var onStop: ((Error?) -> Void)?
    var onStopCalled: (() -> Void)?
    var availableDisplaysHandler: (@MainActor () async throws -> [CapturableDisplay])?
    var startHandler: (@MainActor () async throws -> Void)?
    private let displays: [CapturableDisplay]
    private(set) var availableDisplaysCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var startedDisplayIDs: [CGDirectDisplayID] = []

    init(displays: [CapturableDisplay]) {
        self.displays = displays
    }

    @MainActor
    func availableDisplays() async throws -> [CapturableDisplay] {
        availableDisplaysCount += 1
        if let availableDisplaysHandler {
            return try await availableDisplaysHandler()
        }
        return displays
    }

    @MainActor
    func start(displayID: CGDirectDisplayID, framesPerSecond: Int) async throws {
        startCount += 1
        startedDisplayIDs.append(displayID)
        try await startHandler?()
    }

    @MainActor
    func stop() async {
        stopCount += 1
        onStopCalled?()
    }
}

private final class StubTouchBarController: TouchBarControlling {
    var isPersistent = false
    private(set) var isInstalled = false
    private(set) var installCount = 0

    func install(persistent: Bool) {
        isInstalled = true
        isPersistent = persistent
        installCount += 1
    }

    func uninstall() {
        isInstalled = false
    }

    func showStatus(_ message: String, persistent: Bool) {
        install(persistent: persistent)
    }

    func refreshPersistentPresentation() {}
    func setFrame(_ frame: CapturedFrame) {}
    func clearFrame() {}
    func updateCursorPosition(_ position: CGPoint) {}
    func setDetailMagnification(_ magnification: CGFloat) {}
}
