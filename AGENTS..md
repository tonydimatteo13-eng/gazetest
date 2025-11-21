FireflyStopSignalAgent

Purpose
FireflyStopSignalAgent runs the owl–firefly oculomotor stop-signal task (SST) to estimate proactive and reactive inhibitory control in young children. It implements a short-form, toddler-feasible version of the oculomotor SST described by Kelly et al. 2021 (12° step targets; central STOP signal) while maintaining compatibility with our scoring and ASD-likeness models.

Task Structure

Blocks

Baseline Block

Trials: 10 GO-only trials.

Stimuli:

Central owl fixation cross.

Firefly (white circle) appears at ±12° horizontally.

Timing:

Fixation: 1500–2000 ms (jittered; extended if fixation unstable).

GO cue duration: up to 650 ms (deadline).

Instructions:

“Follow the firefly as fast as you can when it appears.”

Purpose:

Establish baseline visually guided saccade RT distribution.

Stop-Signal Block (SST)

Trials: up to 60 trials.

GO trials: 60% (~36)

STOP trials: 40% (~24)

Stimuli:

Central owl (fixation).

Firefly appears at ±12° as a step target.

STOP signal: stop sign held by the owl at center.

Timing:

Fixation: 1500–2000 ms (jittered).

GO cue: 12° left/right.

GO deadline: 650 ms.

SSD: 50–200 ms after GO onset, randomized each STOP trial.

Constraints:

Max 3 GO or STOP trials in a row.

Max 3 left or right trials in a row.

Instructions:

GO: “Follow the firefly.”

STOP: “If the owl shows a STOP sign, keep your eyes on the owl and do NOT look at the firefly.”

Total duration: ~4–6 minutes depending on child speed and early-stop logic.

Early-Stop Logic

To avoid over-long sessions while preserving data quality, the agent supports optional early termination of the SST block.

Minimum per-session valid data (for analysis):

Baseline: ≥ 8 valid GO trials.

SST: ≥ 20 valid GO trials and ≥ 16 valid STOP trials.

Heuristic early stop (if enableEarlyStop = true):

When:

Total SST trials ≥ 40, and

Valid SST GO ≥ 20, and

Valid SST STOP ≥ 16,

The agent may end the SST block and mark it as “complete.”

This keeps the protocol in the 3–6 minute range under typical conditions.

A future iteration may replace heuristic early stop with full Bayesian stopping rules (e.g., CI-based thresholds on stopping accuracy and GO RT slowing).

Metrics & Outputs

For each completed session, the agent logs:

BaselineRTMean / BaselineRTSD

Mean and SD of valid baseline GO saccadic reaction times.

GoRTMean / GoRTSD

Mean and SD of GO RTs in the SST block.

GoRTSlowing

Difference between SST GO RT mean and baseline RT mean.

Interpreted as a measure of proactive control (greater slowing → more proactive control).

StopAccuracy

Percentage of STOP trials with successfully inhibited saccades.

SSRT (Stop Signal Reaction Time)

Estimated using the integration method (Logan & Cowan, Hanes & Schall) applied to the GO RT distribution and STOP success rate, separately by direction when needed.

All metrics are computed only if per-session minimums are met.

Design Constraints (Scientific)

Target eccentricity remains 12° horizontally, matching Kelly et al. 2021.

Firefly remains a step target:

No continuous pursuit movement.

Optional short pop/ease-in animation at the new location is allowed, but no pre-trial motion.

Owl remains fixed at the center during trials.

STOP signal appears at the center after SSD and persists for the remainder of the trial.

Saccade detection, corridor logic, and integration-method SSRT estimation are unchanged in principle; only counts, scheduling, and optional early-stop behavior differ from the original long-form implementation.

Usage Notes

This agent is intended to run as a short, self-contained game session for toddlers and young children (~3–6 minutes).

Multiple sessions per child (e.g., weekly) are expected; classifier models will use both per-session features and across-session trends.

If a session does not meet the minimum valid trial counts, metrics are flagged as low-confidence and excluded from model training or clinical decisions.