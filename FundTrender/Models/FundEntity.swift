import SwiftData
import Foundation

enum FundCategory: String, Codable, CaseIterable {
    case holding = "我买的"
    case watchlist = "待观察"
}

@Model
class FundEntity {
    var code: String
    var name: String
    var category: String  // 存 FundCategory.rawValue
    var previousNav: Double
    var prevPreviousNav: Double
    var currentEstimate: Double
    var changePercent: Double
    var lastUpdated: Date?
    var addedAt: Date
    var sortOrder: Int

    init(code: String, name: String, category: FundCategory = .watchlist, previousNav: Double, currentEstimate: Double, changePercent: Double, sortOrder: Int) {
        self.code = code
        self.name = name
        self.category = category.rawValue
        self.previousNav = previousNav
        self.prevPreviousNav = 0
        self.currentEstimate = currentEstimate
        self.changePercent = changePercent
        self.lastUpdated = Date()
        self.addedAt = Date()
        self.sortOrder = sortOrder
    }
}
