import Foundation

public struct Scorer {
    struct Summary {
        let includedBaseline: [Trial]
        let includedSSTGo: [Trial]
        let includedStop: [Trial]
        let includedGoAll: [Trial]
    }

    public static func computeResults(session: SessionMeta, trials: [Trial]) -> Results {
        let summary = includedTrials(from: trials)
        let baselineRTs = summary.includedBaseline.compactMap { $0.rtMs.map(Double.init) }
        let sstGoRTs = summary.includedSSTGo.compactMap { $0.rtMs.map(Double.init) }
        let baselineMean = Statistics.mean(baselineRTs)
        let goMean = Statistics.mean(sstGoRTs)
        let slowing = goMean - baselineMean

        let stopTrials = summary.includedStop
        let totalStop = Double(stopTrials.count)
        let failedStop = stopTrials.filter { !$0.stopSuccess }.count
        let stopAccuracy = totalStop > 0 ? (1 - Double(failedStop) / totalStop) * 100.0 : .nan

        let pFail = totalStop > 0 ? Double(failedStop) / totalStop : 0
        let ssds = stopTrials.compactMap { $0.ssdMs.map(Double.init) }
        let ssrtValue = ssrt(goRTs: sstGoRTs, ssds: ssds, pFail: pFail)

        let bayes = bayesASDLike(stopAcc: stopAccuracy, slowingMs: slowing)
        let proactive = proactiveZ(stopAcc: stopAccuracy, slowing: slowing)

        return Results(
            baselineRTMs: baselineMean,
            goRTMs: goMean,
            goRTSlowingMs: slowing,
            stoppingAccuracyPct: stopAccuracy,
            ssrtMs: ssrtValue,
            pASDLike: bayes.p,
            proactiveZ: proactive,
            classificationLabel: bayes.label,
            includedBaselineGo: summary.includedBaseline.count,
            includedSSTGo: summary.includedSSTGo.count,
            includedGo: summary.includedGoAll.count,
            includedStop: summary.includedStop.count,
            buildID: session.buildID
        )
    }

    private static func includedTrials(from trials: [Trial]) -> Summary {
        let included: [Trial] = trials.filter { trial in
            if trial.block == .training { return false }
            guard !trial.headMotionFlag, !trial.lostTrackingFlag else { return false }
            if trial.gazeRMSEDeg > 2.5 { return false }
            if let rt = trial.rtMs, rt < 100 { return false }
            return true
        }

        let baseline = included.filter { $0.block == .baseline && $0.type == .go && $0.goSuccess }
        let sstGo = included.filter { $0.block == .sst && $0.type == .go && $0.goSuccess }
        let stop = included.filter { $0.block == .sst && $0.type == .stop }
        let goAll = included.filter { $0.block != .training && $0.type == .go && $0.goSuccess }
        return Summary(includedBaseline: baseline, includedSSTGo: sstGo, includedStop: stop, includedGoAll: goAll)
    }

    public static func ssrt(goRTs: [Double], ssds: [Double], pFail: Double) -> Double {
        guard !goRTs.isEmpty, !ssds.isEmpty else { return .nan }
        let meanSSD = Statistics.mean(ssds)
        let rtStar = Statistics.percentile(goRTs, percentile: pFail)
        return rtStar - meanSSD
    }

    public static func bayesASDLike(stopAcc: Double, slowingMs: Double) -> (p: Double, label: ClassLabel, z: Double) {
        let stopAccTD = gaussian(value: stopAcc, mean: 69, sd: 15)
        let stopAccASD = gaussian(value: stopAcc, mean: 62, sd: 17)
        let slowingTD = gaussian(value: slowingMs, mean: 99, sd: 53)
        let slowingASD = gaussian(value: slowingMs, mean: 73, sd: 50)

        let td = stopAccTD * slowingTD
        let asd = stopAccASD * slowingASD
        let exponent = 2.0 // amplify separation between likelihoods
        let tdWeighted = pow(td, exponent)
        let asdWeighted = pow(asd, exponent)
        let total = tdWeighted + asdWeighted
        let probability = total > 0 ? asdWeighted / total : 0.5
        let label: ClassLabel
        if probability >= 0.70 {
            label = .asdLike
        } else if probability <= 0.30 {
            label = .typicalLike
        } else {
            label = .indeterminate
        }
        let proactive = proactiveZ(stopAcc: stopAcc, slowing: slowingMs)
        return (p: probability, label: label, z: proactive)
    }

    private static func gaussian(value: Double, mean: Double, sd: Double) -> Double {
        guard sd > 0 else { return 0 }
        let exponent = -pow(value - mean, 2) / (2 * pow(sd, 2))
        return (1.0 / (sd * sqrt(2 * .pi))) * exp(exponent)
    }

    private static func proactiveZ(stopAcc: Double, slowing: Double) -> Double {
        let zStop = Statistics.zScore(value: stopAcc, mean: 69, sd: 15)
        let zSlowing = Statistics.zScore(value: slowing, mean: 99, sd: 53)
        return (zStop + zSlowing) / 2.0
    }
}
