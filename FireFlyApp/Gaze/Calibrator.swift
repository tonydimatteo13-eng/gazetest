import Foundation
import simd
import UIKit

infix operator • : MultiplicationPrecedence

public struct CalibrationResult {
    public let rmseDeg: Double
    public let transform: simd_double3x3
}

public final class Calibrator {
    private struct Sample {
        let normalizedPoint: CGPoint
        let feature: simd_double3
    }

    private(set) var result: CalibrationResult?
    private var samples: [Sample] = []
    private let screenSize: CGSize
    private let pixelsPerDegree: Double

    public init(screenSize: CGSize = UIScreen.main.bounds.size, pixelsPerDegree: Double = Calibrator.defaultPixelsPerDegree) {
        self.screenSize = screenSize
        self.pixelsPerDegree = pixelsPerDegree
    }

    public func begin() {
        samples.removeAll(keepingCapacity: true)
        result = nil
    }

    public func capture(point screenPt: CGPoint, sample gazeRay: simd_double3) {
        let normalized = CGPoint(x: screenPt.x / screenSize.width, y: screenPt.y / screenSize.height)
        let feature = featureVector(gazeRay: gazeRay)
        samples.append(Sample(normalizedPoint: normalized, feature: feature))
    }

    public func finish() -> CalibrationResult {
        precondition(samples.count >= 3, "Need at least 3 samples for calibration")
        let (coeffX, coeffY) = solveCoefficients()
        let transform = simd_double3x3(
            simd_double3(coeffX.x, coeffY.x, 0),
            simd_double3(coeffX.y, coeffY.y, 0),
            simd_double3(coeffX.z, coeffY.z, 1)
        )
        let rmse = computeRMSEDeg(coeffX: coeffX, coeffY: coeffY)
        let output = CalibrationResult(rmseDeg: rmse, transform: transform)
        result = output
        return output
    }

    public func screenPoint(from gazeRay: simd_double3, headPose: simd_double4x4) -> CGPoint {
        guard let transform = result?.transform else { return defaultPoint }
        return Calibrator.transformPoint(ray: gazeRay, headPose: headPose, transform: transform, screenSize: screenSize)
    }

    private func featureVector(gazeRay: simd_double3) -> simd_double3 {
        simd_double3(gazeRay.x, gazeRay.y, 1.0)
    }

    private func solveCoefficients() -> (simd_double3, simd_double3) {
        var ata = simd_double3x3(repeating: 0)
        var atbx = simd_double3(0, 0, 0)
        var atby = simd_double3(0, 0, 0)

        for sample in samples {
            let f = sample.feature
            let outer = simd_double3x3(
                simd_double3(f.x * f.x, f.x * f.y, f.x * f.z),
                simd_double3(f.y * f.x, f.y * f.y, f.y * f.z),
                simd_double3(f.z * f.x, f.z * f.y, f.z * f.z)
            )
            ata += outer
            atbx += f * Double(sample.normalizedPoint.x)
            atby += f * Double(sample.normalizedPoint.y)
        }

        var regularizedATA = ata
        let determinant = simd_determinant(ata)
        if abs(determinant) < 1e-6 {
            let epsilon = 1e-1
            regularizedATA += simd_double3x3(diagonal: simd_double3(epsilon, epsilon, epsilon))
        }
        let inv = regularizedATA.inverse
        let coeffX = inv * atbx
        let coeffY = inv * atby
        return (coeffX, coeffY)
    }

    private func computeRMSEDeg(coeffX: simd_double3, coeffY: simd_double3) -> Double {
        guard !samples.isEmpty else { return .nan }
        var accum = 0.0
        for sample in samples {
            let predicted = apply(coeffX: coeffX, coeffY: coeffY, feature: sample.feature)
            let dx = (Double(predicted.x) - Double(sample.normalizedPoint.x)) * Double(screenSize.width)
            let dy = (Double(predicted.y) - Double(sample.normalizedPoint.y)) * Double(screenSize.height)
            let pixelError = sqrt(dx * dx + dy * dy)
            let degError = pixelError / pixelsPerDegree
            accum += degError * degError
        }
        let mean = accum / Double(samples.count)
        return sqrt(mean)
    }

    private func apply(coeffX: simd_double3, coeffY: simd_double3, feature: simd_double3) -> CGPoint {
        let x = coeffX • feature
        let y = coeffY • feature
        return CGPoint(x: x, y: y)
    }

    private var defaultPoint: CGPoint {
        CGPoint(x: screenSize.width / 2.0, y: screenSize.height / 2.0)
    }

    public static func transformPoint(ray: simd_double3, headPose: simd_double4x4, transform: simd_double3x3, screenSize: CGSize = UIScreen.main.bounds.size) -> CGPoint {
        let feature = simd_double3(ray.x, ray.y, 1.0)
        let coeffX = simd_double3(transform[0, 0], transform[0, 1], transform[0, 2])
        let coeffY = simd_double3(transform[1, 0], transform[1, 1], transform[1, 2])
        let normalized = CGPoint(x: coeffX • feature, y: coeffY • feature)
        return CGPoint(x: normalized.x * screenSize.width, y: normalized.y * screenSize.height)
    }

    public static let defaultPixelsPerDegree: Double = {
        // 1° ≈ 1.05 cm; iPad ~264 PPI ⇒ ~104 px/cm ⇒ ~109 px/deg
        return 109.0
    }()
}

private func • (lhs: simd_double3, rhs: simd_double3) -> Double {
    lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
}

private extension simd_double3 {
    init(_ v0: Double, _ v1: Double, _ v2: Double) {
        self.init(x: v0, y: v1, z: v2)
    }

    static func *(lhs: simd_double3, rhs: Double) -> simd_double3 {
        simd_double3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }
}

private extension simd_double3x3 {
    init(repeating value: Double) {
        self.init(
            simd_double3(value, 0, 0),
            simd_double3(0, value, 0),
            simd_double3(0, 0, value)
        )
    }
}
