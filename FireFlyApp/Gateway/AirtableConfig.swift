import Foundation

public struct AirtableConfig {
    public let uploadEnabled: Bool
    public let useProxy: Bool
    public let baseURL: URL
    public let baseID: String
    public let tableSessions: String
    public let tableTrials: String
    public let tableResults: String
    public let apiKey: String?

    public static func fromBundle(_ bundle: Bundle = .main) -> AirtableConfig? {
        guard let info = bundle.infoDictionary else { return nil }
        guard let baseId = info["AIRTABLE_BASE_ID"] as? String,
              let sessions = info["AIRTABLE_TABLE_SESSIONS"] as? String,
              let trials = info["AIRTABLE_TABLE_TRIALS"] as? String,
              let results = info["AIRTABLE_TABLE_RESULTS"] as? String,
              let baseURLString = info["API_BASE_URL"] as? String,
              let url = URL(string: baseURLString) else {
            return nil
        }
        let enabled = (info["UPLOAD_ENABLED"] as? String)?.uppercased() == "YES"
        let proxy = (info["USE_PROXY"] as? String)?.uppercased() != "NO"
        let apiKey = info["AIRTABLE_PAT"] as? String
        return AirtableConfig(
            uploadEnabled: enabled,
            useProxy: proxy,
            baseURL: url,
            baseID: baseId,
            tableSessions: sessions,
            tableTrials: trials,
            tableResults: results,
            apiKey: apiKey
        )
    }
}
