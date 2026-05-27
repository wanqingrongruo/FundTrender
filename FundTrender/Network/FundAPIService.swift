import Foundation

enum FundAPIError: LocalizedError {
    case invalidCode
    case parseError
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "基金代码无效或不存在"
        case .parseError: return "数据解析失败"
        case .networkError(let e): return e.localizedDescription
        }
    }
}

struct FundAPIService {
    static let shared = FundAPIService()

    func fetchQuote(code: String) async throws -> FundQuote {
        guard let url = URL(string: "https://fundgz.1234567.com.cn/js/\(code).js") else {
            throw FundAPIError.invalidCode
        }
        var request = URLRequest(url: url)
        request.setValue("https://fund.eastmoney.com", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw FundAPIError.invalidCode
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw FundAPIError.parseError
        }
        return try parseJSONP(text)
    }

    private func parseJSONP(_ text: String) throws -> FundQuote {
        // 提取 jsonpgz({...}); 中的 JSON 部分
        let pattern = #"jsonpgz\((\{.+\})\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            throw FundAPIError.parseError
        }
        let json = String(text[range])
        guard let jsonData = json.data(using: .utf8),
              let quote = try? JSONDecoder().decode(FundQuote.self, from: jsonData) else {
            throw FundAPIError.parseError
        }
        return quote
    }
}
