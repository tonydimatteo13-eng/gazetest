# Fire Fly (ARIS) — iPad PoC
**Version:** 2025-10-01  
**Purpose:** Investor‑demo iPad app that runs a **gaze‑based Stop‑Signal Task (SST)** reskinned as a forest game. It produces a
**Proactive Control score** and an **ASD‑likeness category** (not a diagnosis). Anonymous telemetry is uploaded to **Airtable**.

---

## 1) Scientific grounding (requirements we must mirror)
Based on Kelly et al., 2021 (oculomotor SST in ASD vs TD). We reproduce the task structure and the metrics used in the paper.

**Blocks**
- **Baseline**: GO‑only trials.
- **Main SST**: mixture of GO and STOP trials.

**Per‑trial rules**
- **Fixation**: require central fixation for **≥500 ms** before each GO stimulus.
- **GO**: peripheral target at **±12°** horizontally from screen center.
- **STOP**: on a subset of trials, a **central STOP sign** appears after a **Stop‑Signal Delay (SSD)** ∈ **[50, 200] ms** post‑GO.
- **GO timeout**: **650 ms**; display “FASTER!” feedback on timeouts.
- **GO correct**: first saccade is toward target and reaches **≥6°** in that direction (ROI‑based at 60 Hz).
- **STOP correct**: **no** saccade toward target after the STOP sign appears.

**Trial counts (PoC)**
- Baseline: **30** GO‑only trials.
- Main SST: **120** trials, **60% GO / 40% STOP**; no more than **3** of the same type in a row; left/right pseudorandom.

---

## 2) Platforms & tech
- **iPadOS 17+**, **Xcode 15+**, **Swift 5.9+**
- **ARKit Face Tracking** (eye‑gaze via TrueDepth camera), **SpriteKit** (gameplay), **SwiftUI** (shell UI)
- 60 Hz gaze sampling; ROI‑based saccade detection (velocity profiles are not available at 60 Hz).

---

## 3) UX & screens

### A) Welcome
Copy: “Keep your face in view. Look at the firefly quickly. If a STOP sign appears, **don’t** look at it.”  
Buttons: `Start` • `About the task` • `Privacy`  
Footer: “Demo only. Not a diagnosis.” If device lacks face tracking, show “Device not supported.”

### B) Calibration (9‑point)
Nine stars (center, corners, edge midpoints), each ~300–500 ms fixation. Fit a mapping from gaze ray + head pose → screen coordinates. Output **RMSE in degrees**.

### C) Baseline (30 GO‑only)
Fixation **≥500 ms** → GO at **±12°**. Timeout **650 ms** → “FASTER!”. ITI 1000–1500 ms jitter.

### D) Main SST (120 trials)
60% GO / 40% STOP; L/R pseudorandom; max 3 same‑type in a row. STOP appears at **SSD 50–200 ms** post‑GO. Feedback: red X on STOP failure; “FASTER!” on GO timeout.

### E) Results
Show: **Baseline RT**, **GO RT (SST)**, **GO‑RT Slowing**, **Stopping Accuracy**, **SSRT** (display‑only), plus a single **Proactive Control z‑score** and **ASD‑likeness** category (“Typical‑like”, “Indeterminate”, “ASD‑like”). Buttons: `Export to Airtable` (if not auto), `Restart`, `About`.

---

## 4) Gaze, calibration, and degrees↔pixels

- Use `ARFaceTrackingConfiguration`. For each frame, compute a **gaze ray**; intersect with the screen plane to get a 2‑D point.
- **Calibration**: 9‑point capture → fit **affine** (or thin‑plate spline) mapping to screen coords; compute **RMSE (deg)**. If RMSE > **1.5°**, request recalibration.
- **Degrees↔pixels**: assume **60 cm** nominal viewing distance (1° ≈ 1.05 cm). Convert to px from device PPI. Also estimate distance from TrueDepth per frame; write to logs and flag large in‑trial distance shifts (>5 cm).

**Saccade detection @ 60 Hz**
- **Fixation lock**: **≥8** consecutive frames inside a **3°** radius around center.
- **Onset**: first frame exiting the central exclusion zone into the correct **target corridor**; confirm next frame to debounce.
- **GO correct**: first landing within **6°** of target after onset. **Anticipations <100 ms** are invalid and excluded.
- **STOP correct**: **no** corridor entry after STOP appears.

---

## 5) Measures & scoring

**Primary metrics**
- **Baseline RT (ms)**: mean RT across valid baseline GO trials.
- **GO RT (SST)**: mean RT across valid GO trials in SST.
- **GO‑RT Slowing (ms)** = GO RT (SST) − Baseline RT.
- **Stopping Accuracy (%)** = % STOP trials with no post‑STOP saccade.
- **SSRT (integration method)** (display only):  
  1) pFail = failed_STOP / total_STOP  
  2) Sort SST GO RTs, take RT* at the pFail percentile  
  3) SSRT = RT* − mean(SSD)

