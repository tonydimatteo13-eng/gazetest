import SpriteKit
import ARKit
import UIKit
import simd

public final class FireFlyScene: SKScene {
    public enum State { case calibrate, fixate, go, stop, feedback, iti, paused }
    public enum BreakType { case baselineToSST, midSST }

    public var onTrialFinished: ((Trial) -> Void)?
    public var onBlockFinished: ((TrialBlock) -> Void)?
    public var onBreakRequested: ((BreakType) -> Void)?

    private var config: GameConfig = .production
    private var calibrator: Calibrator = Calibrator()
    private var gazeTracker: GazeTracker = GazeTracker()
    private let engine = TrialEngine()
    private var detector: SaccadeDetector = SaccadeDetector(anticipationThresholdMs: 100)

    private var state: State = .calibrate
    private var currentBlock: TrialBlock?
    private var scheduledTrial: ScheduledTrial?
    private var goStartTime: TimeInterval?
    private var stopSignalTime: TimeInterval?
    private var fixationStartSample: TimeInterval?
    private var fixationStreak = 0
    private var trialCompleted = false
    private var gazeSamples: [AngleSample] = []
    private var distanceSamples: [Double] = []
    private var headMotionFlag = false
    private var lostTrackingFlag = false
    private var itiRng: SeededGenerator = SeededGenerator(seed: 0xF1F2F3F4)
    private var visibleHalfWidth: CGFloat = 0
    private var gazeCenterCalibrated = false
    private var centerHorizontalRad: Double = 0
    private var centerVerticalRad: Double = 0
    private var centerAccumHorizontalRad: Double = 0
    private var centerAccumVerticalRad: Double = 0
    private var centerSampleCount: Int = 0
    private var fixationDifficultyStart: TimeInterval?
    private var lastHintTime: TimeInterval?
    private var lastSampleTime: TimeInterval?
    private var hasIssuedMidSSTBreak = false

    private var shouldCalibrateGazeCenter: Bool {
        currentBlock == .training || currentBlock == .baseline
    }

    private var didSetupScene = false

    // Nodes
    private let rootNode = SKNode()
    private let backgroundNode = SKNode()
    private let fireflyNode = SKSpriteNode(imageNamed: "firefly_idle")
    private let stopNode = SKSpriteNode(imageNamed: "stop_sign")
    private let feedbackNode = SKSpriteNode()
    private let owlNode = SKSpriteNode(imageNamed: "owl_body")
    private let owlEyesOpen = SKSpriteNode(imageNamed: "owl_eyes_open")
    private let owlEyesBlink = SKSpriteNode(imageNamed: "owl_eyes_blink")
    private let hintLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hintBackground = SKShapeNode()

    private let pixelsPerDegree: Double = 109.0

    public override func didMove(to view: SKView) {
        super.didMove(to: view)
        guard !didSetupScene else {
            recomputeVisibleWidth(for: view)
            return
        }
        didSetupScene = true
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        setupScene()
        recomputeVisibleWidth(for: view)
    }

    private func recomputeVisibleWidth(for view: SKView) {
        // Compute the horizontally visible portion of the scene given the
        // SpriteKit view's aspect ratio. On tall iPhones, the scene is cropped
        // horizontally when aspectFill is used, so we must keep targets inside
        // the actually visible half‑width.
        let viewSize = view.bounds.size
        let viewAspect = viewSize.width / max(viewSize.height, 1)
        let sceneAspect = size.width / max(size.height, 1)
        if viewAspect < sceneAspect {
            // Cropped horizontally: visible world width is limited by view width.
            visibleHalfWidth = (size.height * viewAspect) / 2.0
        } else {
            visibleHalfWidth = size.width / 2.0
        }
        if visibleHalfWidth <= 0 {
            visibleHalfWidth = size.width / 2.0
        }
        print("[Scene] didMove – sceneSize=\(size) viewSize=\(viewSize) visibleHalfWidth=\(visibleHalfWidth)")
    }

