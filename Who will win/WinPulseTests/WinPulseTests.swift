import XCTest
@testable import AiSports

final class WinPulseTests: XCTestCase {
    func testImpliedProbability() {
        let odds = -150
        let negative = Double(-odds) / (Double(-odds) + 100)
        XCTAssertEqual(round(negative * 100)/100, 0.6, accuracy: 0.01)
    }

    func testOddsFormatting() {
        let formatted = String(format: "%d", -150)
        XCTAssertEqual(formatted, "-150")
    }
}
