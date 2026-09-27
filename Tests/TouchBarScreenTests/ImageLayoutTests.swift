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
}
