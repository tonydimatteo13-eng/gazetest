# FireflyStopSignalAgent

## Purpose

`FireflyStopSignalAgent` runs the owl–firefly oculomotor stop-signal task (SST) to estimate proactive and reactive inhibitory control in young children. It implements a short-form, toddler-feasible version of the oculomotor SST described by Kelly et al. 2021 (12° step targets; central STOP signal) while maintaining compatibility with our scoring and ASD-likeness models. :contentReference[oaicite:0]{index=0}  

The agent is designed to:
- Collect **valid, analyzable eye-movement data** under realistic conditions with toddlers.
- Provide a **game-like experience** that most children can complete in 3–6 minutes.
- Surface **calibration/signal quality** to the operator and avoid running long sessions with unusable data.

---

## Task Structure

### High-Level Flow

1. **Calibration**
2. **Training Block (Practice – not scored)**
3. **Baseline Block (GO-only)**
4. **Stop-Signal Block (SST: GO + STOP)**
5. **Results / Summary**

The agent exposes block-level progress and short micro-breaks between blocks to improve completion rates.

---

## Calibration

Before any trials:

- The agent runs a gaze **calibration** sequence using an animated target.
- Calibration returns an **RMSE in visual degrees** (`rmseDeg`) between the gaze estimate and known target positions.

**Calibration quality rules:**

- **Good:** `rmseDeg ≤ 1.5°`  
  - Proceed to Training Block.
- **OK:** `1.5° < rmseDeg ≤ 2.0°`  
  - Allow progression but strongly encourage recalibration (operator-visible warning).
- **Poor:** `rmseDeg > 2.0°`  
  - The UI must **block progression** and prompt the operator to redo calibration.
  - The agent should not start task blocks while in this state.

The calibration screen must display a simple quality message (Good/OK/Poor) and the numeric RMSE so the operator understands signal quality before continuing.

---

## Training Block (Practice – Not Scored)

**Purpose:**  
Make the GO and STOP rules intuitive and give the child a chance to practice with explicit feedback. Training trials are **never used in analysis**.

**Trials:** ~10 total, split into:

1. **GO Practice (~6 trials)**
   - Stimuli:
     - Central owl (fixation).
     - Firefly (white circle) appears at ±12° horizontally.
   - Instructions:
     - “Look at the owl. When the firefly appears, jump your eyes to it as fast as you can.”
   - Feedback:
     - Show clear per-trial feedback (“Nice! That one counted!” vs “Too slow, let’s try faster.”).

2. **STOP Practice (~4 trials)**
   - Stimuli:
     - Same owl + firefly as GO.
     - STOP signal: stop sign held by the owl at center, appearing after SSD.
   - Instructions:
     - “If the owl shows a STOP sign, keep your eyes on the owl and do NOT look at the firefly.”
   - Feedback:
     - Success: “Perfect, you stayed on the owl when STOP showed up.”
     - Failure: “You chased the firefly. When STOP appears, freeze on the owl.”

**Constraints:**

- Training uses the same 12° step targets and central STOP signal as the main blocks.
- Training trials are tagged as `block = training` (or equivalent) and excluded from metrics and model inputs.

---

## Baseline Block

**Trials:** 10 GO-only trials. :contentReference[oaicite:1]{index=1}  

**Stimuli:**

- Central owl fixation cross.
- Firefly (white circle) appears at ±12° horizontally.

**Timing:**

- Fixation: 1500–2000 ms (jittered; extended if fixation unstable).
- GO cue duration: up to 650 ms (deadline).

**Instructions:**

- “Follow the firefly as fast as you can when it appears.”

**Purpose:**

- Establish baseline visually guided saccade RT distribution.

**UX:**

- Show a simple progress indicator, e.g. “Part 1: Fireflies 3 / 10.”
- At block end, show a brief break screen: 
  - “Part 1 done! Next, the owl will sometimes show a STOP sign when the firefly appears.”

---

## Stop-Signal Block (SST)

**Trials:** up to 60 trials. :contentReference[oaicite:2]{index=2}  

- GO trials: 60% (~36)
- STOP trials: 40% (~24)

**Stimuli:**

- Central owl (fixation).
- Firefly appears at ±12° as a step target.
- STOP signal: stop sign held by the owl at center.

**Timing:**

- Fixation: 1500–2000 ms (jittered).
- GO cue: 12° left/right.
- GO deadline: 650 ms.
- SSD: 50–200 ms after GO onset, randomized each STOP trial.

**Constraints:**

- Max 3 GO or STOP trials in a row.
- Max 3 left or right trials in a row.

**Instructions:**

