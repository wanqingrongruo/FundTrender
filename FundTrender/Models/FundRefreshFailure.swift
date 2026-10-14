import Foundation

struct FundRefreshFailure: Identifiable {
    let id = UUID()
    let code: String
    let name: String
    let reason: String
}
