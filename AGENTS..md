# AGENTS.md — Build Plan for gpt‑codex‑high

## Role & mode
You are the **Build Agent** for an iPad app named **FireFlyApp**. Implement exactly what the PRD specifies. Treat all timings and thresholds as **hard constraints**.

## Repo layout
```
FireFlyApp/
  App/
  Game/
  Gaze/
  Scoring/
  Gateway/
  Resources/
  Tests/
assets/vector/          # provided SVGs
docs/
```

## Tasks (do in order)
1) **Scaffold Xcode project** (iPadOS 17+, Swift 5.9+). Add Camera/Face Tracking entitlements.
2) **SwiftUI shell**: screens for Welcome, Calibration, Baseline, SST, Results; About & Privacy modals.
3) **ARKit GazeTracker** (`ARFaceTrackingConfiguration`), per‑frame gaze ray → screen point; expose `latestPoint`, `latestDistanceCm`.
4) **Calibrator**: 9‑point capture → fit mapping; compute **RMSE (deg)**; force recalibration if RMSE > 1.5°.
5) **SpriteKit scene** with states `.calibrate → .fixate → .go → (.stop?) → .feedback → .iti`.
   - Fixation **≥500 ms** inside 3° radius.
   - GO at ±12°; timeout **650 ms** ⇒ “FASTER!” overlay.
   - STOP appears after **SSD 50–200 ms**; max 3 same‑type trials in a row.
6) **Saccade detection** (ROI‑based, 60 Hz): onset at corridor exit; GO correct if first landing ≥6° toward target; STOP correct if no corridor entry after STOP; drop RT <100 ms.
7) **Data model**: `Session`, `Trial`, `Results` structs matching PRD fields. Persist in memory during run.
8) **Scorer**: compute Baseline RT, GO RT (SST), Slowing, Stopping Accuracy, SSRT (integration), and Bayes classifier (two features). Emit Proactive z‑score and category thresholds (≥0.70 / 0.30–0.70 / ≤0.30).
9) **Airtable/Proxy client** (behind flags): batch create **≤10** trials per request; handle **429** with exponential backoff + jitter (base 500 ms, factor 2, cap 30 s, ≤6 retries). Provide offline queue (disk) + idempotent batch IDs.
10) **Assets**: import vectors (convert to single‑scale PDF) into `Assets.xcassets` using the **exact names** given in PRD. Optional parallax on `bg_*`.
11) **Results UI**: show numeric metrics, z‑score gauge, ASD‑likeness label; export/upload button.
12) **Config**: add `.xcconfig.sample` with:
```
UPLOAD_ENABLED = NO
USE_PROXY = YES
API_BASE_URL = https://example-worker.example.workers.dev
AIRTABLE_BASE_ID = appXXXXXXXXXXXXXX
AIRTABLE_TABLE_SESSIONS = Sessions
AIRTABLE_TABLE_TRIALS = Trials
AIRTABLE_TABLE_RESULTS = Results
# Demo-only (if USE_PROXY = NO)
AIRTABLE_PAT = *** PLACEHOLDER ***
```
13) **Determinism/TestMode**: seed RNG for trial order/SSD when `TestMode` is on.

## Public types & signatures (must implement)
```swift
// Gaze/GazeTracker.swift
final class GazeTracker: NSObject, ARSessionDelegate {
    struct Sample { let t: TimeInterval; let point: CGPoint; let distanceCm: Double }
    var latestPoint: CGPoint { get }
    var latestDistanceCm: Double { get }
    func start()
    func stop()
}

// Gaze/Calibrator.swift
struct CalibrationResult { let rmseDeg: Double; let transform: simd_double3x3 }
final class Calibrator {
    func begin()
    func capture(point screenPt: CGPoint, sample gazeRay: simd_double3)
    func finish() -> CalibrationResult
    func screenPoint(from gazeRay: simd_double3, headPose: simd_double4x4) -> CGPoint
}

// Game/FireFlyScene.swift
final class FireFlyScene: SKScene {
    enum State { case calibrate, fixate, go, stop, feedback, iti }
    var onTrialFinished: ((Trial) -> Void)?
    func configure(with config: GameConfig, calibrator: Calibrator, gaze: GazeTracker)
    func startBaseline()
    func startSST()
}

// Scoring/Scorer.swift
struct SessionMeta { /* PRD session fields */ }
struct Trial { /* PRD trial fields */ }
enum ClassLabel: String { case typicalLike = "Typical-like", indeterminate = "Indeterminate", asdLike = "ASD-like" }
struct Results { /* PRD results fields + classifier outputs */ }

struct Scorer {
    static func computeResults(session: SessionMeta, trials: [Trial]) -> Results
    static func ssrt(goRTs: [Double], ssds: [Double], pFail: Double) -> Double
    static func bayesASDLike(stopAcc: Double, slowingMs: Double) -> (p: Double, label: ClassLabel, z: Double)
}

// Gateway/AirtableClient.swift (or ApiClient.swift when using proxy)
final class AirtableClient {
    init(cfg: AirtableConfig)
    func createSession(_ fields: [String: Any]) async throws -> String
    func createTrials(sessionRecordId: String, trials: [[String: Any]]) async throws
    func createResults(sessionRecordId: String, fields: [String: Any]) async throws
}
```

## Acceptance tests
- **AT‑1 Calibration quality**: synthetic gaze with 1° noise ⇒ RMSE ≤ 1.2°; with 3° noise ⇒ RMSE > 1.5° and UI forces recalibration.
- **AT‑2 Baseline timing**: simulated saccades at 250 ms ⇒ baseline mean RT ∈ [240,260] ms; timeouts at 650 ms show “FASTER!”.
- **AT‑3 STOP accuracy**: simulated perfect stopping ⇒ accuracy ≥95% across SSDs.
- **AT‑4 SSD window**: recorded `ssd_ms` uniformly cover 50–200 ms (±10 ms).
- **AT‑5 Scorer math**: fixture `score_typical.json` ⇒ `p_asd_like ≤ 0.30`; fixture `score_asdlike.json` ⇒ `p_asd_like ≥ 0.70`.
- **AT‑6 Exclusions**: `rt_ms < 100` or `gaze_rmse_deg > 2.5` ⇒ excluded from denominators.
- **AT‑7 Upload chunking**: 23 trials ⇒ exactly 3 create requests (10/10/3).
- **AT‑8 429 backoff**: first two calls return 429 ⇒ exponential backoff + jitter; eventual success; no duplicates.
- **AT‑9 Offline queue**: network loss mid‑block ⇒ results still display; on next foreground uploads Session + Trials + Results and links correctly.

## Coding constraints
- No third‑party SDKs. No analytics. No secrets in source control.
- Deterministic RNG for `TestMode`. Clear comments for any heuristics (e.g., ROI sizes).
- 60 fps; avoid allocations in `update(_:)`.

## Runbook
- Open the project in Xcode, run on an iPad with TrueDepth camera.
- If enabling upload, duplicate `.xcconfig.sample` → `.xcconfig`, fill IDs/URLs, set `UPLOAD_ENABLED=YES`.
- Use attached vectors; convert to single‑scale PDFs; keep names unchanged.

## Deliverables
- Compilable project, assets catalog, unit tests, fixtures, `.xcconfig.sample`, short README.
- Print file tree + acceptance‑test checklist at the end of the build run.