    public func configure(with config: GameConfig, calibrator: Calibrator, gaze: GazeTracker) {
        self.config = config
        self.calibrator = calibrator
        self.gazeTracker = gaze
        self.detector = SaccadeDetector(anticipationThresholdMs: config.anticipationThresholdMs)
        itiRng = SeededGenerator(seed: config.rngSeed ^ 0xA5A5A5A5)
        gazeTracker.onSample = { [weak self] sample, ray, _ in
            self?.handle(sample: sample, ray: ray)
        }
        print("[FireFlyScene] Configured with gaze tracker")
    }

    public func startTraining() {
        prepareForBlock(.training, resetEngine: true, resetGazeCenter: true)
    }

    public func startBaseline() {
        prepareForBlock(.baseline, resetEngine: false, resetGazeCenter: true)
    }

    public func startSST() {
        prepareForBlock(.sst, resetEngine: false, resetGazeCenter: false)
    }

    public func resumeAfterBreak() {
        print("[Scene] resumeAfterBreak() – advancing to next scheduled trial")
        advanceToNextTrial()
    }

    public override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        guard let trial = scheduledTrial, let goTime = goStartTime else {
            checkForLostTracking(currentTime: currentTime)
            return
        }
        checkForLostTracking(currentTime: currentTime)
        switch state {
        case .go:
            updateStopStateIfNeeded(currentTime: currentTime, trial: trial)
            evaluateTimeout(currentTime: currentTime, goTime: goTime, trial: trial)
        case .stop:
            evaluateTimeout(currentTime: currentTime, goTime: goTime, trial: trial)
        case .fixate, .iti, .paused, .calibrate:
            checkForLostTracking(currentTime: currentTime)
        default:
            break
        }
    }
}

// MARK: - Block lifecycle
private extension FireFlyScene {
    func prepareForBlock(_ block: TrialBlock, resetEngine: Bool, resetGazeCenter: Bool) {
        currentBlock = block
        state = .calibrate
        scheduledTrial = nil
        goStartTime = nil
        stopSignalTime = nil
        fixationStartSample = nil
        fixationStreak = 0
        trialCompleted = false
        gazeSamples.removeAll(keepingCapacity: true)
        distanceSamples.removeAll(keepingCapacity: true)
        headMotionFlag = false
        lostTrackingFlag = false
        lastSampleTime = CACurrentMediaTime()
        hasIssuedMidSSTBreak = false
        hintLabel.isHidden = true
        if resetEngine {
            engine.reset()
        }
        if resetGazeCenter {
            resetGazeCenterOffsets()
        }
        print("[Scene] prepareForBlock(\(block)) – resetEngine=\(resetEngine) resetGazeCenter=\(resetGazeCenter)")
        advanceToNextTrial()
    }

    func resetGazeCenterOffsets() {
        gazeCenterCalibrated = false
        centerHorizontalRad = 0
        centerVerticalRad = 0
        centerAccumHorizontalRad = 0
        centerAccumVerticalRad = 0
        centerSampleCount = 0
    }
}

// MARK: - Scene wiring
private extension FireFlyScene {
    func setupScene() {
        addChild(rootNode)
        rootNode.addChild(backgroundNode)
        addBackground()

        fireflyNode.isHidden = true
        fireflyNode.zPosition = 10
        rootNode.addChild(fireflyNode)
        fireflyNode.run(SKAction.repeatForever(glowAnimation()))
        let bobUp = SKAction.moveBy(x: 0, y: 6, duration: 0.9)
        bobUp.timingMode = .easeInEaseOut
        let bobSequence = SKAction.sequence([bobUp, bobUp.reversed()])
        fireflyNode.run(SKAction.repeatForever(bobSequence), withKey: "idleBob")

        stopNode.isHidden = true
        stopNode.zPosition = 20
        owlNode.addChild(stopNode)
        stopNode.position = CGPoint(x: 0, y: 120)

        feedbackNode.isHidden = true
        feedbackNode.zPosition = 25
        rootNode.addChild(feedbackNode)

        owlNode.zPosition = 5
        rootNode.addChild(owlNode)
        owlEyesOpen.position = .zero
        owlEyesBlink.position = .zero
        owlEyesBlink.isHidden = true
        owlNode.addChild(owlEyesOpen)
        owlNode.addChild(owlEyesBlink)

        let blink = SKAction.sequence([
            SKAction.wait(forDuration: 2.5, withRange: 1.5),
            SKAction.run { [weak self] in self?.blink() }
        ])
        owlNode.run(SKAction.repeatForever(blink))

        hintLabel.fontSize = 20
        hintLabel.fontColor = .white
        hintLabel.horizontalAlignmentMode = .center
        hintLabel.verticalAlignmentMode = .center
        hintLabel.position = CGPoint(x: 0, y: -size.height * 0.18)
        hintLabel.text = ""
        hintLabel.isHidden = true
        hintBackground.fillColor = UIColor.black.withAlphaComponent(0.7)
        hintBackground.strokeColor = .clear
        hintBackground.zPosition = 50
        hintBackground.isHidden = true
        rootNode.addChild(hintBackground)
        rootNode.addChild(hintLabel)
    }

