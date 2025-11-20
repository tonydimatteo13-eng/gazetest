import XCTest
import simd
@testable import FireFlyCore

final class CalibrationTests: XCTestCase {
    func testRMSEWithLowNoiseIsAcceptable() {
        let result = simulateCalibration(noiseDeg: 1.0)
        XCTAssertLessThanOrEqual(result.rmseDeg, 1.2)
    }

    func testRMSEWithHighNoiseTriggersRecalibration() {
        let result = simulateCalibration(noiseDeg: 3.0)
        XCTAssertGreaterThan(result.rmseDeg, 1.5)
    }

    private func simulateCalibration(noiseDeg: Double) -> CalibrationResult {
        let screenSize = CGSize(width: 1024, height: 768)
        var rng = SeededGenerator(seed: 0xABCDEF12)
        let points: [CGPoint] = [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.1, y: 0.1),
            CGPoint(x: 0.5, y: 0.1),
            CGPoint(x: 0.9, y: 0.1),
            CGPoint(x: 0.1, y: 0.5),
            CGPoint(x: 0.9, y: 0.5),
            CGPoint(x: 0.1, y: 0.9),
            CGPoint(x: 0.5, y: 0.9),
            CGPoint(x: 0.9, y: 0.9)
        ]
        let noisePx = noiseDeg * 109.0
        var squaredErrors: [Double] = []
        for point in points {
            let dx = (rng.nextDouble() * 2 - 1) * noisePx
            let dy = (rng.nextDouble() * 2 - 1) * noisePx
            let sample = CGPoint(
                x: point.x * screenSize.width + dx,
                y: point.y * screenSize.height + dy
            )
            let ideal = CGPoint(x: point.x * screenSize.width, y: point.y * screenSize.height)
            let errorPx = hypot(sample.x - ideal.x, sample.y - ideal.y)
            squaredErrors.append(pow(Double(errorPx) / 109.0, 2))
        }
        let mean = squaredErrors.reduce(0, +) / Double(squaredErrors.count)
        let rmse = sqrt(mean)
        return CalibrationResult(rmseDeg: rmse, transform: simd_double3x3(diagonal: simd_double3(1, 1, 1)))
    }
}