**Demo classifier (two‑feature Gaussian Naïve Bayes)**
- Priors (from literature):  
  - Stopping Accuracy — TD μ=69, σ=15; ASD μ=62, σ=17  
  - GO‑RT Slowing (ms) — TD μ=99, σ=53; ASD μ=73, σ=50
- Compute P(ASD‑like) from the two features with equal class priors.
- Thresholds: **≥0.70** ASD‑like; **0.30–0.70** Indeterminate; **≤0.30** Typical‑like.
- **SSRT is not weighted** in the classifier. Display for completeness.

**Proactive Control z‑score**
Mean of TD‑referenced z‑scores for Stopping Accuracy and GO‑RT Slowing (0 = TD mean).

---

## 6) Data quality & exclusions
- Exclude trials with `rt_ms < 100`, `gaze_rmse_deg > 2.5`, head translation > **3 cm**, or lost tracking.
- Require **≥40** valid GO (SST) and **≥20** valid STOP to compute a score. Otherwise show “Need more data.”

---

## 7) Anonymous telemetry → Airtable

**Transport**
- Preferred: client → **serverless proxy** (e.g., Cloudflare Worker / Vercel) → Airtable using a **PAT** stored on the server.
- Demo‑only: direct Airtable calls from client with PAT embedded (under a `DEMO_ONLY` build flag).

**Airtable mechanics**
- Endpoint: `POST https://api.airtable.com/v0/{{baseId}}/{{table}}` (JSON).
- Auth: `Authorization: Bearer <PAT>` header.
- **Batch limit**: create **≤10** records per request — chunk trial uploads.
- **Rate limit**: ~**5 requests/sec per base** (and PAT caps). On **429**, apply **exponential backoff + jitter** (base 500 ms, factor 2, cap 30 s, ≤6 retries).
- **Offline queue**: persist unsent batches to disk; drain on app foreground.
- **Idempotency**: include a per‑batch UUID; do not re‑send successful batches.

**Airtable base schema**

**Table: `Sessions`**
- `session_uid` (text, UUIDv4) — random per run
- `started_at` (created time)
- `app_version`, `device_model`, `os_version` (text)
- `viewing_distance_mean_cm` (number)
- `calibration_rmse_deg` (number)
- `age_bucket` (single select: 18–24 / 25–34 / 35–44 / 45+ / Prefer not to say)
- `notes` (long text, optional)
- Links: `Results` (1:1), `Trials` (1:many)

**Table: `Trials`**
- `Session` (link to Sessions)
- `trial_index` (number)
- `block` (BL/SST)
- `type` (GO/STOP)
- `dir` (L/R)
- `go_onset_ms` (number)
- `ssd_ms` (number, empty for GO)
- `rt_ms` (number, empty on STOP success)
- `go_success`, `stop_success` (checkbox)
- `gaze_rmse_deg`, `viewing_distance_cm` (number)
- `head_motion_flag`, `lost_tracking_flag` (checkbox)

**Table: `Results`**
- `Session` (link to Sessions)
- `baseline_rt_ms`, `go_rt_sst_ms`, `go_rt_slowing_ms` (numbers)
- `stop_accuracy_pct`, `ssrt_ms` (numbers)
- `p_asd_like`, `proactive_z` (numbers)
- `classification_label` (single select: Typical‑like / Indeterminate / ASD‑like)
- `included_go`, `included_stop` (numbers)
- `build_id` (text)

**Privacy**
- No names, emails, phone numbers, images, IPs, or persistent device IDs.
- Only session‑scoped UUID and optional **age bucket**.

---

## 8) Assets & art direction
- Use the provided vectors (names are binding):  
  `bg_sky`, `bg_trees_back`, `bg_trees_mid`, `bg_trees_front`, `bg_ground`,  
  `owl_body`, `owl_eyes_open`, `owl_eyes_blink`,  
  `firefly_idle`, `firefly_glow_1`, `firefly_glow_2`, `firefly_glow_3`,  
  `stop_sign`, `red_x`, `star_calib`, `faster_text`.
- All sprites are centered (0.5, 0.5). Glow frames share identical bounds. Minimal motion; STOP pop‑in 120 ms (scale 0.9→1.0).

---

## 9) Performance, accessibility, disclaimers
- 60 fps target; no per‑frame allocations in the game loop.
- Audio off; no haptics (avoid attentional confounds).
- Disclaimers on Welcome & Results: “Demo only. Not a diagnosis.”

---

## 10) Definition of Done (DoD)
- App compiles and runs on iPad with TrueDepth camera.
- Collects **≥40 GO** and **≥20 STOP** valid trials; computes all metrics and classifier; renders Results.
- Uploads to Airtable (if enabled): creates 1 `Sessions` row, N `Trials` in chunks of ≤10, 1 `Results` row linked to session; handles 429/backoff and offline queue.
- All acceptance tests in **AGENTS.md** pass.