    func addBackground() {
        let layers = [
            ("bg_sky", -50.0),
            ("bg_trees_back", -40.0),
            ("bg_trees_mid", -30.0),
            ("bg_trees_front", -20.0),
            ("bg_ground", -10.0)
        ]
        for (name, z) in layers {
            let node = SKSpriteNode(imageNamed: name)
            node.zPosition = z
            node.position = .zero
            backgroundNode.addChild(node)
            let amplitude: CGFloat = 8.0
            let duration: TimeInterval = 6.0
            let moveRight = SKAction.moveBy(x: amplitude, y: 0, duration: duration)
            moveRight.timingMode = .easeInEaseOut
            let parallax = SKAction.sequence([moveRight, moveRight.reversed()])
            node.run(SKAction.repeatForever(parallax))
        }
    }

    func glowAnimation() -> SKAction {
        let frames = ["firefly_idle", "firefly_glow_1", "firefly_glow_2", "firefly_glow_3"].map { SKTexture(imageNamed: $0) }
        return SKAction.sequence([
            SKAction.animate(with: frames, timePerFrame: 0.35, resize: false, restore: false),
            SKAction.animate(with: frames.reversed(), timePerFrame: 0.35, resize: false, restore: false)
        ])
    }

    func blink() {
        owlEyesOpen.isHidden = true
        owlEyesBlink.isHidden = false
        owlEyesBlink.run(SKAction.wait(forDuration: 0.15)) { [weak self] in
            self?.owlEyesOpen.isHidden = false
            self?.owlEyesBlink.isHidden = true
        }
    }
}

// MARK: - Samples and state
private extension FireFlyScene {
    func handle(sample: GazeTracker.Sample, ray: simd_double3) {
        print("[Scene] handling sample t=\(sample.t) state=\(state) scheduled=\(scheduledTrial != nil) completed=\(trialCompleted)")
        guard let trial = scheduledTrial, !trialCompleted else {
            print("[Scene] no scheduled trial (state=\(state))")
            return
        }
        // Derive gaze angles directly from the ARKit gaze ray, and apply
        // a per-session center offset so that "looking at the owl" maps to
        // approximately (0°,0°) even if the absolute ray is biased.
        let rawHorizontalRad = atan2(ray.x, ray.z)
        let rawVerticalRad = atan2(ray.y, ray.z)

        if state == .fixate && shouldCalibrateGazeCenter && !gazeCenterCalibrated {
            centerAccumHorizontalRad += rawHorizontalRad
            centerAccumVerticalRad += rawVerticalRad
            centerSampleCount += 1
            let needed = 20
            if centerSampleCount >= needed {
                centerHorizontalRad = centerAccumHorizontalRad / Double(centerSampleCount)
                centerVerticalRad = centerAccumVerticalRad / Double(centerSampleCount)
                gazeCenterCalibrated = true
                fixationStartSample = nil
                fixationStreak = 0
                let hDeg = centerHorizontalRad * 180.0 / .pi
                let vDeg = centerVerticalRad * 180.0 / .pi
                print("[Scene] calibrated gaze center offset h=\(String(format: "%.2f", hDeg))° v=\(String(format: "%.2f", vDeg))° from \(centerSampleCount) samples")
            }
        }

        let horizontalRad: Double
        let verticalRad: Double
        if gazeCenterCalibrated {
            horizontalRad = rawHorizontalRad - centerHorizontalRad
            verticalRad = rawVerticalRad - centerVerticalRad
        } else {
            horizontalRad = rawHorizontalRad
            verticalRad = rawVerticalRad
        }
        let horizontalDeg = horizontalRad * 180.0 / .pi
        let verticalDeg = verticalRad * 180.0 / .pi
        let angleSample = AngleSample(timestamp: sample.t, horizontalDeg: horizontalDeg, verticalDeg: verticalDeg)
        lastSampleTime = sample.t

        switch state {
        case .fixate:
            processFixation(sample: angleSample)
        case .go, .stop:
            gazeSamples.append(angleSample)
            distanceSamples.append(sample.distanceCm)
            monitorHeadMotion()
            evaluateSaccade(for: trial, goTime: goStartTime ?? sample.t)
        default:
            print("[Scene] ignoring sample (state=\(state))")
            break
        }
    }

