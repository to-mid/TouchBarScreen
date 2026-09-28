import XCTest
@testable import TouchBarScreen

final class DisplayRecoveryTests: XCTestCase {
    private let mainDisplay = CapturableDisplay(
        id: 1,
        name: "Built-in Display",
        width: 2560,
        height: 1600,
        isMain: true
    )
    private let virtualDisplay = CapturableDisplay(
        id: 2,
        name: "Virtual Display",
        width: 1920,
        height: 1080,
        isMain: false
    )

    func testKeepsCurrentDisplayWhenItStillExists() {
        let result = DisplayRecovery.selectedDisplayID(
            currentID: virtualDisplay.id,
            in: [mainDisplay, virtualDisplay],
            previouslySelected: nil
        )

        XCTAssertEqual(result, virtualDisplay.id)
    }

    func testMatchesReconnectedDisplayByNameAndResolution() {
        let reconnected = CapturableDisplay(
            id: 9,
            name: virtualDisplay.name,
            width: virtualDisplay.width,
            height: virtualDisplay.height,
            isMain: false
        )
        let result = DisplayRecovery.selectedDisplayID(
            currentID: virtualDisplay.id,
            in: [mainDisplay, reconnected],
            previouslySelected: virtualDisplay
        )

        XCTAssertEqual(result, reconnected.id)
    }

    func testPrefersNonMainDisplayAsFallback() {
        let result = DisplayRecovery.selectedDisplayID(
            currentID: 99,
            in: [mainDisplay, virtualDisplay],
            previouslySelected: nil
        )

        XCTAssertEqual(result, virtualDisplay.id)
    }
}