- GO: “Follow the firefly.”
- STOP: “If the owl shows a STOP sign, keep your eyes on the owl and do NOT look at the firefly.”

**UX / Pacing:**

- Show block progress, e.g. “Forest fireflies: 18 / 40.”
- Provide a short **mid-block break** around trial 30–40:  
  - “Halfway there. Take a breath, then tap when you’re ready for more fireflies.”
- Provide subtle per-trial feedback (e.g., small success icon) so the user feels the game is responsive.

---

## Fixation & Gaze Stability

Each trial begins with a fixation period:

- Child must maintain gaze near the central owl before GO stimulus onset.
- Fixation criteria are tuned to require ~300–350 ms of stable gaze on the owl (e.g., ~18–20 samples at 60 Hz). This is implemented via:
  - A required number of consecutive samples within a central window (e.g., 3° radius).
  - Automatic extension of fixation if stability criteria are not met.

If fixation is not achieved within a reasonable time (e.g., several seconds), the agent should:

- Provide a simple coaching overlay:
  - “Keep your eyes on the owl so the firefly knows where you’re looking.”
- Optionally skip or retry the trial.

Downstream scoring can still apply stricter gaze-quality checks per trial (e.g., gaze RMSE thresholds), but the online fixation logic is intentionally less punishing to keep the task flowing.

---

## Early-Stop Logic

To avoid over-long sessions while preserving data quality, the agent supports early termination of the SST block.

**Minimum per-session valid data (for analysis):** :contentReference[oaicite:3]{index=3}  

- Baseline: ≥ 8 valid GO trials.
- SST: ≥ 20 valid GO trials and ≥ 16 valid STOP trials.

**Heuristic early stop (if `enableEarlyStop = true`):**

When:

- Total SST trials ≥ 40, **and**
- Valid SST GO ≥ 20, **and**
- Valid SST STOP ≥ 16,

the agent may end the SST block and mark it as “complete”.

Only **valid** trials (passing gaze and timing criteria) should count toward these thresholds. If thresholds are met, the SST block ends immediately, even if the nominal 60 trials have not all been presented.

---

## Metrics & Outputs

For each completed session, the agent logs: :contentReference[oaicite:4]{index=4}  

- **BaselineRTMean / BaselineRTSD**
  - Mean and SD of valid baseline GO saccadic reaction times.

- **GoRTMean / GoRTSD**
  - Mean and SD of GO RTs in the SST block.

- **GoRTSlowing**
  - Difference between SST GO RT mean and baseline RT mean.
  - Interpreted as a measure of proactive control (greater slowing → more proactive control).

- **StopAccuracy**
  - Percentage of STOP trials with successfully inhibited saccades.

- **SSRT (Stop Signal Reaction Time)**
  - Estimated using the integration method (Logan & Cowan, Hanes & Schall) applied to the GO RT distribution and STOP success rate, separately by direction when needed.

All metrics are computed only if per-session minimums are met. Sessions that do not meet thresholds are flagged as **low-confidence** and excluded from model training or clinical decisions.

---

## Design Constraints (Scientific)

The task must preserve the following core scientific features from Kelly et al. 2021: :contentReference[oaicite:5]{index=5}  

- Target eccentricity remains **12° horizontally**.
- Firefly remains a **step target**:
  - No continuous pursuit movement.
  - Optional short pop/ease-in animation at the new location is allowed, but no pre-trial motion cues.
- Owl remains fixed at the center during trials.
- STOP signal appears at the center after SSD and persists for the remainder of the trial.
- Saccade detection, corridor logic, and integration-method SSRT estimation are unchanged in principle; only counts, scheduling, fixation tolerances, and early-stop behavior are modified for toddler feasibility.

---

## UX & Coaching

To maximize data quality and completion rates, the agent should:

- Surface **calibration quality** (Good/OK/Poor) and block entry when calibration is poor.
- Expose **block progress** and approximate remaining duration.
- Provide **simple, child-friendly coaching** in response to repeated issues:
  - “Hold the iPad steady.”
  - “Keep your eyes on the owl.”
  - “We lost your eyes—try looking back at the owl.”
- Use **short micro-breaks** between blocks (and a mid-SST break) to reduce fatigue.
- Keep per-trial visual feedback light but present (e.g., a small success pulse when a trial counts).

---

## Usage Notes

- This agent is intended to run as a short, self-contained game session for toddlers and young children (~3–6 minutes).
- Multiple sessions per child (e.g., weekly) are expected; classifier models will use both per-session features and across-session trends.
- If a session does not meet the minimum valid trial counts, metrics are flagged as low-confidence and excluded from downstream modeling.
