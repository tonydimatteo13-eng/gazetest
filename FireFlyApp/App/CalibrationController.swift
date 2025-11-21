import Foundation
import UIKit
import Combine
import simd
import FireFlyCore

@MainActor
final class CalibrationController: ObservableObject {
    @Published var currentPoint: CGPoint = .zero
    @Published var progress: Double = 0
    @Published var status: String = ""
    @Published var isComplete: Bool = false
    @Published var debugInfo: String = ""

    var onCompletion: ((CalibrationResult) -> Void)?

    private let calibrator: Calibrator
    private let gazeTracker: GazeTracker
    private let points: [CGPoint]
    private var currentIndex: Int = 0
    private var pointSamples: [simd_double3] = []
    private var settleWorkItem: DispatchWorkItem?
    private var captureWorkItem: DispatchWorkItem?
    private let minSamplesPerPoint = 5
    private let captureTimeout: TimeInterval = 1.5
    private let settleDuration: TimeInterval = 0.6

    init(calibrator: Calibrator, gazeTracker: GazeTracker) {
        self.calibrator = calibrator
        self.gazeTracker = gazeTracker
        self.points = CalibrationController.starPoints
    }

    func start() {
        calibrator.begin()
        subscribeToGaze()
        currentIndex = 0
        progress = 0
        status = "Tracker: \(gazeTracker.modeDescription)"
        debugInfo = "Awaiting samples…"
        advancePoint()
    }

    private func subscribeToGaze() {
        gazeTracker.onSample = { [weak self] sample, ray, _ in
            guard let self else { return }
            guard self.isCollecting else { return }
            self.pointSamples.append(ray)
            self.debugInfo = "Samples: \(self.pointSamples.count)/\(self.minSamplesPerPoint)"
            if self.pointSamples.count >= self.minSamplesPerPoint {
                self.capturePoint()
            }
        }
    }

    private var isCollecting: Bool {
        captureWorkItem != nil
    }

    private func advancePoint() {
        guard currentIndex < points.count else {
            finalize()
            return
        }
        let normalized = points[currentIndex]
        let bounds = UIScreen.main.bounds
        currentPoint = CGPoint(x: normalized.x * bounds.width, y: normalized.y * bounds.height)
        progress = Double(currentIndex) / Double(points.count)
        status = String(format: "Point %d / %d", currentIndex + 1, points.count)
        pointSamples.removeAll(keepingCapacity: true)
        startSettlingPhase()
    }

    private func startSettlingPhase() {
        captureWorkItem?.cancel()
        captureWorkItem = nil
        settleWorkItem?.cancel()
        settleWorkItem = nil
        settleWorkItem = nil
        debugInfo = "Hold steady…"
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.beginSampling()
            }
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDuration, execute: work)
    }

    private func beginSampling() {
        guard settleWorkItem != nil else { return }
        settleWorkItem = nil
        debugInfo = "Samples: 0/\(minSamplesPerPoint)"
        scheduleCaptureTimeout()
    }

    private func scheduleCaptureTimeout() {
        captureWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.debugInfo = "Timeout – using \(self?.pointSamples.count ?? 0) samples"
                self?.capturePoint()
            }
        }
        captureWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + captureTimeout, execute: work)
    }

    private func capturePoint() {
        settleWorkItem?.cancel()
        guard captureWorkItem != nil else { return }
        captureWorkItem?.cancel()
        captureWorkItem = nil
        let bounds = UIScreen.main.bounds
        let normalized = points[currentIndex]
        let screenPoint = CGPoint(x: normalized.x * bounds.width, y: normalized.y * bounds.height)
        let averagedRay = averageRay()
        status = String(format: "Captured point %d (%d samples)", currentIndex + 1, pointSamples.count)
        calibrator.capture(point: screenPoint, sample: averagedRay)
        currentIndex += 1
        advancePoint()
    }

    private func averageRay() -> simd_double3 {
        guard !pointSamples.isEmpty else {
            debugInfo = "Samples: 0 (no gaze data)"
            return simd_double3(0, 0, 1)
        }
        var sum = simd_double3(0, 0, 0)
        for ray in pointSamples {
            sum += ray
        }
        let avg = sum / Double(pointSamples.count)
        debugInfo = "Samples: \(pointSamples.count)"
        return avg
    }

    private func finalize() {
        let result = calibrator.finish()
        status = String(format: "RMSE %.2f°", result.rmseDeg)
        debugInfo = result.rmseDeg > 2.0 ? "Signal quality is low. Please recalibrate." : "Calibration complete"
        isComplete = true
        onCompletion?(result)
    }
}

private extension CalibrationController {
    static let starPoints: [CGPoint] = [
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
}
