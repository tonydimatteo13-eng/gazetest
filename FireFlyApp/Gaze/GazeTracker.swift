import ARKit
import UIKit
import simd

@objc(FireFlyGazeTracker)
public final class GazeTracker: NSObject, ARSessionDelegate {
    public struct Sample {
        let t: TimeInterval
        let point: CGPoint
        let distanceCm: Double
    }

    private let session: ARSession
    private var calibration: CalibrationResult?
    public private(set) var latestPoint: CGPoint = .zero
    public private(set) var latestDistanceCm: Double = 60.0
    private let screenBounds: CGRect
    public var onSample: ((Sample, simd_double3, simd_double4x4) -> Void)?
    public var onDebugMessage: ((String) -> Void)?

    public override init() {
        screenBounds = UIScreen.main.bounds
        session = ARSession()
        super.init()
        session.delegate = self
        emitDebug("GazeTracker initialized (ARKit)")
    }

    deinit {
        session.delegate = nil
    }

    private func emitDebug(_ message: String) {
        print(message)
        DispatchQueue.main.async { [weak self] in
            self?.onDebugMessage?(message)
        }
    }

    public func apply(calibration result: CalibrationResult) {
        calibration = result
    }

    public func start() {
        emitDebug("Starting ARKit tracking")
        startARTracking()
    }

    public func stop() {
        emitDebug("Stopping ARKit tracking")
        session.pause()
    }

    private func startARTracking() {
        guard ARFaceTrackingConfiguration.isSupported else {
            assertionFailure("ARFaceTrackingConfiguration is not supported on this device")
            return
        }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.providesAudioData = false
        if #available(iOS 17.0, *) {
            configuration.worldAlignment = .gravityAndHeading
        }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let anchor = anchors.first(where: { $0 is ARFaceAnchor }) as? ARFaceAnchor else { return }
        process(anchor: anchor)
    }

    private func process(anchor: ARFaceAnchor) {
        let tf = anchor.transform
        let headPose = simd_double4x4(
            simd_double4(Double(tf.columns.0.x), Double(tf.columns.0.y), Double(tf.columns.0.z), Double(tf.columns.0.w)),
            simd_double4(Double(tf.columns.1.x), Double(tf.columns.1.y), Double(tf.columns.1.z), Double(tf.columns.1.w)),
            simd_double4(Double(tf.columns.2.x), Double(tf.columns.2.y), Double(tf.columns.2.z), Double(tf.columns.2.w)),
            simd_double4(Double(tf.columns.3.x), Double(tf.columns.3.y), Double(tf.columns.3.z), Double(tf.columns.3.w))
        )
        let origin = simd_double3(headPose.columns.3.x, headPose.columns.3.y, headPose.columns.3.z)
        let lookAt = simd_double3(Double(anchor.lookAtPoint.x), Double(anchor.lookAtPoint.y), Double(anchor.lookAtPoint.z))
        let rotation = simd_double3x3(
            simd_double3(headPose.columns.0.x, headPose.columns.0.y, headPose.columns.0.z),
            simd_double3(headPose.columns.1.x, headPose.columns.1.y, headPose.columns.1.z),
            simd_double3(headPose.columns.2.x, headPose.columns.2.y, headPose.columns.2.z)
        )
        let target = rotation * lookAt + origin
        let ray = simd_normalize(target - origin)

        let mappedPoint = projectToScreen(ray: ray, headPose: headPose)
        let distance = simd_length(origin) * 100.0
        deliverSample(point: mappedPoint, distance: distance, ray: ray, headPose: headPose)
    }

    private func deliverSample(point: CGPoint, distance: Double, ray: simd_double3, headPose: simd_double4x4) {
        latestPoint = point
        latestDistanceCm = distance
        let sample = Sample(t: CACurrentMediaTime(), point: point, distanceCm: distance)
        onSample?(sample, ray, headPose)
        print("[Gaze] point=(\(String(format: "%.1f", point.x)), \(String(format: "%.1f", point.y))) cm=\(String(format: "%.1f", distance))")
    }

    private func projectToScreen(ray: simd_double3, headPose: simd_double4x4) -> CGPoint {
        if let calibration {
            let mapped = Calibrator.transformPoint(ray: ray, headPose: headPose, transform: calibration.transform)
            return mapped
        }
        let center = CGPoint(x: screenBounds.midX, y: screenBounds.midY)
        let scale: CGFloat = min(screenBounds.width, screenBounds.height) / 2.0
        return CGPoint(
            x: center.x + CGFloat(ray.x) * scale,
            y: center.y - CGFloat(ray.y) * scale
        )
    }

    public var modeDescription: String {
        "ARKit"
    }
}
