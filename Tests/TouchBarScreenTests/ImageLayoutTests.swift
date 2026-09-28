import XCTest
@testable import TouchBarScreen

final class ImageLayoutTests: XCTestCase {
    func testStretchUsesAllBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 1004, height: 30)
        let result = ImageLayout.destinationRect(
            imageSize: CGSize(width: 1920, height: 1080),
            bounds: bounds,
            mode: .stretch
        )

        XCTAssertEqual(result, bounds)
    }

    func testAspectFitCentersImage() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = ImageLayout.destinationRect(
            imageSize: CGSize(width: 200, height: 100),
            bounds: bounds,
            mode: .aspectFit
        )

        XCTAssertEqual(result, CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    func testCenterCropOverflowsAndCentersImage() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = ImageLayout.destinationRect(
            imageSize: CGSize(width: 200, height: 100),
            bounds: bounds,
            mode: .centerCrop
        )

        XCTAssertEqual(result, CGRect(x: -50, y: 0, width: 200, height: 100))
    }

    func testDetailSourceRectCentersOnCursor() {
        let result = ImageLayout.detailSourceRect(
            imageSize: CGSize(width: 1920, height: 1080),
            destinationSize: CGSize(width: 500, height: 30),
            normalizedCursorPosition: CGPoint(x: 0.5, y: 0.5),
            magnification: 2
        )

        XCTAssertEqual(
            result,
            CGRect(x: 835, y: 532.5, width: 250, height: 15)
        )
    }

    func testDetailSourceRectPreservesAspectRatioAtLowMagnification() {
        let result = ImageLayout.detailSourceRect(
            imageSize: CGSize(width: 1920, height: 1080),
            destinationSize: CGSize(width: 500, height: 30),
            normalizedCursorPosition: CGPoint(x: 0.5, y: 0.5),
            magnification: 0.1
        )

        XCTAssertEqual(result.width / result.height, 500 / 30, accuracy: 0.001)
        XCTAssertLessThanOrEqual(result.width, 1920)
        XCTAssertLessThanOrEqual(result.height, 1080)
    }

    func testDetailSourceRectClampsToTopLeftEdge() {
        let result = ImageLayout.detailSourceRect(
            imageSize: CGSize(width: 1920, height: 1080),
            destinationSize: CGSize(width: 500, height: 30),
            normalizedCursorPosition: CGPoint(x: 0, y: 0),
            magnification: 1
        )

        XCTAssertEqual(result.origin.x, 0)
        XCTAssertEqual(result.maxY, 1080)
    }
}
