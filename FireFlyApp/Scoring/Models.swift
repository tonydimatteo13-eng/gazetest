import Foundation

public enum AgeBucket: String, Codable, CaseIterable {
    case bucket18_24 = "18–24"
    case bucket25_34 = "25–34"
    case bucket35_44 = "35–44"
    case bucket45Plus = "45+"
    case preferNotToSay = "Prefer not to say"
}

public enum TrialBlock: String, Codable, CaseIterable {
    case baseline = "BL"
    case sst = "SST"
}

public enum TrialType: String, Codable, CaseIterable {
    case go = "GO"
    case stop = "STOP"
}

public enum TrialDirection: String, Codable, CaseIterable {
    case left = "L"
    case right = "R"
}

public enum TrialExclusion: String, Codable, CaseIterable {
    case anticipation
    case poorGaze
    case headMotion
    case lostTracking
}

public struct SessionMeta: Codable {
    public let sessionUID: UUID
    public let appVersion: String
    public let deviceModel: String
    public let osVersion: String
    public let viewingDistanceMeanCm: Double
    public let calibrationRMSEDeg: Double
    public let ageBucket: AgeBucket
    public let buildID: String

    public init(sessionUID: UUID, appVersion: String, deviceModel: String, osVersion: String, viewingDistanceMeanCm: Double, calibrationRMSEDeg: Double, ageBucket: AgeBucket, buildID: String) {
        self.sessionUID = sessionUID
        self.appVersion = appVersion
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.viewingDistanceMeanCm = viewingDistanceMeanCm
        self.calibrationRMSEDeg = calibrationRMSEDeg
        self.ageBucket = ageBucket
        self.buildID = buildID
    }
}

public struct Trial: Codable, Identifiable, Hashable {
    public var id: UUID = UUID()
    public let trialIndex: Int
    public let block: TrialBlock
    public let type: TrialType
    public let direction: TrialDirection
    public let goOnsetMs: Int
    public let ssdMs: Int?
    public let rtMs: Int?
    public let goSuccess: Bool
    public let stopSuccess: Bool
    public let gazeRMSEDeg: Double
    public let viewingDistanceCm: Double
    public let headMotionFlag: Bool
    public let lostTrackingFlag: Bool
    public let exclusions: [TrialExclusion]

    public init(id: UUID = UUID(), trialIndex: Int, block: TrialBlock, type: TrialType, direction: TrialDirection, goOnsetMs: Int, ssdMs: Int?, rtMs: Int?, goSuccess: Bool, stopSuccess: Bool, gazeRMSEDeg: Double, viewingDistanceCm: Double, headMotionFlag: Bool, lostTrackingFlag: Bool, exclusions: [TrialExclusion]) {
        self.id = id
        self.trialIndex = trialIndex
        self.block = block
        self.type = type
        self.direction = direction
        self.goOnsetMs = goOnsetMs
        self.ssdMs = ssdMs
        self.rtMs = rtMs
        self.goSuccess = goSuccess
        self.stopSuccess = stopSuccess
        self.gazeRMSEDeg = gazeRMSEDeg
        self.viewingDistanceCm = viewingDistanceCm
        self.headMotionFlag = headMotionFlag
        self.lostTrackingFlag = lostTrackingFlag
        self.exclusions = exclusions
    }
}

public struct Results: Codable {
    public let baselineRTMs: Double
    public let goRTMs: Double
    public let goRTSlowingMs: Double
    public let stoppingAccuracyPct: Double
    public let ssrtMs: Double
    public let pASDLike: Double
    public let proactiveZ: Double
    public let classificationLabel: ClassLabel
    public let includedBaselineGo: Int
    public let includedSSTGo: Int
    public let includedGo: Int
    public let includedStop: Int
    public let buildID: String

    public init(
        baselineRTMs: Double,
        goRTMs: Double,
        goRTSlowingMs: Double,
        stoppingAccuracyPct: Double,
        ssrtMs: Double,
        pASDLike: Double,
        proactiveZ: Double,
        classificationLabel: ClassLabel,
        includedBaselineGo: Int,
        includedSSTGo: Int,
        includedGo: Int,
        includedStop: Int,
        buildID: String
    ) {
        self.baselineRTMs = baselineRTMs
        self.goRTMs = goRTMs
        self.goRTSlowingMs = goRTSlowingMs
        self.stoppingAccuracyPct = stoppingAccuracyPct
        self.ssrtMs = ssrtMs
        self.pASDLike = pASDLike
        self.proactiveZ = proactiveZ
        self.classificationLabel = classificationLabel
        self.includedBaselineGo = includedBaselineGo
        self.includedSSTGo = includedSSTGo
        self.includedGo = includedGo
        self.includedStop = includedStop
        self.buildID = buildID
    }
}

public enum ClassLabel: String, Codable {
    case typicalLike = "Typical-like"
    case indeterminate = "Indeterminate"
    case asdLike = "ASD-like"
}
