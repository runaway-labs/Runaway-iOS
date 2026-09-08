import Foundation

struct TwinInsight: Codable {
    let acwr: Double
    let hrvTrend: Double
    let readiness: Int
    let twinStatus: String
    let insight: InsightDetail
    
    struct InsightDetail: Codable {
        let message: String
        let action: String
    }
    
    enum CodingKeys: String, CodingKey {
        case acwr
        case hrvTrend = "hrv_trend"
        case readiness
        case twinStatus = "twin_status"
        case insight
    }
}

class TwinEngineService {
    static let shared = TwinEngineService()
    
    struct TwinEngineBody: Encodable {
        let athlete_id: Int
    }
    
    func fetchTwinInsights() async throws -> TwinInsight {
        throw LocalIntelligenceBoundaryError.retiredCloudTwin
    }
}

enum LocalIntelligenceBoundaryError: LocalizedError {
    case retiredCloudTwin
    case retiredCloudAnalysis

    var errorDescription: String? {
        switch self {
        case .retiredCloudTwin:
            return "The retired cloud twin is unavailable. Runaway now builds training guidance privately on this device."
        case .retiredCloudAnalysis:
            return "Cloud analysis has been retired. Runaway now generates intelligence privately on this device."
        }
    }
}
