import Foundation
import OSLog

enum FundHistoryError: LocalizedError {
    case invalidCode
    case invalidResponse
    case dataUnavailable
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "基金代码无效"
        case .invalidResponse: return "历史数据服务响应异常"
        case .dataUnavailable: return "暂无历史净值数据"
        case .parseError: return "历史净值数据解析失败"
        }
    }
}

actor FundHistoryService {
    static let shared = FundHistoryService()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FundTrender",
        category: "FundHistoryService"
    )
    private var cache: [String: [FundHistoryPoint]] = [:]

    func fetchHistory(code: String, forceRefresh: Bool = false) async throws -> [FundHistoryPoint] {
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw FundHistoryError.invalidCode
        }
        if !forceRefresh, let cached = cache[code] {
            return cached
        }

        guard let url = URL(string: "https://fund.eastmoney.com/pingzhongdata/\(code).js") else {
            throw FundHistoryError.invalidCode
        }
        var request = URLRequest(url: url)
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        request.timeoutInterval = 20
        request.setValue("https://fund.eastmoney.com/\(code).html", forHTTPHeaderField: "Referer")

        let startedAt = Date()
        Self.logger.debug("[History] request start code=\(code, privacy: .private) force=\(forceRefresh)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            Self.logger.error(
                "[History] request failed code=\(code, privacy: .private) error=\(String(describing: error), privacy: .private)"
            )
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            Self.logger.error("[History] invalid response code=\(code, privacy: .private)")
            throw FundHistoryError.invalidResponse
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw FundHistoryError.parseError
        }

        let points = try parseNetWorthTrend(text, expectedCode: code)
        guard !points.isEmpty else {
            throw FundHistoryError.dataUnavailable
        }
        cache[code] = points

        let elapsed = Date().timeIntervalSince(startedAt)
        Self.logger.info(
            "[History] request finished code=\(code, privacy: .private) count=\(points.count) bytes=\(data.count) elapsed=\(elapsed, format: .fixed(precision: 3))s"
        )
        return points
    }

    private func parseNetWorthTrend(_ text: String, expectedCode: String) throws -> [FundHistoryPoint] {
        guard text.contains("var fS_code = \"\(expectedCode)\";") else {
            Self.logger.error("[History] fund code mismatch expected=\(expectedCode, privacy: .private)")
            throw FundHistoryError.parseError
        }

        let marker = "var Data_netWorthTrend = "
        guard let markerRange = text.range(of: marker) else {
            throw FundHistoryError.parseError
        }
        let jsonStart = markerRange.upperBound
        guard let jsonEnd = text.range(of: "];", range: jsonStart..<text.endIndex) else {
            throw FundHistoryError.parseError
        }
        let json = String(text[jsonStart...jsonEnd.lowerBound])
        guard let jsonData = json.data(using: .utf8) else {
            throw FundHistoryError.parseError
        }

        let decoded: [RemoteHistoryPoint]
        do {
            decoded = try JSONDecoder().decode([RemoteHistoryPoint].self, from: jsonData)
        } catch {
            Self.logger.error("[History] decode failed error=\(String(describing: error), privacy: .private)")
            throw FundHistoryError.parseError
        }

        return decoded.compactMap { item in
            guard let value = item.y, value.isFinite, value > 0 else { return nil }
            return FundHistoryPoint(
                timestamp: item.x,
                date: Date(timeIntervalSince1970: TimeInterval(item.x) / 1_000),
                netAssetValue: value,
                dailyChangePercent: item.equityReturn?.isFinite == true ? item.equityReturn : nil
            )
        }
        .sorted { $0.timestamp < $1.timestamp }
    }
}

private struct RemoteHistoryPoint: Decodable {
    let x: Int64
    let y: Double?
    let equityReturn: Double?

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case equityReturn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Int64.self, forKey: .x)
        y = Self.decodeFlexibleDouble(from: container, forKey: .y)
        equityReturn = Self.decodeFlexibleDouble(from: container, forKey: .equityReturn)
    }

    private static func decodeFlexibleDouble(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(text)
        }
        return nil
    }
}