    func checkForLostTracking(currentTime: TimeInterval) {
        guard let last = lastSampleTime else { return }
        let deltaMs = (currentTime - last) * 1000.0
        if deltaMs >= 1500 {
            if !lostTrackingFlag {
                lostTrackingFlag = true
                lastHintTime = currentTime
        showCoachingMessage("Hold steady and look at the owl so we can find your eyes.")
        }
    }
    }

    func processFixation(sample: AngleSample) {
        let radius = hypot(sample.horizontalDeg, sample.verticalDeg)
        print("[Fixation candidate] radius=\(String(format: "%.2f", radius))° state=\(state)")
        let effectiveRadiusDeg = config.fixationRadiusDeg
        if radius <= effectiveRadiusDeg {
            fixationDifficultyStart = nil
            fixationStreak += 1
            if fixationStartSample == nil {
                fixationStartSample = sample.timestamp
            }
            let durationMs = (sample.timestamp - (fixationStartSample ?? sample.timestamp)) * 1000.0
            // See AGENTS.md – toddler-friendly fixation window (~300–333 ms at 60 Hz).
            let minSamplesForTime = Int(ceil(config.samplingRateHz * 0.3))
            let requiredSamples = max(config.fixationSamplesRequired, minSamplesForTime)
            print(String(
                format: "[Fixation] radius=%.2f°, window=%.2f°, streak=%d, durationMs=%d, requiredSamples=%d",
                radius,
                effectiveRadiusDeg,
                fixationStreak,
                Int(durationMs),
                requiredSamples
            ))
            if fixationStreak >= requiredSamples && durationMs >= 300.0 {
                beginGoPhase(at: sample.timestamp)
            }
        } else {
            trackFixationDifficulty(sample: sample, radius: radius)
            if fixationStreak > 0 {
                print("[Fixation reset] radius=\(String(format: "%.2f", radius))°")
            }
            fixationStreak = 0
            fixationStartSample = nil
        }
    }

    func trackFixationDifficulty(sample: AngleSample, radius: Double) {
        let thresholdDeg = 10.0
        guard radius >= thresholdDeg else {
            fixationDifficultyStart = nil
            return
        }
        if fixationDifficultyStart == nil {
            fixationDifficultyStart = sample.timestamp
        }
        guard let start = fixationDifficultyStart else { return }
        let elapsedMs = (sample.timestamp - start) * 1000.0
        if elapsedMs >= 3000 {
            showFixationHintIfNeeded(now: sample.timestamp)
        }
    }

    func showFixationHintIfNeeded(now: TimeInterval) {
        guard canShowHint(now: now) else { return }
        lastHintTime = now
        showCoachingMessage("Keep your eyes on the owl so the firefly knows where you're looking.")
        print("[Fixation] showing guidance hint for sustained off-center gaze")
    }

    func canShowHint(now: TimeInterval, cooldownMs: Double = 5000.0) -> Bool {
        if let last = lastHintTime {
            let deltaMs = (now - last) * 1000.0
            if deltaMs < cooldownMs { return false }
        }
        return true
    }

