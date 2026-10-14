import Foundation

struct FundHistoryPoint: Identifiable, Sendable {
    let timestamp: Int64
    let date: Date
    let netAssetValue: Double
    let dailyChangePercent: Double?

    var id: Int64 { timestamp }
}

enum FundTrendRange: String, CaseIterable, Identifiable {
    case thirtyDays
    case sixMonths
    case oneYear
    case threeYears
    case fiveYears
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .thirtyDays: return "30 天"
        case .sixMonths: return "半年"
        case .oneYear: return "1 年"
        case .threeYears: return "3 年"
        case .fiveYears: return "5 年"
        case .all: return "成立以来"
        }
    }

    func startDate(relativeTo endDate: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        switch self {
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -30, to: endDate)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: endDate)
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: endDate)
        case .threeYears:
            return calendar.date(byAdding: .year, value: -3, to: endDate)
        case .fiveYears:
            return calendar.date(byAdding: .year, value: -5, to: endDate)
        case .all:
            return nil
        }
    }
}

