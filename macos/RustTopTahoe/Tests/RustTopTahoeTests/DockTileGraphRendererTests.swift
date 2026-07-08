import AppKit
import XCTest
@testable import RustTopTahoe

final class DockTileGraphRendererTests: XCTestCase {
    func testRendererProducesDockSizedImage() throws {
        let image = DockTileGraphRenderer.image(
            samples: [
                MetricSample(date: Date(timeIntervalSince1970: 1), cpu: 22, memory: 45, networkIn: 0, networkOut: 0),
                MetricSample(date: Date(timeIntervalSince1970: 2), cpu: 74, memory: 68, networkIn: 0, networkOut: 0)
            ],
            isLive: true,
            activeAlertCount: 1
        )

        XCTAssertEqual(image.size.width, DockTileGraphRenderer.tileSize.width)
        XCTAssertEqual(image.size.height, DockTileGraphRenderer.tileSize.height)
        XCTAssertNotNil(image.tiffRepresentation)
    }
}