    func showCoachingMessage(_ message: String, duration: TimeInterval = 2.8) {
        hintLabel.removeAllActions()
        hintLabel.text = message
        hintLabel.alpha = 1.0
        hintLabel.isHidden = false
        let padding: CGFloat = 18
        let textSize = hintLabel.frame.insetBy(dx: -padding, dy: -padding)
        let bubblePath = UIBezierPath(roundedRect: textSize, cornerRadius: 12)
        hintBackground.path = bubblePath.cgPath
        hintBackground.position = hintLabel.position
        hintBackground.isHidden = false
        let wait = SKAction.wait(forDuration: duration)
        hintLabel.run(wait) { [weak self] in
            self?.hintLabel.isHidden = true
            self?.hintBackground.isHidden = true
        }
    }

    func beginGoPhase(at timestamp: TimeInterval) {
        guard let trial = scheduledTrial else {
            print("[Scene] beginGoPhase() called with no scheduled trial")
            return
        }
        print("[Scene] beginGoPhase() – transitioning to .go at t=\(timestamp) for trial index=\(trial.index) block=\(trial.block) type=\(trial.type) dir=\(trial.direction)")
        state = .go
        trialCompleted = false
        goStartTime = timestamp
        stopSignalTime = trial.ssdMs.map { timestamp + Double($0) / 1000.0 }
        gazeSamples.removeAll(keepingCapacity: true)
        distanceSamples.removeAll(keepingCapacity: true)
        headMotionFlag = false
        lostTrackingFlag = false
        presentStimulus(for: trial)
    }

    func presentStimulus(for trial: ScheduledTrial) {
        let targetDeg = trial.direction == .left ? -config.targetEccentricityDeg : config.targetEccentricityDeg
        // Map desired eccentricity in degrees into scene coordinates. We scale so that the
        // target lies comfortably within the horizontally visible portion of the scene,
        // even when the SpriteKit view crops the sides on tall iPhones.
        let halfWidth = visibleHalfWidth > 0 ? visibleHalfWidth : size.width / 2.0
        let maxOffset = halfWidth * 0.8
        let unitsPerDegree = maxOffset / CGFloat(config.targetEccentricityDeg)
        let offset = CGFloat(targetDeg) * unitsPerDegree
        print("[Scene] presentStimulus() – targetDeg=\(targetDeg) offset=\(offset) sceneWidth=\(size.width) visibleHalfWidth=\(halfWidth)")
        fireflyNode.removeAllActions()
        fireflyNode.position = CGPoint(x: offset, y: 0)
        fireflyNode.setScale(0.85)
        fireflyNode.alpha = 0
        fireflyNode.isHidden = false
        // Keep the owl visible on STOP trials so the central STOP sign can appear,
        // but hide it on GO trials to emphasize the peripheral step target.
        owlNode.isHidden = (trial.type == .go)
        let fadeIn = SKAction.fadeIn(withDuration: 0.05)
        let scaleUp = SKAction.scale(to: 1.05, duration: 0.08).easeOut()
        let settle = SKAction.scale(to: 1.0, duration: 0.06).easeOut()
        let pulse = SKAction.sequence([scaleUp, settle])
        let appear = SKAction.group([fadeIn, pulse])
        fireflyNode.run(appear)
        fireflyNode.run(SKAction.repeatForever(glowAnimation()))
        if fireflyNode.action(forKey: "idleBob") == nil {
            let bobUp = SKAction.moveBy(x: 0, y: 6, duration: 0.9)
            bobUp.timingMode = .easeInEaseOut
            let bobSequence = SKAction.sequence([bobUp, bobUp.reversed()])
            fireflyNode.run(SKAction.repeatForever(bobSequence), withKey: "idleBob")
        }
        stopNode.isHidden = true
        feedbackNode.isHidden = true
    }

    func updateStopStateIfNeeded(currentTime: TimeInterval, trial: ScheduledTrial) {
        guard trial.type == .stop, let stopTime = stopSignalTime, currentTime >= stopTime else { return }
        state = .stop
        showStopSignal()
    }

    func showStopSignal() {
        stopNode.removeAllActions()
        owlNode.isHidden = false
        stopNode.isHidden = false
        stopNode.alpha = 0
        stopNode.setScale(0.9)
        let startPosition = CGPoint(x: 0, y: 90)
        let raisedPosition = CGPoint(x: 0, y: 120)
        stopNode.position = startPosition
        let moveUp = SKAction.move(to: raisedPosition, duration: 0.12).easeOut()
        let fadeIn = SKAction.fadeIn(withDuration: 0.12)
        let appear = SKAction.group([moveUp, fadeIn, SKAction.scale(to: 1.0, duration: 0.12).easeOut()])
        stopNode.run(appear)
    }

    func evaluateSaccade(for trial: ScheduledTrial, goTime: TimeInterval) {
        let outcome = detector.evaluate(samples: gazeSamples, goTime: goTime, direction: trial.direction)
        guard let rt = outcome.reactionTimeMs else { return }
        if trial.type == .go {
            concludeTrial(reason: .completion(outcome))
        } else {
            if let ssd = trial.ssdMs, rt >= ssd {
                concludeTrial(reason: .completion(outcome))
            } else {
                concludeTrial(reason: .completion(outcome))
            }
        }
    }

    func evaluateTimeout(currentTime: TimeInterval, goTime: TimeInterval, trial: ScheduledTrial) {
        let elapsed = (currentTime - goTime) * 1000.0
        if Int(elapsed) >= config.goTimeoutMs {
            concludeTrial(reason: .timeout)
        }
    }

    func monitorHeadMotion() {
        guard let first = distanceSamples.first, let last = distanceSamples.last else { return }
        if abs(last - first) > 3.0 {
            headMotionFlag = true
        }
        if distanceSamples.count >= 2 {
            let maxDistance = distanceSamples.max() ?? last
            let minDistance = distanceSamples.min() ?? first
            if maxDistance - minDistance > 5.0 {
                headMotionFlag = true
            }
        }
    }
}

// MARK: - Trial completion
private extension FireFlyScene {
    func advanceToNextTrial() {
        guard let block = currentBlock else {
            print("[Scene] advanceToNextTrial() – currentBlock is nil")
            return
        }
        let modeLabel = "\(block)"
        switch block {
        case .training:
            scheduledTrial = engine.nextTrainingTrial()
        case .baseline:
            scheduledTrial = engine.nextBaselineTrial()
        case .sst:
            scheduledTrial = engine.nextSSTTrial()
        }
        if let trial = scheduledTrial {
            print("[Scene] advanceToNextTrial() – mode=\(modeLabel) index=\(trial.index) block=\(trial.block) type=\(trial.type) dir=\(trial.direction)")
        } else {
            print("[Scene] advanceToNextTrial() – mode=\(modeLabel) yielded nil (no more trials)")
        }
        goStartTime = nil
        stopSignalTime = nil
        fixationStartSample = nil
        fixationStreak = 0
        trialCompleted = false
        gazeSamples.removeAll(keepingCapacity: true)
        distanceSamples.removeAll(keepingCapacity: true)
        fireflyNode.isHidden = true
        stopNode.isHidden = true
        feedbackNode.isHidden = true
        owlNode.isHidden = false
        if scheduledTrial == nil {
            state = .calibrate
            print("[Scene] state set to .calibrate (no scheduled trial)")
            onBlockFinished?(block)
        } else {
            state = .fixate
            print("[Scene] state set to .fixate – waiting for fixation")
        }
    }

    func concludeTrial(reason: TrialEndReason) {
        guard !trialCompleted, let trial = scheduledTrial, let goTime = goStartTime else { return }
        trialCompleted = true
        let outcome: SaccadeOutcome
        switch reason {
        case .completion(let provided):
            outcome = provided
        case .timeout:
            outcome = detector.evaluate(samples: gazeSamples, goTime: goTime, direction: trial.direction)
        }

        let averageDistance = distanceSamples.isEmpty ? 60.0 : distanceSamples.reduce(0, +) / Double(distanceSamples.count)
        let rmse = computeRMSE(for: trial)
        let metrics = makeMetrics(trial: trial, outcome: outcome, rmse: rmse, averageDistance: averageDistance, reason: reason)
        let recorded = engine.record(trial: trial, metrics: metrics)
        onTrialFinished?(recorded)
        updateFeedback(for: trial, outcome: outcome, reason: reason)
        cleanupAfterTrial(for: trial)
    }

    func computeRMSE(for trial: ScheduledTrial) -> Double {
        guard !gazeSamples.isEmpty else { return 0 }
        let targetDeg = trial.type == .go ? (trial.direction == .left ? -config.targetEccentricityDeg : config.targetEccentricityDeg) : 0.0
        let mse = gazeSamples.reduce(0.0) { partial, sample in
            let error = sample.horizontalDeg - targetDeg
            return partial + error * error
        } / Double(gazeSamples.count)
        return sqrt(mse)
    }

    func makeMetrics(trial: ScheduledTrial, outcome: SaccadeOutcome, rmse: Double, averageDistance: Double, reason: TrialEndReason) -> TrialMetricsInput {
        var goSuccess = trial.type == .go && outcome.enteredCorridor
        var stopSuccess = trial.type == .stop && !outcome.enteredCorridor
        var rt = outcome.reactionTimeMs
        if trial.type == .stop {
            goSuccess = false
        }
        if case .timeout = reason {
            goSuccess = false
            stopSuccess = trial.type == .stop && !outcome.enteredCorridor
            rt = nil
        }

        return TrialMetricsInput(
            goOnsetMs: 0,
            rtMs: rt,
            goSuccess: goSuccess,
            stopSuccess: stopSuccess,
            gazeRMSEDeg: rmse,
            viewingDistanceCm: averageDistance,
            headMotionFlag: headMotionFlag,
            lostTrackingFlag: lostTrackingFlag
        )
    }

    func updateFeedback(for trial: ScheduledTrial, outcome: SaccadeOutcome, reason: TrialEndReason) {
        fireflyNode.isHidden = true
        if trial.type == .go {
            if case .timeout = reason {
                feedbackNode.texture = SKTexture(imageNamed: "faster_text")
                feedbackNode.isHidden = false
            } else {
                feedbackNode.isHidden = true
            }
        } else {
            if outcome.enteredCorridor {
                feedbackNode.texture = SKTexture(imageNamed: "red_x")
                feedbackNode.isHidden = false
            } else {
                feedbackNode.isHidden = true
            }
        }
    }

    func cleanupAfterTrial(for trial: ScheduledTrial) {
        state = .feedback
        hintLabel.isHidden = true
        if !stopNode.isHidden {
            let loweredPosition = CGPoint(x: 0, y: 90)
            let moveDown = SKAction.move(to: loweredPosition, duration: 0.15).easeOut()
            let fadeOut = SKAction.fadeOut(withDuration: 0.15)
            let lower = SKAction.group([moveDown, fadeOut])
            stopNode.run(lower) { [weak self] in
                self?.stopNode.isHidden = true
            }
        }
        let feedbackDuration = 0.45
        run(SKAction.wait(forDuration: feedbackDuration)) { [weak self] in
            guard let self else { return }
            self.state = .iti
            self.run(SKAction.wait(forDuration: self.randomITI())) { [weak self] in
                guard let self else { return }
                if let pauseType = self.pauseReason(after: trial) {
                    self.state = .paused
                    self.onBreakRequested?(pauseType)
                } else {
                    self.advanceToNextTrial()
                }
            }
        }
    }

    func randomITI() -> TimeInterval {
        let min = Double(config.itiRangeMs.lowerBound)
        let max = Double(config.itiRangeMs.upperBound)
        let roll = Double(itiRng.next()) / Double(UInt64.max)
        return (min + (max - min) * roll) / 1000.0
    }

    func pauseReason(after trial: ScheduledTrial) -> BreakType? {
        if trial.block == .sst, !hasIssuedMidSSTBreak {
            let validGo = engine.validSSTGoCount
            let validStop = engine.validSSTStopCount
            // Trigger mid-block break when child has reached roughly half of valid targets,
            // or after 30 total SST attempts as a fallback.
            if (validGo >= 10 && validStop >= 8) || engine.completedSSTCount >= 30 {
                hasIssuedMidSSTBreak = true
                return .midSST
            }
        }
        return nil
    }
}

private enum TrialEndReason {
    case completion(SaccadeOutcome)
    case timeout
}

private extension SKAction {
    func easeOut() -> SKAction {
        timingFunction = { t in
            let inv = t - 1
            return inv * inv * inv + 1
        }
        return self
    }
}
